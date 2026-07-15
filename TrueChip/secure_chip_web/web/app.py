"""
Secure Chip Web Portal
=======================

Two audiences, one database (same secure_chip.db used by mock_server.py):

1. Public lookup portal ("/", "/lookup")
   - No login required.
   - Consumers type the UID printed / encoded on the product's QR code.
   - Shows product / manufacturer info if the UID exists and is active.
   - This is a *basic* lookup (UID -> product info). It does NOT prove the
     physical chip is genuine by itself -- that requires the cryptographic
     challenge/response flow in chip_tester.py / mock_server.py's /verify
     endpoint, which needs a real UART/NFC reader talking to the chip.
     The lookup page clearly labels this distinction for the user.

2. Manufacturer dashboard ("/login", "/register", "/dashboard/*")
   - Login required (session-based auth, salted+hashed passwords).
   - A manufacturer account can register new chips, edit existing ones,
     enable/disable chips, and see recent lookup activity for their chips.

This file is additive: it does not remove or break mock_server.py's
/verify JSON API used by chip_tester.py and demo_scenarios.py. Run this
app on a separate port (default 5050) alongside mock_server.py (5000),
or merge the /verify route in yourself if you want a single process.
"""

from __future__ import annotations

import functools
import os
import secrets
import sqlite3
import sys
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Optional

from flask import Flask, flash, g, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

# Allow running this script directly (python web/app.py) while the shared
# crypto/protocol helpers live one level up, in common/.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "common"))

from secure_chip_common import (
    UID_LEN,
    SecureChipError,
    normalize_hex,
    to_hex,
)

DEFAULT_DB_PATH = Path(__file__).resolve().parent.parent / "data" / "secure_chip.db"
DB_PATH = os.environ.get("SECURE_CHIP_DB", str(DEFAULT_DB_PATH))

app = Flask(__name__)
app.secret_key = os.environ.get("SECURE_CHIP_WEB_SECRET") or secrets.token_hex(32)


# --------------------------------------------------------------------------
# Database
# --------------------------------------------------------------------------

