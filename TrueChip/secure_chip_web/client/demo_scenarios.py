"""
Live demo scenarios for the Secure Chip project.

This script uses the real UART chip and real Flask server.
It avoids hard-coded demo UID/key/product values.

Scenarios:
1. Real chip verification through UART + server.
2. Tampered UID: server should reject because UID is not registered.
3. Tampered response: server should reject because copied UID without the secret key cannot answer correctly.
"""

from __future__ import annotations

import argparse
import os
import secrets
import sys
import time
from pathlib import Path
from typing import Dict, Any

import serial

# Allow running this script directly (python client/demo_scenarios.py) while
# the shared crypto/protocol helpers live one level up, in common/.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "common"))

from chip_tester import (
    get_uid,
    open_uart,
    print_result,
    request_challenge_response,
    verify_with_server,
)
from secure_chip_common import DEFAULT_BAUD, NONCE_LEN, SecureChipError, to_hex


def banner(title: str) -> None:
    print(f"\n{'=' * 70}")
    print(f"  {title}")
    print("=" * 70)


def flip_one_bit(raw: bytes) -> bytes:
    if not raw:
        raise ValueError("Cannot flip an empty byte string")
    mutable = bytearray(raw)
    mutable[-1] ^= 0x01
    return bytes(mutable)


def scenario_real_chip(ser: serial.Serial, server_url: str, server_timeout: float) -> Dict[str, Any]:
    banner("KỊCH BẢN 1: Quét chip thật bằng UART + Server")
    uid = get_uid(ser)
    print(f"UID nhận từ FPGA: {to_hex(uid)}")

    nonce = secrets.token_bytes(NONCE_LEN)
    response = request_challenge_response(ser, nonce)
    print(f"Nonce gửi xuống FPGA: {to_hex(nonce)}")
    print(f"Response từ FPGA:     {to_hex(response)}")

    result = verify_with_server(server_url, uid, nonce, response, server_timeout)
    result.setdefault("uid", to_hex(uid))
    print_result(result)
    return {"uid": uid, "nonce": nonce, "response": response, "result": result}


def scenario_tampered_uid(real_uid: bytes, real_nonce: bytes, real_response: bytes, server_url: str, server_timeout: float) -> None:
    banner("KỊCH BẢN 2: UID bị sửa / không tồn tại trong database")
    fake_uid = flip_one_bit(real_uid)
    print(f"UID thật : {to_hex(real_uid)}")
    print(f"UID sửa  : {to_hex(fake_uid)}")
    print("Gửi UID đã sửa cùng nonce/response thật lên server...")

    result = verify_with_server(server_url, fake_uid, real_nonce, real_response, server_timeout)
    result.setdefault("uid", to_hex(fake_uid))
    print_result(result)


def scenario_tampered_response(ser: serial.Serial, real_uid: bytes, server_url: str, server_timeout: float) -> None:
    banner("KỊCH BẢN 3: Copy UID thật nhưng response bị giả mạo")
    nonce = secrets.token_bytes(NONCE_LEN)
    real_response = request_challenge_response(ser, nonce)
    fake_response = flip_one_bit(real_response)

    print(f"UID thật:             {to_hex(real_uid)}")
    print(f"Nonce mới:            {to_hex(nonce)}")
    print(f"Response thật FPGA:   {to_hex(real_response)}")
    print(f"Response đã sửa giả:  {to_hex(fake_response)}")
    print("Server sẽ tự tính lại AES bằng key trong database và so sánh...")

    result = verify_with_server(server_url, real_uid, nonce, fake_response, server_timeout)
    result.setdefault("uid", to_hex(real_uid))
    print_result(result)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Live demo for Secure Chip project")
    parser.add_argument("--port", default=os.environ.get("SECURE_CHIP_SERIAL_PORT"), help="UART port, e.g. COM3 or /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=int(os.environ.get("SECURE_CHIP_BAUD", str(DEFAULT_BAUD))))
    parser.add_argument("--timeout", type=float, default=float(os.environ.get("SECURE_CHIP_UART_TIMEOUT", "2.0")))
    parser.add_argument(
        "--server-url",
        default=os.environ.get("SECURE_CHIP_VERIFY_URL"),
        help="Verification endpoint, e.g. http://127.0.0.1:5000/verify",
    )
    parser.add_argument("--server-timeout", type=float, default=float(os.environ.get("SECURE_CHIP_SERVER_TIMEOUT", "5.0")))
    parser.add_argument("--no-negative", action="store_true", help="Only run real-chip verification")
    parser.add_argument("--pause", type=float, default=1.5, help="Seconds between scenarios")
    return parser


def main() -> int:
    args = build_arg_parser().parse_args()

    if not args.server_url:
        print(
            "Thiếu verification server URL. Dùng --server-url hoặc biến môi trường SECURE_CHIP_VERIFY_URL.",
            file=sys.stderr,
        )
        return 2

    try:
        with open_uart(args.port, args.baud, args.timeout) as ser:
            print(f"UART connected: {ser.port} @ {args.baud} baud")
            real = scenario_real_chip(ser, args.server_url, args.server_timeout)

            if not args.no_negative:
                time.sleep(args.pause)
                scenario_tampered_uid(real["uid"], real["nonce"], real["response"], args.server_url, args.server_timeout)
                time.sleep(args.pause)
                scenario_tampered_response(ser, real["uid"], args.server_url, args.server_timeout)

        banner("Demo hoàn tất")
        return 0
    except SecureChipError as exc:
        print(f"LỖI: {exc}", file=sys.stderr)
        return 1
    except serial.SerialException as exc:
        print(f"LỖI UART: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
