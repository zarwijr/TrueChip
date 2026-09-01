# ============================================================
# common.do - shared setup for every TrueChip Questa run
# ============================================================
# Sourced by every other .do file. Not meant to be run on its own.
#
# It does three things:
#   1. works out where the project root is, whatever directory vsim
#      was started from;
#   2. creates/maps the work library under Simulation/questa/work, so
#      Questa's build artefacts never litter RTL/ or Simulation/;
#   3. compiles the RTL and the testbenches.
#
# Two vsim options matter a great deal for this workflow and are used
# by every script:
#
#   -voptargs=+acc   keeps internal signals visible. Without it Questa
#                    optimises them away and half the waveform is empty.
#
#   -onfinish stop   stops at $finish instead of closing the simulator.
#                    This is what lets you take a screenshot after the
#                    run completes. Without it vsim exits and the wave
#                    window disappears.
# ============================================================

# --- locate the project root -------------------------------------------
# NOTE: Questa's `do` is not Tcl's `source`, so [info script] does NOT
# give this file's path - it returns Questa's own install directory
# (e.g. C:/mtitcl/vsim). Everything must be derived from the current
# working directory instead, which is wherever vsim was started.
#
# Normal usage is to start vsim from Simulation/questa, but the search
# below also copes with starting from Simulation/ or from the project
# root, so a wrong starting directory gives a clear message rather than
# a confusing "failed to create directory C:/mtitcl/vsim/work".
#
# To override explicitly, set TC_QUESTA_DIR before sourcing, e.g.
#     set TC_QUESTA_DIR C:/GitHub/TrueChip/TrueChip/Simulation/questa
#     do common.do

if {[info exists TC_QUESTA_DIR]} {
    set QUESTA_DIR [file normalize $TC_QUESTA_DIR]
} else {
    set _cwd [file normalize [pwd]]
    set QUESTA_DIR ""
    foreach _cand [list \
            $_cwd \
            [file join $_cwd questa] \
            [file join $_cwd Simulation questa] \
            [file join $_cwd ..] \
            [file join $_cwd .. questa]] {
        if {[file exists [file join $_cand common.do]]} {
            set QUESTA_DIR [file normalize $_cand]
            break
        }
    }
    if {$QUESTA_DIR eq ""} {
        echo ""
        echo "============================================================"
        echo " ERROR: cannot locate Simulation/questa from here."
        echo ""
        echo " Current directory: $_cwd"
        echo ""
        echo " Start Questa from the questa folder:"
        echo "     cd <project>/Simulation/questa"
        echo "     vsim -c -do regression.do"
        echo ""
        echo " Or set the path explicitly before running:"
        echo "     set TC_QUESTA_DIR C:/path/to/TrueChip/Simulation/questa"
        echo "============================================================"
        error "TrueChip: project root not found"
    }
}

set PROJ [file normalize [file join $QUESTA_DIR .. ..]]
set RTL  $PROJ/RTL
set SIM  $PROJ/Simulation
set WORK $QUESTA_DIR/work

# Sanity-check the layout before doing anything destructive.
if {![file exists $RTL/aes128.v]} {
    echo ""
    echo "============================================================"
    echo " ERROR: RTL not found where expected."
    echo "   questa dir : $QUESTA_DIR"
    echo "   project    : $PROJ"
    echo "   looked for : $RTL/aes128.v"
    echo ""
    echo " The questa folder must sit at <project>/Simulation/questa."
    echo "============================================================"
    error "TrueChip: RTL directory not found"
}

echo "TrueChip: project = $PROJ"
echo "TrueChip: work    = $WORK"

# --- self-check the .do scripts ---------------------------------------
# Questa's `echo` runs its argument through Tcl, so an unescaped [PASS]
# in a message is treated as a command and errors out AFTER the test has
# already passed. check_do_syntax.py catches that (and brace imbalance)
# before anything runs. Silently skipped if python3 is not on PATH.
if {[file exists $QUESTA_DIR/check_do_syntax.py]} {
    if {[catch {exec python3 $QUESTA_DIR/check_do_syntax.py} _out]} {
        if {[string match "*WOULD FAIL IN QUESTA*" $_out]} {
            echo $_out
            echo ""
            echo "ERROR: a .do script has a Tcl problem - fix it before running."
            error "TrueChip: .do syntax check failed"
        }
    }
}

# --- work library ------------------------------------------------------
if {![file exists $WORK]} {
    vlib $WORK
}
vmap work $WORK

# --- compile -----------------------------------------------------------
# +define+RO_PUF_SIM swaps the ring oscillators for a delay-annotated
# model. Without it they are zero-delay combinational loops and the
# simulator hangs at time 0. It is simulation-only and never synthesised.
#
# -timescale is forced because a few RTL files have no `timescale
# directive of their own; leaving it to chance produces confusing
# time units in the waveform.

proc tc_compile {} {
    global RTL SIM

    echo "--- compiling RTL ---"
    vlog -quiet -timescale 1ns/1ps +define+RO_PUF_SIM \
        $RTL/aes_sbox.v \
        $RTL/aes128.v \
        $RTL/uart_rx.v \
        $RTL/uart_tx.v \
        $RTL/uart_echo.v \
        $RTL/chip_rom.v \
        $RTL/cmd_parser.v \
        $RTL/auth_fsm.v \
        $RTL/ro_puf.v \
        $RTL/secure_asic_top.v \
        $RTL/secure_soc_top.v

    echo "--- compiling testbenches ---"
    vlog -quiet -timescale 1ns/1ps $SIM/tb_aes128.v
    vlog -quiet -timescale 1ns/1ps $SIM/uart_tb.v
    vlog -quiet -timescale 1ns/1ps $SIM/uart_echo_tb.v
    vlog -quiet -timescale 1ns/1ps $SIM/cmd_parser_tb.v
    vlog -quiet -timescale 1ns/1ps $SIM/ro_puf_tb.v
    vlog -quiet -timescale 1ns/1ps $SIM/secure_asic_top_tb.v
    vlog -quiet -timescale 1ns/1ps $SIM/secure_soc_top_tb.v
    vlog -quiet -sv -timescale 1ns/1ps $SIM/auth_fsm_tb.sv

    echo "--- compile finished ---"
}

# --- wave window cosmetics --------------------------------------------
# Screenshots are the deliverable here, so the defaults are tuned for
# legibility rather than density.
proc tc_wave_setup {} {
    configure wave -namecolwidth  260
    configure wave -valuecolwidth 160
    configure wave -justifyvalue left
    configure wave -signalnamewidth 1   ;# show leaf names, not full paths
    configure wave -timelineunits ns
    configure wave -rowmargin 4
    configure wave -childrowmargin 2
}

# --- close any previous simulation ------------------------------------
proc tc_reset_sim {} {
    if {[catch {quit -sim}]} {
        # nothing was loaded - fine
    }
    if {[catch {delete wave /*}]} {
        # no wave window yet - fine
    }
}

# --- end-of-script banner ---------------------------------------------
proc tc_done {name what} {
    echo ""
    echo "============================================================"
    echo " $name - simulation finished and STOPPED (not closed)."
    echo ""
    echo " Screenshot now. What to capture:"
    echo "   $what"
    echo ""
    echo " Transcript pane holds the \[PASS\]/\[FAIL\] lines - include it."
    echo " Useful commands:"
    echo "   wave zoom full        - fit the whole run"
    echo "   wave zoom range 0 5us - zoom to a window"
    echo "   restart -f            - rerun from time 0"
    echo "============================================================"
}