@contextmanager
def db_conn():
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    """Create tables used by mock_server.py (if missing) plus the web-portal tables."""
    with db_conn() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS chips (
                uid TEXT PRIMARY KEY,
                secret_key TEXT NOT NULL,
                product TEXT NOT NULL,
                manufacturer TEXT NOT NULL,
                pack_date TEXT NOT NULL,
                active INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS used_nonces (
                uid TEXT NOT NULL,
                nonce TEXT NOT NULL,
                used_at INTEGER NOT NULL,
                PRIMARY KEY (uid, nonce),
                FOREIGN KEY(uid) REFERENCES chips(uid)
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS manufacturers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                display_name TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS scan_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uid TEXT NOT NULL,
                authentic INTEGER NOT NULL,
                reason TEXT,
                scanned_at INTEGER NOT NULL
            )
            """
        )
        # Migration: add manufacturer_id to chips if this DB pre-dates the portal.
        cols = [r["name"] for r in conn.execute("PRAGMA table_info(chips)").fetchall()]
        if "manufacturer_id" not in cols:
            conn.execute("ALTER TABLE chips ADD COLUMN manufacturer_id INTEGER REFERENCES manufacturers(id)")


# --------------------------------------------------------------------------
# Auth helpers
# --------------------------------------------------------------------------

def current_manufacturer() -> Optional[sqlite3.Row]:
    if "manufacturer_id" not in session:
        return None
    if not hasattr(g, "_mfr_loaded"):
        with db_conn() as conn:
            g._mfr_cache = conn.execute(
                "SELECT * FROM manufacturers WHERE id = ?", (session["manufacturer_id"],)
            ).fetchone()
        g._mfr_loaded = True
    return g._mfr_cache


def login_required(view):
    @functools.wraps(view)
    def wrapped(*args, **kwargs):
        if current_manufacturer() is None:
            flash("Vui lòng đăng nhập để tiếp tục.", "error")
            return redirect(url_for("login", next=request.path))
        return view(*args, **kwargs)
    return wrapped


@app.context_processor
def inject_globals():
    return {"current_manufacturer": current_manufacturer()}


# --------------------------------------------------------------------------
# Public: home + lookup portal
# --------------------------------------------------------------------------

@app.route("/")
def home():
    with db_conn() as conn:
        stats = {
            "chip_count": conn.execute("SELECT COUNT(*) c FROM chips WHERE active = 1").fetchone()["c"],
            "scan_count": conn.execute("SELECT COUNT(*) c FROM scan_logs").fetchone()["c"],
        }
    return render_template("home.html", stats=stats)


def _format_ts(ts: Optional[int]) -> Optional[str]:
    if not ts:
        return None
    return time.strftime("%d/%m/%Y %H:%M", time.localtime(ts))


def _run_lookup(uid_raw: str) -> dict:
    """Normalize a UID string, check it against the DB, log the attempt, and
    return a result dict shaped like the one shown on the lookup page.

    Reuse is allowed by design (a chip stays valid on every scan until the
    manufacturer disables it). For transparency, an authentic result also
    reports how many times this UID has been scanned successfully before
    and when the most recent prior scan happened, so the person looking it
    up can judge for themselves if something looks off (e.g. a brand-new
    purchase that already shows hundreds of prior scans).
    """
    uid_hex = ""
    try:
        uid = normalize_hex(uid_raw, UID_LEN, "Mã UID")
        uid_hex = to_hex(uid)

        with db_conn() as conn:
            chip = conn.execute("SELECT * FROM chips WHERE uid = ?", (uid_hex,)).fetchone()

            if chip is None:
                result = {"authentic": False, "reason": "Không tìm thấy mã này trong hệ thống."}
            elif int(chip["active"]) != 1:
                result = {"authentic": False, "reason": "Chip này đã bị nhà sản xuất vô hiệu hóa."}
            else:
                prior = conn.execute(
                    "SELECT COUNT(*) AS c, MAX(scanned_at) AS last FROM scan_logs WHERE uid = ? AND authentic = 1",
                    (uid_hex,),
                ).fetchone()
                prior_count = int(prior["c"] or 0)
                result = {
                    "authentic": True,
                    "uid": uid_hex,
                    "product": chip["product"],
                    "manufacturer": chip["manufacturer"],
                    "pack_date": chip["pack_date"],
                    "scan_count": prior_count + 1,
                    "previous_scan_at": _format_ts(prior["last"]),
                }

            conn.execute(
                "INSERT INTO scan_logs(uid, authentic, reason, scanned_at) VALUES (?, ?, ?, ?)",
                (uid_hex, int(bool(result.get("authentic"))), result.get("reason"), int(time.time())),
            )
    except SecureChipError as exc:
        result = {"authentic": False, "reason": str(exc)}

    return result


@app.route("/lookup", methods=["GET", "POST"])
def lookup():
    result = None
    submitted_uid = ""

    if request.method == "POST":
        submitted_uid = (request.form.get("uid") or "").strip()
        result = _run_lookup(submitted_uid)
    else:
        # A QR code that encodes the full URL (e.g. http://host/lookup?uid=XXXX)
        # lands here directly when scanned by any phone camera app — no JS needed.
        deep_link_uid = (request.args.get("uid") or "").strip()
        if deep_link_uid:
            submitted_uid = deep_link_uid
            result = _run_lookup(deep_link_uid)

    return render_template("lookup.html", result=result, submitted_uid=submitted_uid)


# --------------------------------------------------------------------------
# Auth: register / login / logout
# --------------------------------------------------------------------------

@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        username = (request.form.get("username") or "").strip().lower()
        display_name = (request.form.get("display_name") or "").strip()
        password = request.form.get("password") or ""
        confirm = request.form.get("confirm") or ""

        error = None
        if not username or not display_name or not password:
            error = "Vui lòng điền đầy đủ thông tin."
        elif len(password) < 8:
            error = "Mật khẩu cần tối thiểu 8 ký tự."
        elif password != confirm:
            error = "Mật khẩu xác nhận không khớp."

        if error is None:
            try:
                with db_conn() as conn:
                    conn.execute(
                        "INSERT INTO manufacturers(username, password_hash, display_name, created_at) VALUES (?, ?, ?, ?)",
                        (username, generate_password_hash(password), display_name, int(time.time())),
                    )
            except sqlite3.IntegrityError:
                error = "Tên đăng nhập đã tồn tại."
            else:
                flash("Tạo tài khoản thành công. Vui lòng đăng nhập.", "success")
                return redirect(url_for("login"))

        flash(error, "error")

    return render_template("register.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = (request.form.get("username") or "").strip().lower()
        password = request.form.get("password") or ""

        with db_conn() as conn:
            mfr = conn.execute("SELECT * FROM manufacturers WHERE username = ?", (username,)).fetchone()

        if mfr is None or not check_password_hash(mfr["password_hash"], password):
            flash("Sai tên đăng nhập hoặc mật khẩu.", "error")
        else:
            session.clear()
            session["manufacturer_id"] = mfr["id"]
            flash(f"Chào mừng trở lại, {mfr['display_name']}.", "success")
            return redirect(request.args.get("next") or url_for("dashboard"))

    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    flash("Đã đăng xuất.", "success")
    return redirect(url_for("home"))


# --------------------------------------------------------------------------
# Manufacturer dashboard
# --------------------------------------------------------------------------

@app.route("/dashboard")
@login_required
def dashboard():
    mfr = current_manufacturer()
    with db_conn() as conn:
        chips = conn.execute(
            "SELECT * FROM chips WHERE manufacturer_id = ? ORDER BY created_at DESC", (mfr["id"],)
        ).fetchall()
        chip_uids = [c["uid"] for c in chips]
        recent_scans = []
        if chip_uids:
            placeholders = ",".join("?" for _ in chip_uids)
            recent_scans = conn.execute(
                f"SELECT * FROM scan_logs WHERE uid IN ({placeholders}) ORDER BY scanned_at DESC LIMIT 15",
                chip_uids,
            ).fetchall()

        stats = {
            "total": len(chips),
            "active": sum(1 for c in chips if int(c["active"]) == 1),
            "scans": len(recent_scans),
        }

    return render_template("dashboard.html", chips=chips, recent_scans=recent_scans, stats=stats)


@app.route("/dashboard/chips/new", methods=["GET", "POST"])
@login_required
def chip_new():
    mfr = current_manufacturer()
    suggested_uid = to_hex(secrets.token_bytes(UID_LEN))
    suggested_key = to_hex(secrets.token_bytes(16))

    if request.method == "POST":
        try:
            uid = normalize_hex(request.form.get("uid", ""), UID_LEN, "UID")
            key = normalize_hex(request.form.get("key", ""), 16, "Khóa AES")
            product = (request.form.get("product") or "").strip()
            pack_date = (request.form.get("pack_date") or "").strip()
            active = 1 if request.form.get("active") == "on" else 0

            if not product:
                raise SecureChipError("Tên sản phẩm là bắt buộc.")
            if not pack_date:
                raise SecureChipError("Ngày đóng gói là bắt buộc.")

            with db_conn() as conn:
                conn.execute(
                    """
                    INSERT INTO chips(uid, secret_key, product, manufacturer, pack_date, active, created_at, manufacturer_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        to_hex(uid), to_hex(key), product, mfr["display_name"], pack_date,
                        active, int(time.time()), mfr["id"],
                    ),
                )
            flash("Đã đăng ký chip mới.", "success")
            return redirect(url_for("dashboard"))
        except SecureChipError as exc:
            flash(str(exc), "error")
        except sqlite3.IntegrityError:
            flash("UID này đã tồn tại trong hệ thống.", "error")

    return render_template("chip_form.html", mode="new", chip=None,
                            suggested_uid=suggested_uid, suggested_key=suggested_key)


