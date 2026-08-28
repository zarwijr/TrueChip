"""
TrueChip common crypto + UART protocol helpers.

Request protocol (Protocol V2, PC/reader -> chip):
    A5 | VER | CMD | LEN | PAYLOAD | CRC_H | CRC_L

CRC16-CCITT parameters:
    polynomial 0x1021, init 0xFFFF
    covers VER | CMD | LEN | PAYLOAD (MAGIC and CRC bytes excluded)

Response protocol (chip -> PC/reader):
    A5 | VER | STATUS | LEN | PAYLOAD

Current hardware does not append a CRC to responses.  The cryptographic
challenge response is still checked by the server, but a response CRC is a
reasonable future transport-integrity improvement.

Authentication formula:
    response = AES-128(secret_key, nonce XOR uid)
"""

from __future__ import annotations

import hmac
from dataclasses import dataclass
from typing import Optional, Tuple


MAGIC = 0xA5
VERSION = 0x01

CMD_GET_ID = 0x01
CMD_CHALLENGE = 0x02

STATUS_OK = 0x00
STATUS_BAD_CMD = 0x01          # reserved for software/reporting
STATUS_BAD_LENGTH = 0x02       # reserved for software/reporting
STATUS_REPLAY = 0x03
STATUS_RATE_LIMIT = 0x04
STATUS_LOCKED = 0x05
STATUS_INTERNAL_ERROR = 0x06   # reserved for software/reporting

UID_LEN = 16
NONCE_LEN = 16
RESPONSE_LEN = 16
DEFAULT_BAUD = 115200

STATUS_NAMES = {
    STATUS_OK: "OK",
    STATUS_BAD_CMD: "BAD_CMD",
    STATUS_BAD_LENGTH: "BAD_LENGTH",
    STATUS_REPLAY: "REPLAY",
    STATUS_RATE_LIMIT: "RATE_LIMIT",
    STATUS_LOCKED: "LOCKED",
    STATUS_INTERNAL_ERROR: "INTERNAL_ERROR",
}


class SecureChipError(Exception):
    """Raised when the TrueChip protocol, crypto input, or transport is invalid."""


@dataclass(frozen=True)
class VerificationInput:
    uid: bytes
    nonce: bytes
    response: bytes


def normalize_hex(value: str, expected_len: Optional[int] = None, field_name: str = "value") -> bytes:
    """Convert a human-entered hexadecimal string into bytes."""
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

    if not cleaned:
        raise SecureChipError(f"{field_name} is empty")

    try:
        raw = bytes.fromhex(cleaned)
    except ValueError as exc:
        raise SecureChipError(f"{field_name} must be valid hexadecimal") from exc

    if expected_len is not None and len(raw) != expected_len:
        raise SecureChipError(
            f"{field_name} must be {expected_len} bytes / {expected_len * 2} hex chars, "
            f"got {len(raw)} bytes"
        )
    return raw


def to_hex(raw: bytes) -> str:
    return raw.hex().upper()


def xor_equal_length(a: bytes, b: bytes) -> bytes:
    if len(a) != len(b):
        raise SecureChipError(f"XOR input length mismatch: {len(a)} != {len(b)}")
    return bytes(x ^ y for x, y in zip(a, b))



def _aes_ecb_encrypt_block(key: bytes, block: bytes) -> bytes:
    """Encrypt one AES-128 block; import pycryptodome only when crypto is used."""
    try:
        from Crypto.Cipher import AES
    except ImportError as exc:
        raise SecureChipError(
            "pycryptodome is required for AES verification/KDF helpers. "
            "Install secure_chip_web/requirements.txt."
        ) from exc
    return AES.new(key, AES.MODE_ECB).encrypt(block)

def compute_response(uid: bytes, nonce: bytes, secret_key: bytes) -> bytes:
    """Return AES-128(secret_key, nonce XOR uid)."""
    if len(uid) != UID_LEN:
        raise SecureChipError(f"UID must be {UID_LEN} bytes")
    if len(nonce) != NONCE_LEN:
        raise SecureChipError(f"Nonce must be {NONCE_LEN} bytes")
    if len(secret_key) != 16:
        raise SecureChipError("This design expects an AES-128 key: exactly 16 bytes")

    plaintext = xor_equal_length(nonce, uid)
    return _aes_ecb_encrypt_block(secret_key, plaintext)


