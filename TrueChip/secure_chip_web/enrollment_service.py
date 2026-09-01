"""Shared, local-only chip enrollment service.

The service deliberately does not expose an HTTP enrollment endpoint. It is
used by the factory CLI and the local administrator GUI only.
"""

from __future__ import annotations

import os
import re
import time
from datetime import date
import json
from pathlib import Path
from typing import Dict, Optional

import psycopg2


HEX32_RE = re.compile(r"\A[0-9A-Fa-f]{32}\Z")


class EnrollmentError(RuntimeError):
    """A safe, user-facing enrollment error."""


def _database_url() -> str:
    # Environment variable has priority. The local JSON file is a convenience
    # for the local GUI and is ignored by Git; it is never sent to a browser.
    value = os.environ.get("TRUECHIP_DATABASE_URL", "").strip()
    if not value:
        config_path = Path(__file__).with_name("admin_config.json")
        try:
            config = json.loads(config_path.read_text(encoding="utf-8"))
            value = str(config.get("database_url", "")).strip()
        except (FileNotFoundError, OSError, json.JSONDecodeError):
            value = ""
    if not value:
        raise EnrollmentError(
            "Chua cau hinh TRUECHIP_DATABASE_URL trong cua so PowerShell hien tai."
        )
    return value


def database_configured() -> bool:
    """Return status without exposing the configured URL."""
    try:
        _database_url()
    except EnrollmentError:
        return False
    return True


def _hex32(value: str, label: str) -> str:
    normalized = value.strip().upper()
    if not HEX32_RE.fullmatch(normalized):
        raise EnrollmentError(f"{label} phai gom dung 32 ky tu Hex (0-9, A-F).")
    return normalized


def _text(value: str, label: str, maximum: int = 255) -> str:
    normalized = value.strip()
    if not normalized:
        raise EnrollmentError(f"{label} khong duoc de trong.")
    if len(normalized) > maximum:
        raise EnrollmentError(f"{label} khong duoc dai qua {maximum} ky tu.")
    return normalized


def _ensure_schema(conn) -> None:
    """Keep first-run usability while preserving the server's schema contract."""
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS chips (
                uid VARCHAR(32) PRIMARY KEY,
                secret_key VARCHAR(32) NOT NULL,
                product VARCHAR(255) NOT NULL,
                manufacturer VARCHAR(255) NOT NULL,
                pack_date VARCHAR(255) NOT NULL,
                active INTEGER NOT NULL DEFAULT 1,
                created_at BIGINT NOT NULL
            )
            """
        )


def enroll_chip(
    uid_hex: str,
    secret_key_hex: str,
    product: str,
    manufacturer: str,
    pack_date: Optional[str] = None,
) -> Dict[str, str]:
    """Enroll exactly one new UID without ever overwriting an existing chip."""
    uid = _hex32(uid_hex, "UID")
    secret_key = _hex32(secret_key_hex, "Secret key")
    product_value = _text(product, "Product")
    manufacturer_value = _text(manufacturer, "Manufacturer")
    pack_date_value = _text(
        pack_date or date.today().strftime("%d/%m/%Y"), "Pack date"
    )

    try:
        with psycopg2.connect(_database_url()) as conn:
            _ensure_schema(conn)
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO chips(
                        uid, secret_key, product, manufacturer,
                        pack_date, active, created_at
                    )
                    VALUES (%s, %s, %s, %s, %s, 1, %s)
                    ON CONFLICT(uid) DO NOTHING
                    RETURNING uid
                    """,
                    (
                        uid,
                        secret_key,
                        product_value,
                        manufacturer_value,
                        pack_date_value,
                        int(time.time()),
                    ),
                )
                if cur.fetchone() is None:
                    raise EnrollmentError(
                        f"UID {uid[:8]}... da ton tai; da tu choi ghi de khoa cu."
                    )
    except EnrollmentError:
        raise
    except Exception as exc:  # noqa: BLE001 - hide connection details from UI
        raise EnrollmentError(
            "Khong the ghi danh chip. Kiem tra database URL, mang va quyen truy cap."
        ) from exc

    return {
        "uid_prefix": f"{uid[:8]}...",
        "product": product_value,
        "manufacturer": manufacturer_value,
        "pack_date": pack_date_value,
    }


def reprovision_chip(
    uid_hex: str,
    secret_key_hex: str,
    product: str,
    manufacturer: str,
    pack_date: Optional[str] = None,
) -> Dict[str, str]:
    """Explicitly replace the key for an already enrolled lab chip.

    This is intentionally separate from enroll_chip so normal enrollment
    cannot silently overwrite a chip. The caller must expose this as a clear
    administrator-only re-provision action.
    """
    uid = _hex32(uid_hex, "UID")
    secret_key = _hex32(secret_key_hex, "Secret key")
    product_value = _text(product, "Product")
    manufacturer_value = _text(manufacturer, "Manufacturer")
    pack_date_value = _text(
        pack_date or date.today().strftime("%d/%m/%Y"), "Pack date"
    )

    try:
        with psycopg2.connect(_database_url()) as conn:
            _ensure_schema(conn)
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO chips(
                        uid, secret_key, product, manufacturer,
                        pack_date, active, created_at
                    )
                    VALUES (%s, %s, %s, %s, %s, 1, %s)
                    ON CONFLICT(uid) DO UPDATE SET
                        secret_key=EXCLUDED.secret_key,
                        product=EXCLUDED.product,
                        manufacturer=EXCLUDED.manufacturer,
                        pack_date=EXCLUDED.pack_date,
                        active=1
                    RETURNING uid
                    """,
                    (
                        uid,
                        secret_key,
                        product_value,
                        manufacturer_value,
                        pack_date_value,
                        int(time.time()),
                    ),
                )
                if cur.fetchone() is None:
                    raise EnrollmentError("Khong the cap phat lai chip.")
    except EnrollmentError:
        raise
    except Exception as exc:  # noqa: BLE001 - hide connection details from UI
        raise EnrollmentError(
            "Khong the cap phat lai chip. Kiem tra database URL, mang va quyen truy cap."
        ) from exc

    return {
        "uid_prefix": f"{uid[:8]}...",
        "product": product_value,
        "manufacturer": manufacturer_value,
        "pack_date": pack_date_value,
    }