@app.route("/dashboard/chips/<uid>/edit", methods=["GET", "POST"])
@login_required
def chip_edit(uid: str):
    mfr = current_manufacturer()
    with db_conn() as conn:
        chip = conn.execute(
            "SELECT * FROM chips WHERE uid = ? AND manufacturer_id = ?", (uid.upper(), mfr["id"])
        ).fetchone()

    if chip is None:
        flash("Không tìm thấy chip hoặc bạn không có quyền chỉnh sửa.", "error")
        return redirect(url_for("dashboard"))

    if request.method == "POST":
        try:
            product = (request.form.get("product") or "").strip()
            pack_date = (request.form.get("pack_date") or "").strip()
            active = 1 if request.form.get("active") == "on" else 0

            if not product:
                raise SecureChipError("Tên sản phẩm là bắt buộc.")
            if not pack_date:
                raise SecureChipError("Ngày đóng gói là bắt buộc.")

            with db_conn() as conn:
                conn.execute(
                    "UPDATE chips SET product = ?, pack_date = ?, active = ? WHERE uid = ? AND manufacturer_id = ?",
                    (product, pack_date, active, chip["uid"], mfr["id"]),
                )
            flash("Đã cập nhật thông tin chip.", "success")
            return redirect(url_for("dashboard"))
        except SecureChipError as exc:
            flash(str(exc), "error")

    return render_template("chip_form.html", mode="edit", chip=chip,
                            suggested_uid=None, suggested_key=None)


# --------------------------------------------------------------------------

if __name__ == "__main__":
    init_db()
    port = int(os.environ.get("SECURE_CHIP_WEB_PORT", "5050"))
    host = os.environ.get("SECURE_CHIP_WEB_HOST", "127.0.0.1")
    print(f"Secure Chip Web Portal running on http://{host}:{port}")
    print(f"Database: {DB_PATH}")
    app.run(host=host, port=port, debug=bool(os.environ.get("SECURE_CHIP_WEB_DEBUG")))
