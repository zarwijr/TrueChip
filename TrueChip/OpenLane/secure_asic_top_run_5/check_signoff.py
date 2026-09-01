#!/usr/bin/env python3
"""
check_signoff.py - TrueChip signoff scorecard for an OpenLane run.

WHY THIS EXISTS
---------------
"Flow complete" does not mean "ready to submit".  run_4 finished the flow,
passed DRC/LVS/XOR and closed timing, yet still had 9 antenna violations,
687 max-slew violations, 2151 max-fanout violations, a CVC/ERC abort and a
KLayout DRC check that never ran.  Spotting that required reading six
different files by hand.

This script reads them for you and prints one verdict.  Run it after every
OpenLane run and paste the output into the report.

USAGE
    python3 check_signoff.py                 # newest run under runs/
    python3 check_signoff.py runs/run_5      # a specific run
    python3 check_signoff.py --json          # machine-readable

EXIT CODE
    0 = every gate passed
    1 = at least one BLOCKER
    2 = no blockers, but at least one WARNING to disclose in the report
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

BLOCKER = "BLOCKER"
WARN = "WARN"
OK = "OK"
INFO = "INFO"


class Check:
    def __init__(self, name, status, detail, advice=""):
        self.name = name
        self.status = status
        self.detail = detail
        self.advice = advice


def newest_run(base: Path) -> Path | None:
    runs = base / "runs"
    if not runs.is_dir():
        return None
    candidates = [d for d in runs.iterdir() if d.is_dir()]
    if not candidates:
        return None
    return max(candidates, key=lambda d: d.stat().st_mtime)


def read_metrics(run: Path) -> dict:
    f = run / "reports" / "metrics.csv"
    if not f.is_file():
        return {}
    with f.open(newline="") as fh:
        rows = list(csv.reader(fh))
    if len(rows) < 2:
        return {}
    return dict(zip(rows[0], rows[1]))


def as_num(value, default=None):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def check_flow(m: dict) -> Check:
    status_text = m.get("flow_status", "")
    if not status_text:
        return Check("Flow status", BLOCKER, "metrics.csv missing or unreadable")
    if "complete" in status_text.lower():
        return Check("Flow status", OK, status_text)
    return Check("Flow status", BLOCKER, status_text,
                 "The flow did not finish. Fix the failing step before anything else.")


def check_drc_lvs(m: dict) -> list[Check]:
    out = []

    tr = as_num(m.get("tritonRoute_violations"), -1)
    out.append(Check("Detailed-route DRC", OK if tr == 0 else BLOCKER,
                     f"{int(tr)} violations",
                     "" if tr == 0 else "Routing is not clean. Re-route or relax GRT_ADJUSTMENT."))

    mg = as_num(m.get("Magic_violations"), -1)
    out.append(Check("Magic DRC", OK if mg == 0 else BLOCKER,
                     f"{int(mg)} violations"))

    lvs = as_num(m.get("lvs_total_errors"), -1)
    out.append(Check("LVS (netgen)", OK if lvs == 0 else BLOCKER,
                     f"{int(lvs)} errors"))

    kl = as_num(m.get("klayout_violations"), -1)
    if kl == -1:
        out.append(Check(
            "KLayout DRC", BLOCKER, "NOT RUN (klayout_violations = -1)",
            "KLayout DRC is a separate check from Magic DRC, and the XOR check does "
            "NOT substitute for it. Set KLAYOUT_DRC_TECH_SCRIPT in config.json, or "
            "run ./run_klayout_drc.sh after the flow."))
    elif kl == 0:
        out.append(Check("KLayout DRC", OK, "0 violations"))
    else:
        out.append(Check("KLayout DRC", BLOCKER, f"{int(kl)} violations"))

    cvc = as_num(m.get("cvc_total_errors"), -1)
    if cvc == -1:
        out.append(Check(
            "CVC / ERC", BLOCKER, "NOT RUN or ABORTED (cvc_total_errors = -1)",
            "Check logs/signoff/*-erc_screen.log. If it says 'could not find subcircuit "
            "... sky130_ef_sc_hd__decap_12', remove that cell from DECAP_CELL: it has no "
            "subcircuit in the PDK CDL."))
    elif cvc == 0:
        out.append(Check("CVC / ERC", OK, "0 errors"))
    else:
        out.append(Check("CVC / ERC", BLOCKER, f"{int(cvc)} errors"))

    return out


def check_antenna(m: dict) -> Check:
    pin = as_num(m.get("pin_antenna_violations"), -1)
    net = as_num(m.get("net_antenna_violations"), -1)
    if pin < 0 or net < 0:
        return Check("Antenna", WARN, "not reported")
    total = int(pin) + int(net)
    detail = f"{int(pin)} pin / {int(net)} net"
    if total == 0:
        return Check("Antenna", OK, detail)
    return Check(
        "Antenna", WARN, detail,
        "Lower HEURISTIC_ANTENNA_THRESHOLD one step (250 -> 200 -> 150) and re-run. "
        "Watch the slew/fanout rows below: dropping it too far is what produced "
        "22826 diodes and thousands of DRV violations in run_4. If a handful survive, "
        "disclose them in the report with their ratios from "
        "reports/signoff/*-antenna_violators.rpt.")


def check_diodes(m: dict) -> Check:
    d = as_num(m.get("DiodeCells"), -1)
    total = as_num(m.get("TotalCells"), -1)
    synth = as_num(m.get("synth_cell_count"), -1)
    if d < 0:
        return Check("Diode count", INFO, "not reported")
    detail = f"{int(d)} diodes"
    if synth > 0:
        ratio = d / synth
        detail += f" ({ratio:.2f} per synthesised cell)"
        if ratio > 0.5:
            return Check(
                "Diode count", WARN, detail,
                "More than one diode per two logic cells means blanket insertion, not "
                "targeted repair. Each diode adds a pin and a load to its net AFTER the "
                "resizer has finished, so it directly causes the slew/fanout violations "
                "below. Raise HEURISTIC_ANTENNA_THRESHOLD.")
    return Check("Diode count", OK, detail)


def check_timing(m: dict, run: Path) -> list[Check]:
    out = []

    # Signoff STA lives in the logs, not in the metrics.csv wns/tns column.
    worst_setup = None
    worst_hold = None
    corner_rows = []
    log_dir = run / "logs" / "signoff"
    if log_dir.is_dir():
        for log in sorted(log_dir.glob("*sta*.log")):
            text_tail = ""
            try:
                with log.open(errors="replace") as fh:
                    text_tail = "".join(fh.readlines()[-60:])
            except OSError:
                continue
            slacks = re.findall(r"^worst slack\s+(-?[\d.]+)", text_tail, re.M)
            if len(slacks) >= 2:
                setup, hold = float(slacks[-2]), float(slacks[-1])
                corner_rows.append((log.name, setup, hold))
                worst_setup = setup if worst_setup is None else min(worst_setup, setup)
                worst_hold = hold if worst_hold is None else min(worst_hold, hold)

    if worst_setup is None:
        out.append(Check("Signoff STA", WARN, "no signoff STA logs found"))
    else:
        bad = worst_setup < 0 or worst_hold < 0
        out.append(Check(
            "Signoff STA", BLOCKER if bad else OK,
            f"worst setup {worst_setup:+.2f} ns, worst hold {worst_hold:+.2f} ns "
            f"across {len(corner_rows)} corner log(s)"))

    # Design-rule violations from the checks report.
    checks_rpt = None
    rpt_dir = run / "reports" / "signoff"
    if rpt_dir.is_dir():
        matches = sorted(rpt_dir.glob("*rcx_sta.checks.rpt"))
        if matches:
            checks_rpt = matches[-1]

    if checks_rpt is None:
        out.append(Check("Max slew / fanout / cap", WARN,
                         "*-rcx_sta.checks.rpt not found"))
        return out

    text = checks_rpt.read_text(errors="replace")

    def count_of(label):
        m2 = re.search(rf"{label} violation count (\d+)", text)
        return int(m2.group(1)) if m2 else None

    slew = count_of("max slew")
    fanout = count_of("max fanout")
    cap = count_of("max cap")

    # Split fanout violators into clock-tree vs data, because the clock tree
    # is sized by CTS_MAX_CAP / CTS_SINK_CLUSTERING_SIZE, not by max_fanout.
    clk_fanout = 0
    data_fanout = 0
    fan_section = text.split("max fanout\n")
    if len(fan_section) > 1:
        body = fan_section[1].split("max slew violation count")[0]
        for line in body.splitlines():
            if "VIOLATED" not in line:
                continue
            pin = line.split()[0] if line.split() else ""
            if "clkbuf" in pin or "clknet" in pin:
                clk_fanout += 1
            else:
                data_fanout += 1

    if slew is not None:
        out.append(Check(
            "Max slew", OK if slew == 0 else WARN, f"{slew} violations",
            "" if slew == 0 else
            "Dominated by diode pins when blanket insertion is on. Raise "
            "HEURISTIC_ANTENNA_THRESHOLD first, then re-check."))

    if cap is not None:
        out.append(Check("Max capacitance", OK if cap == 0 else WARN,
                         f"{cap} violations"))

    if fanout is not None:
        if fanout == 0:
            out.append(Check("Max fanout", OK, "0 violations"))
        else:
            detail = f"{fanout} violations ({data_fanout} data, {clk_fanout} clock-tree)"
            advice = ""
            if data_fanout > 0:
                advice = ("Data-net fanout violations are real: the resizer honours "
                          "MAX_FANOUT_CONSTRAINT, so anything above it was added after "
                          "the resizer ran - almost always diodes. ")
            if clk_fanout > 0:
                advice += ("Clock-tree entries are expected: CTS sizes the tree by "
                           "CTS_SINK_CLUSTERING_SIZE (25 sinks/leaf) and CTS_MAX_CAP, "
                           "not by the data fanout rule. To make the report literally "
                           "zero, set CTS_SINK_CLUSTERING_SIZE to 10 - at the cost of a "
                           "larger clock tree. Otherwise state this split in the report.")
            out.append(Check("Max fanout",
                             WARN if data_fanout > 0 else INFO,
                             detail, advice))

    m3 = re.search(r"There are (\d+) unconstrained endpoints", text)
    if m3:
        n = int(m3.group(1))
        out.append(Check(
            "Unconstrained endpoints", INFO if n <= 8 else WARN,
            f"{n} endpoints",
            "Expected and benign for this design: they are register D pins whose only "
            "source is a constant, plus the first synchroniser flop fed by uart_rx_i, "
            "which constraints.sdc false-paths on purpose. Confirmed by netlist analysis "
            "in VALIDATION_v7.2.md. Investigate only if the count changes."))

    return out


def check_metrics_wns_trap(m: dict) -> Check:
    wns = as_num(m.get("wns"))
    if wns is None:
        return Check("metrics.csv wns column", INFO, "not present")
    return Check(
        "metrics.csv wns column", INFO, f"{wns} ns  <-- DO NOT QUOTE THIS",
        "This column is copied from logs/synthesis/*-sta.log, the PRE-PLACEMENT "
        "estimate that uses wireload models. It is not the signoff result. Quote the "
        "'Signoff STA' row above and the logs/signoff/*rcx*sta*.log files instead.")


def check_results_present(run: Path) -> Check:
    res = run / "results" / "signoff"
    if not res.is_dir():
        return Check(
            "results/ in package", WARN, "results/signoff/ missing",
            "The GDS, final netlist, DEF and SPEF live here. Without them nobody can "
            "checksum the layout against the RTL, and run_klayout_drc.sh cannot run. "
            "Include runs/<run>/results/ in the submission ZIP.")
    gds = list(res.glob("*.gds"))
    return Check("results/ in package", OK if gds else WARN,
                 f"{len(gds)} GDS file(s) present")


def check_synth_noise(run: Path) -> list[Check]:
    out = []
    err = run / "logs" / "synthesis" / "1-synthesis.errors"
    warn = run / "logs" / "synthesis" / "1-synthesis.warnings"

    if err.is_file():
        text = err.read_text(errors="replace")
        if "The network is combinational" in text:
            out.append(Check(
                "Yosys/ABC 'network is combinational'", INFO, "present",
                "Benign. ABC's script runs 'retime' then 'scleanup'; scleanup is a "
                "SEQUENTIAL command and yosys hands ABC a combinational network, so it "
                "declines and the flow continues. It appears in every OpenLane run with "
                "a retiming synth strategy. No action needed, but say so in the report "
                "so a judge reading the .errors file is not alarmed."))

    if warn.is_file():
        text = warn.read_text(errors="replace")
        n = text.count("is used but has no driver")
        if n:
            out.append(Check(
                "Yosys 'output has no driver'", INFO, f"{n} top-level outputs",
                "Benign artefact of yosys's 'check' pass running right after 'insbuf' "
                "(OpenLane issue #1827). The DEF creates all pins and LVS passes. "
                "Confirm on your machine with:  grep -c 'uart_tx_o' "
                "runs/<run>/results/routing/secure_asic_top.nl.v"))

    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="TrueChip OpenLane signoff scorecard")
    ap.add_argument("run", nargs="?", help="run directory, e.g. runs/run_5")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    base = Path(__file__).resolve().parent

    if args.run:
        run = Path(args.run)
        if not run.is_absolute():
            run = (base / args.run).resolve() if not Path(args.run).is_dir() else Path(args.run).resolve()
    else:
        found = newest_run(base)
        if found is None:
            print("ERROR: no runs/ directory found next to this script.", file=sys.stderr)
            return 1
        run = found

    if not run.is_dir():
        print(f"ERROR: not a directory: {run}", file=sys.stderr)
        return 1

    m = read_metrics(run)
    if not m:
        print(f"ERROR: could not read {run}/reports/metrics.csv", file=sys.stderr)
        return 1

    checks: list[Check] = [check_flow(m)]
    checks += check_drc_lvs(m)
    checks.append(check_antenna(m))
    checks.append(check_diodes(m))
    checks += check_timing(m, run)
    checks.append(check_metrics_wns_trap(m))
    checks.append(check_results_present(run))
    checks += check_synth_noise(run)

    if args.json:
        print(json.dumps({
            "run": str(run),
            "checks": [{"name": c.name, "status": c.status,
                        "detail": c.detail, "advice": c.advice} for c in checks],
        }, indent=2))
    else:
        width = max(len(c.name) for c in checks) + 2
        print("=" * 72)
        print(f" TrueChip signoff scorecard")
        print(f" run    : {run}")
        print(f" design : {m.get('design_name', '?')}")
        print("=" * 72)
        for c in checks:
            print(f"  [{c.status:^7}] {c.name:<{width}} {c.detail}")
        print("=" * 72)

        advised = [c for c in checks if c.advice]
        if advised:
            print(" NOTES")
            print("-" * 72)
            for c in advised:
                print(f" * {c.name}:")
                for line in _wrap(c.advice, 68):
                    print(f"     {line}")
                print()

    blockers = [c for c in checks if c.status == BLOCKER]
    warns = [c for c in checks if c.status == WARN]

    if not args.json:
        print("=" * 72)
        if blockers:
            print(f" VERDICT: NOT READY - {len(blockers)} blocker(s), {len(warns)} warning(s)")
            for c in blockers:
                print(f"          BLOCKER: {c.name} ({c.detail})")
        elif warns:
            print(f" VERDICT: SUBMITTABLE WITH DISCLOSURE - {len(warns)} warning(s)")
            for c in warns:
                print(f"          disclose: {c.name} ({c.detail})")
        else:
            print(" VERDICT: CLEAN - every signoff gate passed")
        print("=" * 72)

    if blockers:
        return 1
    if warns:
        return 2
    return 0


def _wrap(text: str, width: int) -> list[str]:
    words = text.split()
    lines, cur = [], ""
    for w in words:
        if len(cur) + len(w) + 1 > width:
            lines.append(cur)
            cur = w
        else:
            cur = f"{cur} {w}".strip()
    if cur:
        lines.append(cur)
    return lines


if __name__ == "__main__":
    raise SystemExit(main())
