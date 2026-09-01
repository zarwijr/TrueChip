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
import sys
from pathlib import Path
from typing import Dict, Optional

import psycopg2


HEX32_RE = re.compile(r"\A[0-9A-Fa-f]{32}\Z")


class EnrollmentError(RuntimeError):
    """A safe, user-facing enrollment error."""


def _config_path() -> Path:
    """Use a writable config beside the EXE when frozen, otherwise beside source."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().with_name("admin_config.json")
    return Path(__file__).with_name("admin_config.json")

# Both names are accepted on purpose.
#
# server/mock_server.py reads DATABASE_URL (that is what Render injects),
# while this module originally read only TRUECHIP_DATABASE_URL. Setting one
# and expecting the other to work was the cause of "factory_tool works but
# the admin web says the database is not configured".
ENV_NAMES = ("TRUECHIP_DATABASE_URL", "DATABASE_URL")


def _read_config() -> dict:
    try:
        return json.loads(_config_path().read_text(encoding="utf-8"))
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return {}


def _database_url_and_source() -> tuple:
    """Return (url, source) or ("", "") when nothing is configured."""
    for name in ENV_NAMES:
        value = os.environ.get(name, "").strip()
        if value:
            return value, f"bien moi truong {name}"

    value = str(_read_config().get("database_url", "")).strip()
    if value:
        return value, "admin_config.json"

    return "", ""


def _database_url() -> str:
    url, _ = _database_url_and_source()
    if not url:
        raise EnrollmentError(
            "Chua cau hinh database. Dan Database URL vao o cau hinh tren trang "
            "admin (no se duoc luu vao admin_config.json, khong gui di dau), "
            "hoac dat bien moi truong TRUECHIP_DATABASE_URL."
        )
    return url


def database_configured() -> bool:
    """Return status without exposing the configured URL."""
    url, _ = _database_url_and_source()
    return bool(url)


def database_source() -> str:
    """Where the URL came from - never the URL itself."""
    _, source = _database_url_and_source()
    return source


def save_database_url(url: str) -> str:
    """Persist the URL to admin_config.json so a new window still finds it.

    Environment variables set with `$env:` only live in the window that set
    them, which is why launching admin_web.py from start_admin_web.bat used
    to lose the configuration. Writing the URL to the (git-ignored) config
    file makes it survive.
    """
    value = url.strip()
    if not value:
        raise EnrollmentError("Database URL khong duoc de trong.")
    if not value.startswith(("postgres://", "postgresql://")):
        raise EnrollmentError(
            "Database URL phai bat dau bang postgres:// hoac postgresql://"
        )
    if len(value) > 2000:
        raise EnrollmentError("Database URL qua dai.")

    config = _read_config()
    config["database_url"] = value
    config.setdefault("listen_host", "127.0.0.1")
    config.setdefault("listen_port", 8765)
    try:
        _config_path().write_text(
            json.dumps(config, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    except OSError as exc:
        raise EnrollmentError(f"Khong ghi duoc admin_config.json: {exc}") from exc

    # Make it effective immediately for this process too.
    os.environ["TRUECHIP_DATABASE_URL"] = value
    return "admin_config.json"


def test_connection() -> dict:
    """Connect, ensure the schema exists, and count enrolled chips."""
    try:
        with psycopg2.connect(_database_url()) as conn:
            _ensure_schema(conn)
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM chips")
                total = cur.fetchone()[0]
        return {"ok": True, "chips": int(total)}
    except EnrollmentError:
        raise
    except Exception as exc:  # noqa: BLE001 - never leak the URL or driver detail
        raise EnrollmentError(
            "Khong ket noi duoc database. Kiem tra lai URL, mang, va quyen truy cap."
        ) from exc


def list_chips(limit: int = 200) -> list:
    """Return enrolled chips WITHOUT their secret keys.

    The key column is deliberately never selected: there is no legitimate
    reason for the browser to receive it, and not fetching it means it cannot
    leak through a logging or templating mistake.
    """
    try:
        with psycopg2.connect(_database_url()) as conn:
            _ensure_schema(conn)
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT uid, product, manufacturer, pack_date, active, created_at
                    FROM chips ORDER BY created_at DESC LIMIT %s
                    """,
                    (int(limit),),
                )
                rows = cur.fetchall()
    except EnrollmentError:
        raise
    except Exception as exc:  # noqa: BLE001
        raise EnrollmentError("Khong doc duoc danh sach chip.") from exc

    return [
        {
            "uid": r[0],
            "product": r[1],
            "manufacturer": r[2],
            "pack_date": r[3],
            "active": bool(r[4]),
            "created_at": int(r[5]),
        }
        for r in rows
    ]


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
