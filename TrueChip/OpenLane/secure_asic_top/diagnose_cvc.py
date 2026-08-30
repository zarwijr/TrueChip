#!/usr/bin/env python3
"""
diagnose_cvc.py - find why CVC/ERC aborts on this design.

WHY THIS EXISTS
---------------
run_5 CVC dies with:

    CVC: Setting models ...
    unexpected error: Resistance error:missing parameter: l in l/w*48

CVC parsed the whole netlist first (106167 instances, 139835 nets,
362924 devices), so the CDL itself is readable.  It then failed while
BINDING devices to models.  48 ohm/sq is the sky130 non-silicided poly
sheet resistance, so some device is being matched against a poly-resistor
model whose formula needs an `l` parameter that the instance does not
carry.

This is a model-resolution problem between the extracted CDL and the PDK's
CVC model file - not a design defect.  CVC never reached the stage where it
reports real ERC violations.

WHAT WAS ALREADY RULED OUT
--------------------------
  * sky130_ef_sc_hd__decap_12 - was the run_4 cause ("could not find
    subcircuit").  The DECAP_CELL override in config.json fixed it and must
    stay.  It is not the run_5 cause: run_5 gets much further.
  * sky130_ef_sc_hd__fakediode_2 - NOT instantiated.  FAKEDIODE_CELL is
    only used when DIODE_INSERTION_STRATEGY is 2, and we deliberately leave
    DIODE_INSERTION_STRATEGY unset.  Confirmed absent from run_5's logs.

USAGE (run on the build machine - the CDL is not in packaged ZIPs)
------------------------------------------------------------------
    export PDK_ROOT=$HOME/PDKs          # same value OpenLane uses
    python3 diagnose_cvc.py runs/run_6

It prints every resistor-like device that has no `l`, grouped by the
subcircuit that contains it, so you can see at a glance which cell is
responsible.

TIME-BOX
--------
If this does not point at something you can fix in one config change, STOP
and ship with disclosure.  Three independent signoff tools (Magic DRC,
KLayout DRC, Netgen LVS) already report zero.  See the wording in
REPORT_DRAFT_v7.2.md.
"""

from __future__ import annotations

import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


def find_cdl(run: Path) -> Path | None:
    for pat in ("tmp/signoff/*.cdl", "tmp/**/*.cdl", "results/**/*.cdl"):
        hits = sorted(run.glob(pat))
        if hits:
            return hits[-1]
    return None


def find_models() -> Path | None:
    pdk_root = os.environ.get("PDK_ROOT")
    pdk = os.environ.get("PDK", "sky130A")
    if not pdk_root:
        return None
    cand = Path(pdk_root) / pdk / "libs.tech" / "openlane" / "cvc" / "models"
    return cand if cand.is_file() else None


def report_models(models: Path) -> set[str]:
    """Return the set of device-model names CVC treats as resistors."""
    names: set[str] = set()
    print(f"\n--- CVC model file: {models}")
    for line in models.read_text(errors="replace").splitlines():
        s = line.strip()
        if not s or s.startswith("#") or s.startswith("*"):
            continue
        # CVC model lines look like:  R  <name>  ... r=l/w*48 ...
        if re.match(r"^R\b", s) or "l/w" in s:
            print(f"    {s}")
            m = re.match(r"^R\s+(\S+)", s)
            if m:
                names.add(m.group(1).lower())
    if not names:
        print("    (no resistor model lines matched - inspect the file by hand)")
    return names


