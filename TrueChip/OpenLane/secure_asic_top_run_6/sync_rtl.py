#!/usr/bin/env python3
"""Copy canonical layout RTL into OpenLane while preserving the ASIC CDC attribute."""
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
RTL = PROJECT / "RTL"
DST = HERE / "src"
FILES = [
    "secure_asic_top.v",
    "uart_rx.v",
    "uart_tx.v",
    "cmd_parser.v",
    "chip_rom.v",
    "auth_fsm.v",
    "aes128.v",
    "aes_sbox.v",
]

DST.mkdir(parents=True, exist_ok=True)
for name in FILES:
    if name == "uart_rx.v":
        # FPGA RTL uses Quartus's altera_attribute; the ASIC copy deliberately
        # uses async_reg. Do not overwrite the technology-specific CDC marker.
        print("kept uart_rx.v (ASIC async_reg attribute)")
        continue
    src = RTL / name
    if not src.exists():
        raise SystemExit(f"missing RTL source: {src}")
    shutil.copy2(src, DST / name)
    print(f"synced {name}")
