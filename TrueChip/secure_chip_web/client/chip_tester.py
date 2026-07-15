"""
Smartphone/PC tester layer for the Secure Chip project.

This version is meant to run with the real project architecture:
- Talks to FPGA over UART only.
- Does NOT contain the chip UID or secret key.
- Sends UID + nonce + FPGA response to the Flask verification server.

UART protocol:
    0x01              -> FPGA returns 16-byte UID
    0x02 + 16B nonce  -> FPGA returns 16-byte AES response
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import sys
import time
from pathlib import Path
from typing import Any, Dict, Optional

import requests
import serial
from serial.tools import list_ports

# ==============================================================================
#Khai báo đường link Server thật trên Render
# ==============================================================================
SERVER_URL = "https://truechip-server.onrender.com/verify"

# Allow running this script directly (python client/chip_tester.py) while the
# shared crypto/protocol helpers live one level up, in common/.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from secure_chip_common import (
    CMD_CHALLENGE,
    CMD_GET_ID,
    DEFAULT_BAUD,
    NONCE_LEN,
    REPLAY_OR_ERROR_RESPONSE,
    RESPONSE_LEN,
    UID_LEN,
    SecureChipError,
    read_exact,
    to_hex,
)


def auto_detect_port() -> Optional[str]:
    ports = list(list_ports.comports())
    if len(ports) == 1:
        return ports[0].device
    return None


def open_uart(port: Optional[str], baud: int, timeout: float) -> serial.Serial:
    actual_port = port or os.environ.get("SECURE_CHIP_SERIAL_PORT") or auto_detect_port()
    if not actual_port:
        available = ", ".join(p.device for p in list_ports.comports()) or "không tìm thấy cổng nào"
        raise SecureChipError(
            "Chưa chọn cổng UART. Dùng --port hoặc biến môi trường SECURE_CHIP_SERIAL_PORT. "
            f"Cổng hiện có: {available}"
        )

    # ĐÃ CHỈNH SỬA: Tắt tường minh dsrdtr và rtscts để ngăn mạch nạp UART rời tự động 
    # tạo xung kích hoạt nhầm trạng thái Reset hoặc Start bit giả trên FPGA khi mở cổng.
    ser = serial.Serial(
        port=actual_port,
        baudrate=baud,
        timeout=timeout,
        dsrdtr=False,
        rtscts=False
    )
    
    # ĐÃ CHỈNH SỬA: Tăng thời gian chờ từ 0.2s lên 1.5s để lọc hoàn toàn các xung nhiễu 
    # (glitch) phần cứng lúc vừa cắm/mở cổng COM.
    print("Đang đợi mạch UART ổn định...")
    time.sleep(1.5)  
    
    # Xóa sạch các dữ liệu rác trong bộ đệm trước khi bắt đầu truyền nhận thật
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    return ser


def get_uid(ser: serial.Serial) -> bytes:
    ser.reset_input_buffer()
    ser.write(bytes([CMD_GET_ID]))
    ser.flush()
    return read_exact(ser, UID_LEN, "UID")


def request_challenge_response(ser: serial.Serial, nonce: bytes) -> bytes:
    if len(nonce) != NONCE_LEN:
        raise SecureChipError(f"Nonce must be {NONCE_LEN} bytes")
    ser.reset_input_buffer()
    ser.write(bytes([CMD_CHALLENGE]) + nonce)
    ser.flush()
    return read_exact(ser, RESPONSE_LEN, "challenge response")


def verify_with_server(server_url: str, uid: bytes, nonce: bytes, response: bytes, timeout: float) -> Dict[str, Any]:
    payload = {
        "uid": to_hex(uid),
        "nonce": to_hex(nonce),
        "response": to_hex(response),
    }
    try:
        r = requests.post(server_url, json=payload, timeout=timeout)
        r.raise_for_status()
    except requests.RequestException as exc:
        raise SecureChipError(f"Không kết nối được verification server: {exc}") from exc

    try:
        data = r.json()
    except ValueError as exc:
        raise SecureChipError("Server trả về dữ liệu không phải JSON") from exc

    return data


def scan_once(ser: serial.Serial, server_url: str, server_timeout: float) -> Dict[str, Any]:
    uid = get_uid(ser)
    nonce = secrets.token_bytes(NONCE_LEN)
    response = request_challenge_response(ser, nonce)

    if response == REPLAY_OR_ERROR_RESPONSE:
        return {
            "authentic": False,
            "uid": to_hex(uid),
            "reason": "FPGA trả về mã lỗi FF..FF khi xử lý challenge",
        }

    server_result = verify_with_server(server_url, uid, nonce, response, server_timeout)
    server_result.setdefault("uid", to_hex(uid))
    return server_result


def print_result(result: Dict[str, Any]) -> None:
    print("\n================ SECURE CHIP RESULT ================")
    print(f"UID: {result.get('uid', 'N/A')}")

    if result.get("authentic") is True:
        print("KẾT QUẢ: AUTHENTIC / HÀNG THẬT")
        print(f"Sản phẩm      : {result.get('product', 'N/A')}")
        print(f"Nhà sản xuất  : {result.get('manufacturer', 'N/A')}")
        print(f"Ngày đóng gói : {result.get('pack_date', 'N/A')}")
    else:
        print("KẾT QUẢ: FAKE / KHÔNG XÁC THỰC")
        print(f"Lý do: {result.get('reason', 'Server không trả lý do cụ thể')}")

    print("====================================================")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Secure Chip UART + server verifier")
    parser.add_argument("--port", default=os.environ.get("SECURE_CHIP_SERIAL_PORT"), help="UART port, e.g. COM3 or /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=int(os.environ.get("SECURE_CHIP_BAUD", str(DEFAULT_BAUD))))
    parser.add_argument("--timeout", type=float, default=float(os.environ.get("SECURE_CHIP_UART_TIMEOUT", "2.0")))
    # ĐÃ CHỈNH SỬA: Đưa SERVER_URL làm mặc định nếu không có biến môi trường
    parser.add_argument(
        "--server-url",
        default=os.environ.get("SECURE_CHIP_VERIFY_URL", SERVER_URL),
        help=f"Verification endpoint, default: {SERVER_URL}",
    )
    parser.add_argument("--server-timeout", type=float, default=float(os.environ.get("SECURE_CHIP_SERVER_TIMEOUT", "5.0")))
    parser.add_argument("--repeat", type=int, default=1, help="Number of real scans to perform")
    parser.add_argument("--json", action="store_true", help="Print raw JSON results")
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
            print(f"Server Target : {args.server_url}")  # In ra màn hình để báo đang gửi tới Render
            results = []
            for i in range(args.repeat):
                if args.repeat > 1:
                    print(f"\nScan {i + 1}/{args.repeat}")
                result = scan_once(ser, args.server_url, args.server_timeout)
                results.append(result)
                if not args.json:
                    print_result(result)

            if args.json:
                print(json.dumps(results if args.repeat > 1 else results[0], ensure_ascii=False, indent=2))

        return 0
    except SecureChipError as exc:
        print(f"LỖI: {exc}", file=sys.stderr)
        return 1
    except serial.SerialException as exc:
        print(f"LỖI UART: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())