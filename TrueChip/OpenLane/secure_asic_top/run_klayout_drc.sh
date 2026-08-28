#!/usr/bin/env bash
# ============================================================
# run_klayout_drc.sh - standalone KLayout DRC for TrueChip
# ============================================================
# WHY THIS EXISTS
# ---------------
# run_4 reported klayout_violations = -1 because OpenLane skipped the step:
#
#   [WARNING]: ::env(KLAYOUT_DRC_TECH_SCRIPT) is not defined or doesn't
#              exist for the current PDK. So, GDSII streaming out using
#              KLayout will be skipped.
#
# The sky130A PDK ships the DRC runset (sky130A_mr.drc) but does not
# populate KLAYOUT_DRC_TECH_SCRIPT, so the check silently never runs.
# v7.2's config.json now sets that variable, but the exact name and the
# path convention differ between OpenLane releases.  This script does the
# check directly, so the submission can carry real KLayout DRC evidence
# regardless of which OpenLane version is installed.
#
# Note that KLayout DRC is NOT the same check as Magic DRC, and it is not
# covered by the XOR check either.  XOR only proves the Magic-written GDS
# and the KLayout-written GDS describe the same polygons; it says nothing
# about whether those polygons obey the design rules.
#
# USAGE
#   ./run_klayout_drc.sh                 # newest run under runs/
#   ./run_klayout_drc.sh runs/run_5      # a specific run
#
# REQUIREMENTS
#   klayout on PATH, and PDK_ROOT set (same value OpenLane uses).
# ============================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

RUN_DIR="${1:-}"
if [ -z "$RUN_DIR" ]; then
    RUN_DIR="$(ls -dt runs/*/ 2>/dev/null | head -1 || true)"
    RUN_DIR="${RUN_DIR%/}"
fi

if [ -z "$RUN_DIR" ] || [ ! -d "$RUN_DIR" ]; then
    echo "ERROR: no run directory found. Pass one explicitly, e.g."
    echo "       $0 runs/run_5"
    exit 1
fi

: "${PDK_ROOT:?PDK_ROOT is not set. Export the same value OpenLane uses, e.g. export PDK_ROOT=\$HOME/PDKs}"

PDK="${PDK:-sky130A}"
RUNSET="$PDK_ROOT/$PDK/libs.tech/klayout/drc/${PDK}_mr.drc"
GDS="$RUN_DIR/results/signoff/secure_asic_top.gds"
OUT_DIR="$RUN_DIR/reports/signoff"
REPORT="$OUT_DIR/klayout_drc.xml"
LOG="$RUN_DIR/logs/signoff/klayout_drc.log"

if ! command -v klayout >/dev/null 2>&1; then
    echo "ERROR: klayout not found on PATH."
    exit 1
fi

if [ ! -f "$RUNSET" ]; then
    echo "ERROR: DRC runset not found: $RUNSET"
    echo "       Check PDK_ROOT / PDK, or locate the runset with:"
    echo "         find \"\$PDK_ROOT\" -name '*_mr.drc'"
    exit 1
fi

if [ ! -f "$GDS" ]; then
    echo "ERROR: GDS not found: $GDS"
    echo "       The results/ directory is required. If this ZIP was trimmed,"
    echo "       re-run the flow or unpack the full run."
    exit 1
fi

mkdir -p "$OUT_DIR" "$(dirname "$LOG")"

echo "PDK     : $PDK  ($PDK_ROOT)"
echo "Runset  : $RUNSET"
echo "GDS     : $GDS"
echo "Report  : $REPORT"
echo ""
echo "Running KLayout DRC (this takes several minutes)..."

klayout -b \
    -r "$RUNSET" \
    -rd "input=$GDS" \
    -rd "topcell=secure_asic_top" \
    -rd "report=$REPORT" \
    -rd "feol=true" \
    -rd "beol=true" \
    -rd "offgrid=true" \
    -rd "seal=false" \
    -rd "threads=4" \
    2>&1 | tee "$LOG"

echo ""
if [ -f "$REPORT" ]; then
    COUNT="$(grep -c '<item>' "$REPORT" 2>/dev/null || echo 0)"
    echo "============================================================"
    echo " KLayout DRC violations: $COUNT"
    echo " Report: $REPORT"
    echo " Log   : $LOG"
    echo "============================================================"
    if [ "$COUNT" -eq 0 ]; then
        echo "RESULT: PASS"
    else
        echo "RESULT: FAIL - open the report in KLayout to inspect:"
        echo "  klayout -e $GDS -m $REPORT"
        exit 1
    fi
else
    echo "WARNING: no report was produced. Check $LOG."
    exit 1
fi
