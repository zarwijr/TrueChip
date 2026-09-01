"""Command-line enrollment tool for a trusted local provisioning station."""

from __future__ import annotations

import getpass
from datetime import date

try:  # Works both as a package and when run as a file from the repository root.
    from .enrollment_service import EnrollmentError, enroll_chip, reprovision_chip
except ImportError:  # pragma: no cover - direct script execution path
    from enrollment_service import EnrollmentError, enroll_chip, reprovision_chip

def add_chip():
    print("=== TRUECHIP - GHI DANH CHIP TAI TRAM QUAN TRI ===")
    print("1 = Enroll chip moi | 2 = Re-provision chip da co (cap nhat khoa)\n")
    mode = input("Chon che do [1]: ").strip() or "1"

    uid_hex = input("UID/Puf ID (32 ky tu Hex): ").strip()
    secret_key_hex = getpass.getpass("Secret key (32 ky tu Hex, se duoc an): ").strip()
    product = input("Product [TrueChip V2]: ").strip() or "TrueChip V2"
    manufacturer = input("Manufacturer [Huy Le Corp]: ").strip() or "Huy Le Corp"
    pack_date = input(
        f"Pack date [{date.today().strftime('%d/%m/%Y')}]: "
    ).strip() or date.today().strftime("%d/%m/%Y")

    try:
        enroll_function = reprovision_chip if mode == "2" else enroll_chip
        result = enroll_function(
            uid_hex,
            secret_key_hex,
            product,
            manufacturer,
            pack_date,
        )
    except EnrollmentError as exc:
        print(f"\n[KHONG THANH CONG] {exc}")
        return

    print(
        "\n[THANH CONG] Da ghi danh chip "
        f"{result['uid_prefix']} - {result['product']} - {result['pack_date']}"
    )

if __name__ == '__main__':
    add_chip()
