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

# Chạy tạo bảng khi khởi động Server
with app.app_context():
    init_db()

def cleanup_old_nonces(conn) -> None:
    cutoff = int(time.time()) - NONCE_TTL_SECONDS
    with conn.cursor() as cur:
        cur.execute("DELETE FROM used_nonces WHERE used_at < %s", (cutoff,))

def get_chip(conn, uid_hex: str) -> Optional[Dict]:
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM chips WHERE uid = %s", (uid_hex,))
        return cur.fetchone()

def reserve_nonce_once(conn, uid_hex: str, nonce_hex: str) -> bool:
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO used_nonces(uid, nonce, used_at) VALUES (%s, %s, %s)",
                (uid_hex, nonce_hex, int(time.time())),
            )
        return True
    except psycopg2.IntegrityError:
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
