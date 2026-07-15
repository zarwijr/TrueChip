"""
AES cross-check tool for FPGA bring-up.

No hard-coded test vectors are kept here. Supply real lab values using CLI args
or environment variables. This file is for engineering verification only; the
normal PC tester must not know the production secret key.

Examples:
    python verify_aes.py --uid <UID_HEX> --nonce <NONCE_HEX> --key <AES128_KEY_HEX>
    python verify_aes.py --uid <UID_HEX> --nonce <NONCE_HEX> --key <AES128_KEY_HEX> --response <FPGA_RESPONSE_HEX>
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# Allow running this script directly (python tools/verify_aes.py) while the
# shared crypto/protocol helpers live one level up, in common/.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "common"))

from secure_chip_common import NONCE_LEN, RESPONSE_LEN, UID_LEN, SecureChipError, compute_response, normalize_hex, to_hex, xor_equal_length


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Cross-check AES-128 response used by FPGA")
    parser.add_argument("--uid", default=os.environ.get("SECURE_CHIP_UID"), help="UID from FPGA, 16 bytes / 32 hex chars")
    parser.add_argument("--nonce", default=os.environ.get("SECURE_CHIP_NONCE"), help="Challenge nonce, 16 bytes / 32 hex chars")
    parser.add_argument("--key", default=os.environ.get("SECURE_CHIP_AES_KEY"), help="AES-128 key, 16 bytes / 32 hex chars")
    parser.add_argument("--response", default=os.environ.get("SECURE_CHIP_RESPONSE"), help="Optional FPGA response to compare, 16 bytes / 32 hex chars")
    return parser


def main() -> int:
    args = build_arg_parser().parse_args()

    missing = [name for name in ("uid", "nonce", "key") if not getattr(args, name)]
    if missing:
        print(f"Thiếu tham số bắt buộc: {', '.join('--' + m for m in missing)}", file=sys.stderr)
        return 2

    try:
        uid = normalize_hex(args.uid, UID_LEN, "uid")
        nonce = normalize_hex(args.nonce, NONCE_LEN, "nonce")
        key = normalize_hex(args.key, 16, "key")
        plaintext = xor_equal_length(nonce, uid)
        expected = compute_response(uid, nonce, key)

        print(f"Plaintext nonce XOR UID: {to_hex(plaintext)}")
        print(f"Expected AES response  : {to_hex(expected)}")

        if args.response:
            response = normalize_hex(args.response, RESPONSE_LEN, "response")
            ok = response == expected
            print(f"FPGA response          : {to_hex(response)}")
            print(f"Kết quả                : {'PASS' if ok else 'FAIL'}")
            return 0 if ok else 1

        return 0
    except SecureChipError as exc:
        print(f"LỖI: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
