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

# ------------------------------------------------------------------
# REQUIRES ICARUS VERILOG (iverilog).
#
# If you use Questa/ModelSim instead, do NOT use this script - run
#     cd Simulation/questa
#     vsim -c -do regression.do
# which does exactly the same checks through Questa.
# ------------------------------------------------------------------
if ! command -v iverilog >/dev/null 2>&1; then
    echo "ERROR: iverilog not found on PATH."
    echo ""
    echo "  This script drives Icarus Verilog. If you have Questa or"
    echo "  ModelSim, use the Questa regression instead:"
    echo ""
    echo "      cd Simulation/questa"
    echo "      vsim -c -do regression.do"
    echo ""
    echo "  To install Icarus instead:"
    echo "      Ubuntu/Debian : sudo apt-get install iverilog"
    echo "      macOS         : brew install icarus-verilog"
    echo "      Windows       : https://bleyer.org/icarus/  (then add to PATH)"
    exit 127
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RTL="$ROOT/RTL"
SIM="$ROOT/Simulation"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ------------------------------------------------------------------
# Portability gate.
#
# Icarus accepts things Questa rejects, so a testbench can pass here and
# still fail to compile on the tool actually used for waveform capture.
# Check before running anything.
# ------------------------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
    echo "--- checking testbench portability (Icarus vs Questa) ---"
    if ! python3 "$SIM/check_tb_portability.py" "$SIM"/*.v "$SIM"/*.sv; then
        echo ""
        echo "[FAIL] testbenches use constructs Questa will reject."
        echo "       Fix these before capturing waveforms."
        exit 1
    fi
    echo ""
fi

PASS=0
FAIL=0

# ------------------------------------------------------------------
# Stale-file guard.
#
# v7.1 deleted Simulation/auth_fsm_tb.v - a duplicate module that makes
# the whole directory fail to compile. It reappeared once already,
# because overlaying a patch onto an old tree copies files in but never
# removes them. Catch that here instead of letting it silently rot the
# results.
#
# NOTE: secure_soc_top_tb.v used to be on this list too. The file that
# was banned was the legacy one that sent CRC-less V1 frames and printed
# "[PASS]" unconditionally. It has since been REPLACED by a real
# self-checking FPGA top-level testbench, so the name is no longer
# forbidden - it is required. The retired original still lives at
# Simulation/fpga_only/secure_soc_top_tb_legacy.v for reference.
# ------------------------------------------------------------------
STALE=0
for f in "$SIM/auth_fsm_tb.v"; do
    if [ -e "$f" ]; then
        echo "[FAIL] stale file must be deleted: $f"
        echo "       duplicate 'auth_fsm_tb' module - breaks compilation"
        echo "       Keep auth_fsm_tb.sv (the rewritten one) instead."
        STALE=1
    fi
done

# The legacy fake-PASS testbench must not be the one in Simulation/.
if [ -e "$SIM/secure_soc_top_tb.v" ] && \
   ! grep -q "independent AES" "$SIM/secure_soc_top_tb.v" 2>/dev/null; then
    echo "[FAIL] $SIM/secure_soc_top_tb.v looks like the legacy fake-PASS testbench"
    echo "       (it prints [PASS] without checking anything)."
    echo "       Restore the self-checking version from the v7.2 package."
    STALE=1
fi

if [ "$STALE" -ne 0 ]; then
    echo ""
    echo "  See CHANGELOG_v7.1.md section 1."
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

# ---- FPGA top-level (with the real RO-PUF) ----------------------------
# Needs -DRO_PUF_SIM. The testbench shrinks the PUF via defparam so the
# ring oscillators produce a tractable number of events.
echo ""
echo "============================================================"
echo " secure_soc_top (FPGA top, with RO-PUF)"
echo "============================================================"
if iverilog -g2012 -DRO_PUF_SIM -o "$WORK/soc_tb.out" \
        "$SIM/secure_soc_top_tb.v" "$RTL"/*.v 2>&1; then
    if ( cd "$WORK" && vvp "$WORK/soc_tb.out" ) > "$WORK/soc_tb.log" 2>&1; then
        cat "$WORK/soc_tb.log"
        if grep -q '^\[FAIL\]' "$WORK/soc_tb.log"; then
            echo "[FAIL] secure_soc_top : testbench reported failures"
            FAIL=$((FAIL + 1))
        else
            PASS=$((PASS + 1))
        fi
    else
        cat "$WORK/soc_tb.log"
        echo "[FAIL] secure_soc_top : simulation exited non-zero"
        FAIL=$((FAIL + 1))
    fi
else
    echo "[FAIL] secure_soc_top : compile error"
    FAIL=$((FAIL + 1))
fi

# ---- full-chip test ---------------------------------------------------
run_tb "secure_asic_top" "$SIM/secure_asic_top_tb.v" \
    "$RTL/secure_asic_top.v" "$RTL/uart_rx.v" "$RTL/uart_tx.v" \
    "$RTL/cmd_parser.v" "$RTL/auth_fsm.v" "$RTL/aes128.v" \
    "$RTL/aes_sbox.v" "$RTL/chip_rom.v"

echo ""
echo "============================================================"
echo " REGRESSION SUMMARY: $PASS passed, $FAIL failed"
echo "============================================================"

[ "$FAIL" -eq 0 ] || exit 1
