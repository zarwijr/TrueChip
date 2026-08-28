#!/usr/bin/env python3
"""Copy the canonical layout-target RTL files into this OpenLane design folder."""
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
    src = RTL / name
    if not src.exists():
        raise SystemExit(f"missing RTL source: {src}")
    shutil.copy2(src, DST / name)
    print(f"synced {name}")
