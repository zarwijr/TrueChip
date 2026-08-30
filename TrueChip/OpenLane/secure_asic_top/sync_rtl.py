#!/usr/bin/env python3
"""Copy canonical layout RTL into OpenLane while preserving the ASIC CDC attribute.

WHY uart_rx.v IS FORKED
-----------------------
The CDC synchroniser flops need a technology-specific marker so the tool does
not optimise the two-flop chain away or retime it:

    RTL/uart_rx.v   ->  (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    src/uart_rx.v   ->  (* async_reg = "true" *)

Quartus only understands the first; the OpenLane/Yosys flow only understands
the second.  Copying one over the other would silently drop the marker on the
target technology, so this script deliberately does NOT overwrite uart_rx.v.

THE HAZARD THIS CREATES, AND HOW IT IS HANDLED
----------------------------------------------
A fork means a real functional change made to RTL/uart_rx.v would never reach
the ASIC copy - exactly the class of silent divergence that produced the
duplicate-testbench and stale-file problems earlier in this project.

So the fork is not taken on trust.  After copying, this script strips every
attribute and comment from BOTH copies of uart_rx.v and compares what is left.
If the logic has diverged in any way beyond attributes and formatting, it
FAILS LOUDLY with a non-zero exit code instead of printing a reassuring
"kept uart_rx.v" and moving on.

Verified 2026-08-30: with attributes and comments removed, the only textual
difference is `reg rx_d1; reg rx_d2;` (FPGA) vs `reg rx_d1, rx_d2;` (ASIC).
Yosys synthesis of both copies produces byte-identical statistics - 300 cells,
identical cell-type histogram - so run_5 and run_6 hardened the correct logic.
"""

from pathlib import Path
import re
import shutil
import sys

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

# Files deliberately kept technology-specific.  Each one MUST be justified
# here and MUST pass the equivalence check below.
FORKED = {
    "uart_rx.v": "CDC marker: altera_attribute (Quartus) vs async_reg (Yosys)",
}


def logic_only(path: Path) -> str:
    """Return the file with attributes, comments and whitespace removed."""
    text = path.read_text(encoding="utf-8", errors="replace")
    text = re.sub(r"\(\*.*?\*\)", " ", text, flags=re.S)   # (* attributes *)
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)     # /* block comments */
    text = re.sub(r"//[^\n]*", " ", text)                  # // line comments
    text = re.sub(r"\s+", " ", text)
    text = text.replace("; ", ";").replace(" ;", ";").replace(", ", ",")

    # `reg a;reg b;` and `reg a,b;` are the same declaration written two ways.
    # Split every multi-name declaration into one name per statement so that
    # formatting alone can never trip the divergence check.
    def split_decl(m):
        kw, names = m.group(1), m.group(2)
        return "".join(f"{kw} {n};" for n in names.split(","))

    text = re.sub(r"\b(reg|wire|integer)\s+([A-Za-z_][\w,]*);", split_decl, text)
    return text.strip()


def check_fork(name: str) -> bool:
    """True if the forked file differs only in attributes/formatting."""
    a, b = RTL / name, DST / name
    if not a.exists() or not b.exists():
        print(f"  ERROR: forked file missing ({a if not a.exists() else b})")
        return False
    if logic_only(a) == logic_only(b):
        print(f"  equivalence OK - {name} differs only in attributes")
        return True

    print(f"\n  *** LOGIC DIVERGENCE in {name} ***")
    print("  The FPGA and ASIC copies no longer describe the same circuit.")
    print("  A functional edit was made to one copy and not the other.")
    print("")
    print(f"    FPGA : {a}")
    print(f"    ASIC : {b}")
    print("")
    print("  Port the change across by hand, keeping each copy's own CDC")
    print("  attribute, then re-run this script.  Do NOT harden until this")
    print("  passes - the ASIC would be built from stale logic.")
    return False


def main() -> int:
    DST.mkdir(parents=True, exist_ok=True)
    failures = []

    for name in FILES:
        if name in FORKED:
            print(f"kept {name} ({FORKED[name]})")
            if not check_fork(name):
                failures.append(name)
            continue

        src = RTL / name
        if not src.exists():
            raise SystemExit(f"missing RTL source: {src}")
        shutil.copy2(src, DST / name)
        print(f"synced {name}")

    if failures:
        print(f"\nFAILED: {len(failures)} forked file(s) have diverged: "
              f"{', '.join(failures)}")
        return 1

    print("\nAll 8 layout sources are in sync "
          "(7 copied byte-for-byte, 1 forked and verified equivalent).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
