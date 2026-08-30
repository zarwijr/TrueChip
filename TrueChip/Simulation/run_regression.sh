#!/usr/bin/env bash
# ============================================================
# TrueChip v7.2 - full RTL regression
# ============================================================
# Usage (from the project root):
#     bash Simulation/run_regression.sh
#
# Requires: iverilog (Icarus Verilog 11 or newer, -g2012 support).
#     Ubuntu/Debian : sudo apt-get install iverilog
#     macOS         : brew install icarus-verilog
#
# Exits non-zero if any testbench fails, so it is safe to use in CI.
# ============================================================

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RTL="$ROOT/RTL"
SIM="$ROOT/Simulation"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

# ------------------------------------------------------------------
# Stale-file guard.
#
# The v7.2 package requires Simulation/auth_fsm_tb.v to stay deleted (a
# duplicate module that makes the whole directory fail to compile) and
# Simulation/secure_soc_top_tb.v (a
# testbench that sent CRC-less V1 frames and printed "[PASS]" without
# checking anything).  Both reappeared in the run_4 package, because
# overlaying the patch onto the old tree copies files in but never removes
# them.  Catch that here instead of letting it silently rot the results.
# ------------------------------------------------------------------
STALE=0
for f in "$SIM/auth_fsm_tb.v" "$SIM/secure_soc_top_tb.v"; do
    if [ -e "$f" ]; then
        echo "[FAIL] stale file must be deleted: $f"
        STALE=1
    fi
done
if [ "$STALE" -ne 0 ]; then
    echo ""
    echo "  auth_fsm_tb.v      : duplicate 'auth_fsm_tb' module - breaks compilation"
    echo "  secure_soc_top_tb.v: prints [PASS] unconditionally without checking anything"
    echo ""
    echo "  Delete both, then re-run.  See CHANGELOG_v7.1.md section 1."
    exit 1
fi

run_tb () {
    local name="$1"; shift
    local out="$WORK/$name.out"

    echo ""
    echo "============================================================"
    echo " $name"
    echo "============================================================"

    if ! iverilog -g2012 -o "$out" "$@" 2>&1; then
        echo "[FAIL] $name : compile error"
        FAIL=$((FAIL + 1))
        return
    fi

    # A testbench signals failure with $fatal (non-zero exit) and/or by
    # printing a line starting with [FAIL].  Check both.
    local log="$WORK/$name.log"
    if ( cd "$WORK" && vvp "$out" ) > "$log" 2>&1; then
        cat "$log"
        if grep -q '^\[FAIL\]' "$log"; then
            echo "[FAIL] $name : testbench reported failures"
            FAIL=$((FAIL + 1))
        else
            PASS=$((PASS + 1))
        fi
    else
        cat "$log"
        echo "[FAIL] $name : simulation exited non-zero"
        FAIL=$((FAIL + 1))
    fi
}

# ---- unit tests -------------------------------------------------------
run_tb "aes128"          "$SIM/tb_aes128.v"      "$RTL/aes128.v" "$RTL/aes_sbox.v"
run_tb "uart_loopback"   "$SIM/uart_tb.v"        "$RTL/uart_rx.v" "$RTL/uart_tx.v"
run_tb "cmd_parser"      "$SIM/cmd_parser_tb.v"  "$RTL/cmd_parser.v"
run_tb "auth_fsm"        "$SIM/auth_fsm_tb.sv"   "$RTL/auth_fsm.v"
run_tb "uart_echo"       "$SIM/uart_echo_tb.v"   "$RTL/uart_echo.v" "$RTL/uart_rx.v" "$RTL/uart_tx.v"

# ---- RO-PUF (FPGA path) -----------------------------------------------
# Needs -DRO_PUF_SIM: the ring oscillators are zero-delay combinational
# loops in synthesis form and would hang the simulator at time 0.  The
# macro swaps in a delay-annotated model and is never synthesised.
echo ""
echo "============================================================"
echo " ro_puf"
echo "============================================================"
if iverilog -g2012 -DRO_PUF_SIM -o "$WORK/ro_puf.out" \
        "$SIM/ro_puf_tb.v" "$RTL/ro_puf.v" 2>&1; then
    if ( cd "$WORK" && vvp "$WORK/ro_puf.out" ) > "$WORK/ro_puf.log" 2>&1; then
        cat "$WORK/ro_puf.log"
        if grep -q '^\[FAIL\]' "$WORK/ro_puf.log"; then
            echo "[FAIL] ro_puf : testbench reported failures"
            FAIL=$((FAIL + 1))
        else
            PASS=$((PASS + 1))
        fi
    else
        cat "$WORK/ro_puf.log"
        echo "[FAIL] ro_puf : simulation exited non-zero"
        FAIL=$((FAIL + 1))
    fi
else
    echo "[FAIL] ro_puf : compile error"
    FAIL=$((FAIL + 1))
fi

# ---- full-chip test ---------------------------------------------------
run_tb "secure_asic_top" "$SIM/secure_asic_top_tb.v" \
    "$RTL/secure_asic_top.v" "$RTL/uart_rx.v" "$RTL/uart_tx.v" \
    "$RTL/cmd_parser.v" "$RTL/auth_fsm.v" "$RTL/aes128.v" \
    "$RTL/aes_sbox.v" "$RTL/chip_rom.v"

# ---- elaboration-only check of the FPGA top ---------------------------
# secure_soc_top contains the FPGA RO-PUF ring oscillators, which are not a
# meaningful zero-delay simulation model.  Only check that it elaborates.
echo ""
echo "============================================================"
echo " secure_soc_top (elaboration only)"
echo "============================================================"
if iverilog -g2012 -o "$WORK/soc.out" -s secure_soc_top "$RTL"/*.v 2>&1; then
    echo "[PASS] secure_soc_top elaborates cleanly"
    PASS=$((PASS + 1))
else
    echo "[FAIL] secure_soc_top failed to elaborate"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "============================================================"
echo " REGRESSION SUMMARY: $PASS passed, $FAIL failed"
echo "============================================================"

[ "$FAIL" -eq 0 ] || exit 1