def derive_diversified_key(master_key: bytes, device_id: bytes) -> bytes:
    """Mirror the RTL boot KDF: diversified_key = AES-128(master_key, device_id)."""
    if len(master_key) != 16:
        raise SecureChipError("master_key must be exactly 16 bytes")
    if len(device_id) != 16:
        raise SecureChipError("device_id/PUF ID must be exactly 16 bytes")
    return _aes_ecb_encrypt_block(master_key, device_id)


def verify_response(uid: bytes, nonce: bytes, response: bytes, secret_key: bytes) -> bool:
    if len(response) != RESPONSE_LEN:
        return False
    expected = compute_response(uid, nonce, secret_key)
    return hmac.compare_digest(response, expected)


def crc16_ccitt(data: bytes) -> int:
    """CRC16-CCITT, poly 0x1021, init 0xFFFF, matching cmd_parser.v."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def build_request(cmd: int, payload: bytes = b"") -> bytes:
    """Build one Protocol V2 request frame accepted by cmd_parser.v."""
    if not 0 <= cmd <= 0xFF:
        raise SecureChipError("cmd must fit in one byte")
    if len(payload) > 0xFF:
        raise SecureChipError("payload is too long for the 1-byte LEN field")

    body = bytes((VERSION, cmd, len(payload))) + payload
    crc = crc16_ccitt(body)
    return bytes((MAGIC,)) + body + bytes(((crc >> 8) & 0xFF, crc & 0xFF))


def parse_response(data: bytes) -> Tuple[int, bytes]:
    """Parse one complete hardware response frame: A5|VER|STATUS|LEN|PAYLOAD."""
    if len(data) < 4:
        raise SecureChipError(f"Response too short: expected at least 4 bytes, got {len(data)}")

    magic, version, status, payload_len = data[:4]
    if magic != MAGIC:
        raise SecureChipError(f"Bad response MAGIC: expected 0x{MAGIC:02X}, got 0x{magic:02X}")
    if version != VERSION:
        raise SecureChipError(f"Bad response VERSION: expected 0x{VERSION:02X}, got 0x{version:02X}")

    expected_len = 4 + payload_len
    if len(data) != expected_len:
        raise SecureChipError(
            f"Response length mismatch: header says {payload_len} payload bytes, "
            f"frame has {len(data) - 4}"
        )
    return status, data[4:]


def status_name(status: int) -> str:
    return STATUS_NAMES.get(status, f"UNKNOWN_0x{status:02X}")


def read_exact(serial_port, size: int, label: str) -> bytes:
    """Read an exact number of bytes from a pyserial port or raise a clear error."""
    data = serial_port.read(size)
    if len(data) != size:
        raise SecureChipError(f"Timeout while reading {label}: expected {size} bytes, got {len(data)}")
    return data


def read_response(serial_port, label: str = "response") -> Tuple[int, bytes]:
    """Read one variable-length response frame from a pyserial-like object."""
    header = read_exact(serial_port, 4, f"{label} header")
    magic, version, status, payload_len = header

    if magic != MAGIC:
        raise SecureChipError(f"Bad {label} MAGIC: expected 0x{MAGIC:02X}, got 0x{magic:02X}")
    if version != VERSION:
        raise SecureChipError(f"Bad {label} VERSION: expected 0x{VERSION:02X}, got 0x{version:02X}")

    payload = read_exact(serial_port, payload_len, f"{label} payload") if payload_len else b""
    return status, payload


def require_ok(status: int, payload: bytes, expected_len: Optional[int] = None, operation: str = "command") -> bytes:
    """Convert a non-OK chip status into a readable exception and validate payload length."""
    if status != STATUS_OK:
        raise SecureChipError(f"{operation} rejected by chip: {status_name(status)} (0x{status:02X})")
    if expected_len is not None and len(payload) != expected_len:
        raise SecureChipError(
            f"{operation} returned {len(payload)} payload bytes, expected {expected_len}"
        )
    return payload
