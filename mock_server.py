"""
Secure Chip Flask verification server.

This replaces the old demo-only server:
- No hard-coded UID, product, or secret key.
- Uses SQLite as the chip database.
- Blocks replay by storing used UID + nonce pairs.
- Keeps the AES key only on the server side.

Typical use:
    python mock_server.py init-db
    python mock_server.py register-chip --uid <REAL_UID_HEX> --key <REAL_AES128_KEY_HEX> \
        --product "<PRODUCT_NAME>" --manufacturer "<MANUFACTURER>" --pack-date "<DATE>"
    python mock_server.py serve --host 0.0.0.0 --port 5000
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import sys
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

# Allow running this script directly (python server/mock_server.py) while the
# shared crypto/protocol helpers live one level up, in common/.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "common"))

from flask import Flask, jsonify, request

from secure_chip_common import (
    NONCE_LEN,
    RESPONSE_LEN,
    UID_LEN,
    SecureChipError,
    compute_response,
    normalize_hex,
    to_hex,
)
import hmac

DEFAULT_DB_PATH = Path(__file__).resolve().parent.parent / "data" / "secure_chip.db"
DB_PATH = os.environ.get("SECURE_CHIP_DB", str(DEFAULT_DB_PATH))
NONCE_TTL_SECONDS = int(os.environ.get("SECURE_CHIP_NONCE_TTL_SECONDS", str(7 * 24 * 60 * 60)))

app = Flask(__name__)


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
        conn.execute("CREATE INDEX IF NOT EXISTS idx_used_nonces_used_at ON used_nonces(used_at)")


def cleanup_old_nonces(conn: sqlite3.Connection) -> None:
    cutoff = int(time.time()) - NONCE_TTL_SECONDS
    conn.execute("DELETE FROM used_nonces WHERE used_at < ?", (cutoff,))


def register_chip(uid_hex: str, key_hex: str, product: str, manufacturer: str, pack_date: str, active: bool = True) -> None:
    uid = normalize_hex(uid_hex, UID_LEN, "uid")
    key = normalize_hex(key_hex, 16, "key")
    if not product.strip():
        raise SecureChipError("product is required")
    if not manufacturer.strip():
        raise SecureChipError("manufacturer is required")
    if not pack_date.strip():
        raise SecureChipError("pack_date is required")

    init_db()
    with db_conn() as conn:
        conn.execute(
            """
            INSERT INTO chips(uid, secret_key, product, manufacturer, pack_date, active, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(uid) DO UPDATE SET
                secret_key=excluded.secret_key,
                product=excluded.product,
                manufacturer=excluded.manufacturer,
                pack_date=excluded.pack_date,
                active=excluded.active
            """,
            (to_hex(uid), to_hex(key), product.strip(), manufacturer.strip(), pack_date.strip(), int(active), int(time.time())),
        )


def get_chip(conn: sqlite3.Connection, uid_hex: str) -> Optional[sqlite3.Row]:
    return conn.execute("SELECT * FROM chips WHERE uid = ?", (uid_hex,)).fetchone()


def reserve_nonce_once(conn: sqlite3.Connection, uid_hex: str, nonce_hex: str) -> bool:
    """
    Store nonce before returning a verification result.
    Returns False when the same UID + nonce was already used.
    """
    try:
        conn.execute(
            "INSERT INTO used_nonces(uid, nonce, used_at) VALUES (?, ?, ?)",
            (uid_hex, nonce_hex, int(time.time())),
        )
        return True
    except sqlite3.IntegrityError:
        return False


def verify_payload(data: Dict[str, Any]) -> Tuple[Dict[str, Any], int]:
    try:
        uid = normalize_hex(str(data.get("uid", "")), UID_LEN, "uid")
        nonce = normalize_hex(str(data.get("nonce", "")), NONCE_LEN, "nonce")
        response = normalize_hex(str(data.get("response", "")), RESPONSE_LEN, "response")
    except SecureChipError as exc:
        return {"authentic": False, "reason": str(exc)}, 400

    uid_hex = to_hex(uid)
    nonce_hex = to_hex(nonce)

    with db_conn() as conn:
        cleanup_old_nonces(conn)
        chip = get_chip(conn, uid_hex)

        if chip is None:
            app.logger.info("FAKE: UID not found: %s...", uid_hex[:8])
            return {"authentic": False, "reason": "UID không tồn tại trong database"}, 200

        if int(chip["active"]) != 1:
            app.logger.info("FAKE: UID disabled: %s...", uid_hex[:8])
            return {"authentic": False, "reason": "Chip đã bị vô hiệu hóa trong database"}, 200

        if not reserve_nonce_once(conn, uid_hex, nonce_hex):
            app.logger.warning("REPLAY blocked: UID=%s..., nonce=%s...", uid_hex[:8], nonce_hex[:8])
            return {"authentic": False, "reason": "Nonce đã được sử dụng — nghi ngờ replay attack"}, 200

        secret_key = normalize_hex(chip["secret_key"], 16, "secret_key")
        expected = compute_response(uid, nonce, secret_key)

        if hmac.compare_digest(response, expected):
            app.logger.info("AUTHENTIC: UID=%s...", uid_hex[:8])
            return {
                "authentic": True,
                "uid": uid_hex,
                "product": chip["product"],
                "manufacturer": chip["manufacturer"],
                "pack_date": chip["pack_date"],
            }, 200

        app.logger.info("FAKE: response mismatch: UID=%s...", uid_hex[:8])
        return {"authentic": False, "reason": "Response không khớp — chip giả hoặc secret key sai"}, 200


@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "service": "Secure Chip Verification Server",
        "status": "running",
        "verify_endpoint": "/verify",
    })


@app.route("/health", methods=["GET"])
def health():
    try:
        init_db()
        with db_conn() as conn:
            chip_count = conn.execute("SELECT COUNT(*) AS c FROM chips WHERE active = 1").fetchone()["c"]
        return jsonify({"ok": True, "active_chips": chip_count})
    except Exception as exc:  # pragma: no cover - operational endpoint
        return jsonify({"ok": False, "error": str(exc)}), 500


@app.route("/verify", methods=["POST"])
def verify():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"authentic": False, "reason": "Request body phải là JSON"}), 400

    result, status = verify_payload(data)
    return jsonify(result), status


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Secure Chip Flask verification server")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("init-db", help="Create or update the SQLite schema")

    reg = sub.add_parser("register-chip", help="Register/update a real chip in the server database")
    reg.add_argument("--uid", required=True, help="Real chip UID, 16 bytes / 32 hex chars")
    reg.add_argument("--key", required=True, help="Real AES-128 key burned into the FPGA/key ROM, 16 bytes / 32 hex chars")
    reg.add_argument("--product", required=True, help="Product name stored in database")
    reg.add_argument("--manufacturer", required=True, help="Manufacturer name stored in database")
    reg.add_argument("--pack-date", required=True, help="Packaging/manufacturing date shown after authentication")
    reg.add_argument("--inactive", action="store_true", help="Register but mark chip inactive")

    serve = sub.add_parser("serve", help="Run the Flask server")
    serve.add_argument("--host", default=os.environ.get("SECURE_CHIP_HOST", "127.0.0.1"))
    serve.add_argument("--port", type=int, default=int(os.environ.get("SECURE_CHIP_PORT", "5000")))
    serve.add_argument("--debug", action="store_true")

    return parser


def main() -> None:
    parser = build_arg_parser()
    args = parser.parse_args()

    command = args.command or "serve"

    if command == "init-db":
        init_db()
        print(f"Database initialized: {DB_PATH}")
        return

    if command == "register-chip":
        register_chip(
            uid_hex=args.uid,
            key_hex=args.key,
            product=args.product,
            manufacturer=args.manufacturer,
            pack_date=args.pack_date,
            active=not args.inactive,
        )
        print("Chip registered/updated successfully")
        return

    if command == "serve":
        host = getattr(args, "host", os.environ.get("SECURE_CHIP_HOST", "127.0.0.1"))
        port = getattr(args, "port", int(os.environ.get("SECURE_CHIP_PORT", "5000")))
        debug = getattr(args, "debug", False)

        init_db()
        print(f"Secure Chip Verification Server running on http://{host}:{port}")
        print(f"Database: {DB_PATH}")
        app.run(host=host, port=port, debug=debug)
        return

    parser.print_help()

if __name__ == '__main__':
    # 0.0.0.0 để Server mở cửa ra Internet
    app.run(host='0.0.0.0', port=5000, debug=False)
