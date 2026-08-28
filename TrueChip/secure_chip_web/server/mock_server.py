"""
Secure Chip Flask verification server (PostgreSQL Edition).
"""
from __future__ import annotations
import os
import sys
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

import psycopg2
from psycopg2.extras import RealDictCursor
from flask import Flask, jsonify, request
import hmac

# Trỏ đường dẫn đến thư mục common
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "common"))

from secure_chip_common import (
    NONCE_LEN, RESPONSE_LEN, UID_LEN, SecureChipError,
    compute_response, normalize_hex, to_hex,
)

# Lấy đường link Database từ Render Environment
DATABASE_URL = os.environ.get("DATABASE_URL")
NONCE_TTL_SECONDS = int(os.environ.get("SECURE_CHIP_NONCE_TTL_SECONDS", str(7 * 24 * 60 * 60)))

app = Flask(__name__)

@contextmanager
def db_conn():
    if not DATABASE_URL:
        raise RuntimeError("THIẾU DATABASE_URL! Hãy cấu hình trên Render Environment.")
    # Kết nối tới PostgreSQL
    conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()

def init_db() -> None:
    if not DATABASE_URL:
        return
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS chips (
                    uid VARCHAR(32) PRIMARY KEY,
                    secret_key VARCHAR(32) NOT NULL,
                    product VARCHAR(255) NOT NULL,
                    manufacturer VARCHAR(255) NOT NULL,
                    pack_date VARCHAR(255) NOT NULL,
                    active INTEGER NOT NULL DEFAULT 1,
                    created_at BIGINT NOT NULL
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS used_nonces (
                    uid VARCHAR(32) NOT NULL,
                    nonce VARCHAR(32) NOT NULL,
                    used_at BIGINT NOT NULL,
                    PRIMARY KEY (uid, nonce),
                    FOREIGN KEY(uid) REFERENCES chips(uid)
                )
            """)
            cur.execute("CREATE INDEX IF NOT EXISTS idx_used_nonces_used_at ON used_nonces(used_at)")

# Chạy tạo bảng khi khởi động Server.
#
# v7.1: init_db() used to run bare at import time.  If PostgreSQL was not
# reachable yet (a very normal situation on Render, where the web service can
# boot before the database finishes provisioning), the exception propagated
# out of module import and killed the gunicorn worker immediately - the
# service then looked "down" rather than "waiting for the DB".
#
# Now a failure here is logged and the process stays alive; /verify will
# surface the real error per request, and the tables are created lazily on
# the first successful connection.
_DB_READY = False


def ensure_db_ready() -> None:
    global _DB_READY
    if _DB_READY:
        return
    init_db()
    _DB_READY = True


with app.app_context():
    try:
        ensure_db_ready()
    except Exception as exc:  # noqa: BLE001 - startup must never kill the worker
        app.logger.warning(
            "init_db() failed at startup (%s). Server is up; will retry on first request.",
            exc,
        )

def cleanup_old_nonces(conn) -> None:
    cutoff = int(time.time()) - NONCE_TTL_SECONDS
    with conn.cursor() as cur:
        cur.execute("DELETE FROM used_nonces WHERE used_at < %s", (cutoff,))

def get_chip(conn, uid_hex: str) -> Optional[Dict]:
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM chips WHERE uid = %s", (uid_hex,))
        return cur.fetchone()

def reserve_nonce_once(conn, uid_hex: str, nonce_hex: str) -> bool:
    # Avoid catching IntegrityError without a rollback: PostgreSQL would leave
    # the whole transaction aborted. ON CONFLICT DO NOTHING keeps the
    # transaction healthy and still gives an atomic one-time reservation.
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO used_nonces(uid, nonce, used_at)
            VALUES (%s, %s, %s)
            ON CONFLICT (uid, nonce) DO NOTHING
            RETURNING nonce
            """,
            (uid_hex, nonce_hex, int(time.time())),
        )
        return cur.fetchone() is not None

def verify_payload(data: Dict[str, Any]) -> Tuple[Dict[str, Any], int]:
    try:
        uid = normalize_hex(str(data.get("uid", "")), UID_LEN, "uid")
        nonce = normalize_hex(str(data.get("nonce", "")), NONCE_LEN, "nonce")
        response = normalize_hex(str(data.get("response", "")), RESPONSE_LEN, "response")
    except SecureChipError as exc:
        return {"authentic": False, "reason": str(exc)}, 400

    uid_hex = to_hex(uid)
    nonce_hex = to_hex(nonce)

    # Lazily finish the schema setup if the startup attempt failed.
    try:
        ensure_db_ready()
    except Exception as exc:  # noqa: BLE001
        app.logger.error("Database not available: %s", exc)
        return {"authentic": False, "reason": "Verification database chưa sẵn sàng"}, 503

    with db_conn() as conn:
        cleanup_old_nonces(conn)
        chip = get_chip(conn, uid_hex)

        if chip is None:
            app.logger.info("FAKE: UID not found: %s...", uid_hex[:8])
            return {"authentic": False, "reason": "UID không tồn tại trong database"}, 200

        if int(chip["active"]) != 1:
            app.logger.info("FAKE: UID disabled: %s...", uid_hex[:8])
            return {"authentic": False, "reason": "Chip đã bị vô hiệu hóa trong database"}, 200

        # v7.1: a malformed secret_key column (wrong length, stray characters,
        # a half-finished provisioning row) used to raise SecureChipError right
        # here, escape verify_payload() and turn into an opaque HTTP 500.  Treat
        # it as a server-side data problem with a clear message and log line.
        try:
            secret_key = normalize_hex(chip["secret_key"], 16, "secret_key")
        except SecureChipError as exc:
            app.logger.error("Bad secret_key stored for UID=%s...: %s", uid_hex[:8], exc)
            return {
                "authentic": False,
                "reason": "Dữ liệu secret key của chip trong database không hợp lệ — cần cấp phát lại tại nhà máy",
            }, 500

        expected = compute_response(uid, nonce, secret_key)

        # Verify the cryptographic response BEFORE consuming the nonce.
        # Otherwise anyone could submit a bogus response first and burn a
        # legitimate one-time nonce, creating an avoidable denial-of-service.
        if not hmac.compare_digest(response, expected):
            app.logger.info("FAKE: response mismatch: UID=%s...", uid_hex[:8])
            return {"authentic": False, "reason": "Response không khớp — chip giả hoặc secret key sai"}, 200

        # Atomic INSERT guarded by the (uid, nonce) primary key: in a race,
        # exactly one valid request can reserve the nonce; later copies are
        # classified as replay.
        if not reserve_nonce_once(conn, uid_hex, nonce_hex):
            app.logger.warning("REPLAY blocked: UID=%s..., nonce=%s...", uid_hex[:8], nonce_hex[:8])
            return {"authentic": False, "reason": "Nonce đã được sử dụng — nghi ngờ replay attack"}, 200

        app.logger.info("AUTHENTIC: UID=%s...", uid_hex[:8])
        return {
            "authentic": True,
            "uid": uid_hex,
            "product": chip["product"],
            "manufacturer": chip["manufacturer"],
            "pack_date": chip["pack_date"],
        }, 200

@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "service": "Secure Chip Verification Server",
        "status": "running on PostgreSQL",
        "verify_endpoint": "/verify",
    })

@app.route("/verify", methods=["POST"])
def verify():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"authentic": False, "reason": "Request body phải là JSON"}), 400
    
    result, status = verify_payload(data)
    return jsonify(result), status

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
