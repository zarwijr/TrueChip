"""
Secure Chip common utilities.

Protocol matching the project diagram:
- UART 115200 baud, 8N1
- Command 0x01: GET_ID, FPGA returns 16-byte UID
- Command 0x02 + 16-byte nonce: CHALLENGE, FPGA returns 16-byte AES response
- Response formula: AES-128(secret_key, nonce XOR uid)
"""

from __future__ import annotations

import binascii
import hmac
from dataclasses import dataclass
from typing import Optional

from Crypto.Cipher import AES

CMD_GET_ID = 0x01
CMD_CHALLENGE = 0x02
UID_LEN = 16
NONCE_LEN = 16
RESPONSE_LEN = 16
REPLAY_OR_ERROR_RESPONSE = b"\xff" * RESPONSE_LEN
DEFAULT_BAUD = 115200


class SecureChipError(Exception):
    """Raised when the secure chip protocol or data is invalid."""


@dataclass(frozen=True)
class VerificationInput:
    uid: bytes
    nonce: bytes
    response: bytes


def normalize_hex(value: str, expected_len: Optional[int] = None, field_name: str = "value") -> bytes:
    """
    Convert a hex string into bytes.

    Accepts optional separators commonly used when copying values:
    spaces, colons, dashes, and 0x prefix.
    """
    if value is None:
        raise SecureChipError(f"Missing {field_name}")

    cleaned = (
        value.strip()
        .lower()
        .replace("0x", "")
        .replace(" ", "")
        .replace(":", "")
        .replace("-", "")
        .replace("_", "")
    )

    if len(cleaned) == 0:
        raise SecureChipError(f"{field_name} is empty")

    try:
        raw = bytes.fromhex(cleaned)
    except ValueError as exc:
        raise SecureChipError(f"{field_name} must be valid hexadecimal") from exc

    if expected_len is not None and len(raw) != expected_len:
        raise SecureChipError(
            f"{field_name} must be {expected_len} bytes / {expected_len * 2} hex chars, got {len(raw)} bytes"
        )

    return raw


def to_hex(raw: bytes) -> str:
    return raw.hex().upper()


def xor_equal_length(a: bytes, b: bytes) -> bytes:
    if len(a) != len(b):
        raise SecureChipError(f"XOR input length mismatch: {len(a)} != {len(b)}")
    return bytes(x ^ y for x, y in zip(a, b))


def compute_response(uid: bytes, nonce: bytes, secret_key: bytes) -> bytes:
    """Return AES-128(secret_key, nonce XOR uid)."""
    if len(uid) != UID_LEN:
        raise SecureChipError(f"UID must be {UID_LEN} bytes")
    if len(nonce) != NONCE_LEN:
        raise SecureChipError(f"Nonce must be {NONCE_LEN} bytes")
    if len(secret_key) != 16:
        raise SecureChipError("This FPGA design expects an AES-128 key: exactly 16 bytes")

    plaintext = xor_equal_length(nonce, uid)
    return AES.new(secret_key, AES.MODE_ECB).encrypt(plaintext)


def verify_response(uid: bytes, nonce: bytes, response: bytes, secret_key: bytes) -> bool:
    if len(response) != RESPONSE_LEN:
        return False
    expected = compute_response(uid, nonce, secret_key)
    return hmac.compare_digest(response, expected)


def read_exact(serial_port, size: int, label: str) -> bytes:
    """Read an exact number of bytes from a pyserial port or raise a clear error."""
    data = serial_port.read(size)
    if len(data) != size:
        raise SecureChipError(f"Timeout while reading {label}: expected {size} bytes, got {len(data)}")
    return data