def scan_cdl(cdl: Path) -> None:
    """Walk the CDL, tracking the enclosing .subckt for every R device."""
    print(f"\n--- Extracted netlist: {cdl}  ({cdl.stat().st_size/1e6:.1f} MB)")

    current = "(top level)"
    total_r = 0
    missing_l: Counter[str] = Counter()
    missing_examples: dict[str, str] = {}
    subckt_r: Counter[str] = Counter()

    with cdl.open(errors="replace") as fh:
        pending = ""
        for raw in fh:
            line = raw.rstrip("\n")
            # SPICE line continuation
            if line.startswith("+"):
                pending += " " + line[1:].strip()
                continue
            if pending:
                _classify(pending, current, missing_l, missing_examples, subckt_r)
                if pending.lstrip().lower().startswith("r"):
                    total_r += 1
            pending = ""

            s = line.strip()
            low = s.lower()
            if low.startswith(".subckt"):
                parts = s.split()
                current = parts[1] if len(parts) > 1 else "(unnamed)"
                continue
            if low.startswith(".ends"):
                current = "(top level)"
                continue
            if low.startswith("r") or low.startswith("xr"):
                pending = s
                continue

        if pending:
            _classify(pending, current, missing_l, missing_examples, subckt_r)
            total_r += 1

    print(f"\n--- Resistor-like devices found: {total_r}")
    if subckt_r:
        print("\n    Resistors per subcircuit (top 15):")
        for name, n in subckt_r.most_common(15):
            print(f"      {n:6d}  {name}")

    print("\n" + "=" * 68)
    if not missing_l:
        print(" No resistor instance is missing an `l` parameter.")
        print("")
        print(" That means the culprit is NOT a plain R device in the CDL.")
        print(" Most likely CVC is binding a SUBCIRCUIT (an X... line) to a")
        print(" resistor model by name.  Next step: grep the CDL for the")
        print(" cells that are unique to this run, e.g.")
        print("     grep -o 'sky130_[a-z_0-9]*' <cdl> | sort -u")
        print(" and compare that list against the model file above.")
    else:
        print(" RESISTOR INSTANCES WITH NO `l` PARAMETER")
        print("=" * 68)
        for name, n in missing_l.most_common():
            print(f"\n  subcircuit: {name}   ({n} instance(s))")
            print(f"  example   : {missing_examples[name][:160]}")
        print("")
        print(" ACTION: if the subcircuit above is an sky130_ef_sc_hd__* cell,")
        print(" override the matching *_CELL variable in config.json to use the")
        print(" sky130_fd_sc_hd equivalent - the same fix that cleared the")
        print(" decap_12 failure in run_4.")
    print("=" * 68)


def _classify(line: str, subckt: str,
              missing_l: Counter, examples: dict, subckt_r: Counter) -> None:
    low = line.lower()
    if not (low.startswith("r") or low.startswith("xr")):
        return
    subckt_r[subckt] += 1
    if not re.search(r"\bl\s*=", low):
        missing_l[subckt] += 1
        examples.setdefault(subckt, line)


def list_unique_cells(cdl: Path) -> None:
    """Show which library cells appear, so ef- vs fd- cells stand out."""
    cells = Counter()
    pat = re.compile(r"sky130_[a-z]{2}_[a-z_0-9]+")
    with cdl.open(errors="replace") as fh:
        for line in fh:
            if line.lstrip().lower().startswith(".subckt"):
                for m in pat.findall(line):
                    cells[m] += 1
    ef = sorted(c for c in cells if "_ef_" in c)
    print("\n--- Library cells defined in the CDL")
    print(f"    total distinct: {len(cells)}")
    if ef:
        print("    efabless-generated (sky130_ef_*) cells present - these are the")
        print("    usual suspects for model-resolution failures:")
        for c in ef:
            print(f"      {c}")
    else:
        print("    no sky130_ef_* cells present.")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        print("ERROR: pass a run directory, e.g.  python3 diagnose_cvc.py runs/run_6",
              file=sys.stderr)
        return 2

    run = Path(sys.argv[1]).resolve()
    if not run.is_dir():
        print(f"ERROR: not a directory: {run}", file=sys.stderr)
        return 2

    print("=" * 68)
    print(" CVC failure diagnosis")
    print(f" run: {run}")
    print("=" * 68)

    models = find_models()
    if models:
        report_models(models)
    else:
        print("\n--- CVC model file: NOT FOUND")
        print("    Set PDK_ROOT to the value OpenLane uses, e.g.")
        print("      export PDK_ROOT=$HOME/PDKs")

    cdl = find_cdl(run)
    if cdl is None:
        print("\n--- Extracted netlist: NOT FOUND")
        print("    Expected tmp/signoff/<design>.cdl")
        print("")
        print("    OpenLane deletes tmp/ when a run is archived, and packaged")
        print("    ZIPs exclude it. Run this on the build machine right after")
        print("    the flow, before cleaning up.")
        return 1

    list_unique_cells(cdl)
    scan_cdl(cdl)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
