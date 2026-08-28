"""TrueChip end-to-end UART CHALLENGE test (Protocol V2).

Run on the FPGA only after provisioning/obtaining the chip's *diversified key*.
The production protocol must not expose that key over normal UART.

Examples:
    python test_uart_challenge.py --port COM3 --secret-key <32_hex_chars>

or, in a controlled lab/provisioning setup where the PUF/device ID is known:
    python test_uart_challenge.py --port COM3 \
        --master-key 12341234123412341234123412341234 \
        --device-id <32_hex_chars>

The test proves:
1) framed GET_ID works;
2) one fresh CHALLENGE returns AES-128(key, nonce XOR uid);
3) an immediate fresh challenge is rate-limited;
4) after cooldown, replaying an old nonce returns STATUS_REPLAY;
5) after cooldown, a new nonce still authenticates correctly.

Use --test-lockout only at the end of a lab session: it intentionally drives the
chip into STATUS_LOCKED until a real reset/power-cycle.
"""

from __future__ import annotations

import argparse
import secrets
import sys
import time
from pathlib import Path

import serial

COMMON_DIR = Path(__file__).resolve().parents[1] / "secure_chip_web" / "common"
sys.path.insert(0, str(COMMON_DIR))

from secure_chip_common import (  # noqa: E402
    CMD_CHALLENGE,
    CMD_GET_ID,
    DEFAULT_BAUD,
    NONCE_LEN,
    RESPONSE_LEN,
    STATUS_LOCKED,
    STATUS_OK,
    STATUS_RATE_LIMIT,
    STATUS_REPLAY,
    UID_LEN,
    SecureChipError,
    build_request,
    compute_response,
    derive_diversified_key,
    normalize_hex,
    read_response,
    status_name,
    to_hex,
)


def transact(ser: serial.Serial, cmd: int, payload: bytes = b"") -> tuple[int, bytes]:
    ser.reset_input_buffer()
    ser.write(build_request(cmd, payload))
    ser.flush()
    return read_response(ser, f"CMD 0x{cmd:02X}")


def require_status(actual: int, expected: int, label: str) -> None:
    if actual != expected:
        raise SecureChipError(
            f"{label}: expected {status_name(expected)} (0x{expected:02X}), "
            f"got {status_name(actual)} (0x{actual:02X})"
        )


def get_uid(ser: serial.Serial) -> bytes:
    status, payload = transact(ser, CMD_GET_ID)
    require_status(status, STATUS_OK, "GET_ID")
    if len(payload) != UID_LEN:
        raise SecureChipError(f"GET_ID payload length {len(payload)} != {UID_LEN}")
    return payload


def check_valid_challenge(ser: serial.Serial, uid: bytes, key: bytes, nonce: bytes, label: str) -> bytes:
    status, payload = transact(ser, CMD_CHALLENGE, nonce)
    require_status(status, STATUS_OK, label)
    if len(payload) != RESPONSE_LEN:
        raise SecureChipError(f"{label}: payload length {len(payload)} != {RESPONSE_LEN}")
    expected = compute_response(uid, nonce, key)
    if payload != expected:
        raise SecureChipError(
            f"{label}: AES mismatch\n  chip    = {to_hex(payload)}\n  expected= {to_hex(expected)}"
        )
    return payload


def resolve_key(args: argparse.Namespace) -> bytes:
    if args.secret_key:
        if args.master_key or args.device_id:
            raise SecureChipError("Use either --secret-key OR --master-key + --device-id, not both")
        return normalize_hex(args.secret_key, 16, "secret_key/diversified_key")

    if bool(args.master_key) != bool(args.device_id):
        raise SecureChipError("--master-key and --device-id must be supplied together")
    if args.master_key and args.device_id:
        master = normalize_hex(args.master_key, 16, "master_key")
        device_id = normalize_hex(args.device_id, 16, "device_id")
        return derive_diversified_key(master, device_id)

    raise SecureChipError(
        "Missing verification key. Supply --secret-key (preferred for a provisioned board) "
        "or --master-key + --device-id in a controlled lab setup."
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="TrueChip Protocol V2 AES challenge/replay/rate-limit test")
    parser.add_argument("--port", required=True, help="e.g. COM3 or /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--secret-key", help="16-byte diversified key as 32 hex chars")
    parser.add_argument("--master-key", help="lab-only 16-byte master key as 32 hex chars")
    parser.add_argument("--device-id", help="lab-only 16-byte PUF/device ID as 32 hex chars")
    parser.add_argument("--cooldown-s", type=float, default=0.020, help="wait after rate-limit/replay; default 20 ms")
    parser.add_argument(
        "--test-lockout",
        action="store_true",
        help="intentionally trigger permanent-until-reset lockout at end of test",
    )
    args = parser.parse_args()

    try:
        key = resolve_key(args)
        print(f"[INFO] Verification diversified key loaded: {to_hex(key)}")

        with serial.Serial(args.port, args.baud, timeout=args.timeout, dsrdtr=False, rtscts=False) as ser:
            time.sleep(1.0)
            ser.reset_input_buffer()
            ser.reset_output_buffer()

            uid = get_uid(ser)
            print(f"[PASS] GET_ID: {to_hex(uid)}")

            nonce1 = secrets.token_bytes(NONCE_LEN)
            response1 = check_valid_challenge(ser, uid, key, nonce1, "fresh challenge #1")
            print(f"[PASS] Fresh CHALLENGE: nonce={to_hex(nonce1)} response={to_hex(response1)}")

            nonce2 = secrets.token_bytes(NONCE_LEN)
            status, payload = transact(ser, CMD_CHALLENGE, nonce2)
            require_status(status, STATUS_RATE_LIMIT, "immediate fresh challenge")
            if payload:
                raise SecureChipError("RATE_LIMIT response must have zero-length payload")
            print("[PASS] Immediate fresh CHALLENGE -> STATUS_RATE_LIMIT")

            time.sleep(args.cooldown_s)
            status, payload = transact(ser, CMD_CHALLENGE, nonce1)
            require_status(status, STATUS_REPLAY, "replayed challenge")
            if payload:
                raise SecureChipError("REPLAY response must have zero-length payload")
            print("[PASS] Old nonce after cooldown -> STATUS_REPLAY")

            time.sleep(args.cooldown_s)
            nonce3 = secrets.token_bytes(NONCE_LEN)
            response3 = check_valid_challenge(ser, uid, key, nonce3, "fresh challenge #2")
            print(f"[PASS] New CHALLENGE after protections: response={to_hex(response3)}")

            if args.test_lockout:
                print("[WARN] Driving chip into lockout; a reset/power-cycle will be required afterwards.")
                # A successful challenge just started a cooldown and reset fail_cnt.
                for attempt in range(1, 6):
                    status, payload = transact(ser, CMD_CHALLENGE, secrets.token_bytes(NONCE_LEN))
                    expected = STATUS_LOCKED if attempt == 5 else STATUS_RATE_LIMIT
                    require_status(status, expected, f"lockout attempt {attempt}")
                    if payload:
                        raise SecureChipError("Protection status response must have zero-length payload")
                    print(f"[PASS] lockout attempt {attempt}: {status_name(status)}")

            print("[PASS] TRUECHIP END-TO-END CHALLENGE TEST COMPLETED")
            return 0

    except (SecureChipError, serial.SerialException) as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
