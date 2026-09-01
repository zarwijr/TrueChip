# ============================================================
# regression.do - full TrueChip regression, run entirely in Questa
# ============================================================
# This is the Questa equivalent of Simulation/run_regression.sh.
#
# Use this one on Windows. run_regression.sh needs Icarus Verilog
# (iverilog), which is a separate tool - if you only have Questa, that
# script will fail with "iverilog: command not found". Nothing is wrong
# with your setup; the two scripts just target different simulators.
#
# Run from Simulation/questa:
#     vsim -c -do regression.do        (batch, no GUI - fastest)
#     do regression.do                 (from inside the GUI)
#
# It compiles everything, runs all eight testbenches, then prints a
# summary and tells you PASS or FAIL. Failures are detected two ways:
#   1. any [FAIL] line printed by a testbench, and
#   2. the testbench's own error counter where it has one.
#
# Takes a few minutes - secure_asic_top_tb waits out the real
# 500,000-cycle cooldown twice.
# ============================================================

do common.do

# ------------------------------------------------------------
# Stale-file guard - same checks as run_regression.sh
# ------------------------------------------------------------
set stale 0

if {[file exists $SIM/auth_fsm_tb.v]} {
    echo "\[FAIL\] stale file must be deleted: $SIM/auth_fsm_tb.v"
    echo "       duplicate 'auth_fsm_tb' module - breaks compilation."
    echo "       Keep auth_fsm_tb.sv (the rewritten one) instead."
    set stale 1
}

# The legacy fake-PASS testbench must not be the one in Simulation/.
if {[file exists $SIM/secure_soc_top_tb.v]} {
    set fh [open $SIM/secure_soc_top_tb.v r]
    set body [read $fh]
    close $fh
    if {[string first "independent AES" $body] < 0} {
        echo "\[FAIL\] $SIM/secure_soc_top_tb.v looks like the legacy fake-PASS testbench"
        echo "       (it prints \[PASS\] without checking anything)."
        echo "       Restore the self-checking version from the v7.2 package."
        set stale 1
    }
}

if {$stale} {
    echo ""
    echo "Stale files present - fix these before trusting any result."
    echo "See CHANGELOG_v7.1.md section 1."
    if {[info exists TC_BATCH]} { quit -code 1 }
    return -code error "stale files present"
}

# ------------------------------------------------------------
# Portability gate (needs python3 on PATH; skipped silently if absent)
#
# Icarus accepts constructs Questa rejects. This catches them with a
# readable message instead of a wall of vlog errors.
# ------------------------------------------------------------
if {![catch {exec python3 $SIM/check_tb_portability.py {*}[glob $SIM/*.v] {*}[glob $SIM/*.sv]} out]} {
    echo "--- testbench portability: OK ---"
} else {
    if {[string match "*WOULD FAIL IN QUESTA*" $out]} {
        echo $out
        echo ""
        echo "\[FAIL\] testbenches use constructs Questa rejects - fix these first."
        if {[info exists TC_BATCH]} { quit -code 1 }
        return -code error "portability check failed"
    }
    # python3 not found, or some other issue - not fatal, carry on.
}

# ------------------------------------------------------------
# Compile once
# ------------------------------------------------------------
tc_reset_sim
tc_compile

# ------------------------------------------------------------
# Test list. The second field is the hierarchical path to the
# testbench's own error counter, or "" if it has none (those report
# purely through [FAIL] lines and $fatal).
# ------------------------------------------------------------
set TESTS {
    {tb_aes128            ""}
    {uart_tb              ""}
    {uart_echo_tb         ""}
    {cmd_parser_tb        ""}
    {ro_puf_tb            /ro_puf_tb/errors}
    {auth_fsm_tb          /auth_fsm_tb/errors}
    {secure_soc_top_tb    /secure_soc_top_tb/errors}
    {secure_asic_top_tb   /secure_asic_top_tb/errors}
}

set logfile [file join $QUESTA_DIR regression.log]
if {[file exists $logfile]} { file delete $logfile }

set results {}
set npass 0
set nfail 0

foreach entry $TESTS {
    set name    [lindex $entry 0]
    set errpath [lindex $entry 1]

    echo ""
    echo "============================================================"
    echo " $name"
    echo "============================================================"

    # Capture this test's output so [FAIL] lines can be counted.
    transcript file [file join $QUESTA_DIR _tc_current.log]

    set ok 1
    if {[catch {vsim -quiet -voptargs=+acc -onfinish stop work.$name} msg]} {
        echo "\[FAIL\] $name : could not load ($msg)"
        set ok 0
    } else {
        if {[catch {run -all} msg]} {
            echo "\[FAIL\] $name : simulation error ($msg)"
            set ok 0
        }
        # Read the testbench's own counter where it has one.
        if {$ok && $errpath ne ""} {
            if {![catch {set n [examine -radix decimal $errpath]}]} {
                if {$n != 0} {
                    echo "\[FAIL\] $name : testbench error counter = $n"
                    set ok 0
                }
            }
        }
        catch {quit -sim}
    }

    transcript file ""

    # Scan the captured output for [FAIL] lines.
    set cur [file join $QUESTA_DIR _tc_current.log]
    if {[file exists $cur]} {
        set fh [open $cur r]
        set body [read $fh]
        close $fh
        foreach line [split $body "\n"] {
            if {[string first "\[FAIL\]" $line] >= 0} { set ok 0 }
        }
        # Append to the cumulative log, then remove the per-test file.
        set out [open $logfile a]
        puts $out "===== $name ====="
        puts $out $body
        close $out
        file delete $cur
    }

    if {$ok} {
        lappend results [list $name PASS]
        incr npass
    } else {
        lappend results [list $name FAIL]
        incr nfail
    }
}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo ""
echo "============================================================"
echo " REGRESSION SUMMARY"
echo "============================================================"
foreach r $results {
    echo [format "  %-8s %s" [lindex $r 1] [lindex $r 0]]
}
echo "------------------------------------------------------------"
echo " $npass passed, $nfail failed"
echo " Full output: $logfile"
echo "============================================================"

# Also write the summary to a file, so it survives even if the window
# scrolls or closes.
set sf [open [file join $QUESTA_DIR regression_summary.txt] w]
puts $sf "TrueChip regression summary"
puts $sf "project: $PROJ"
puts $sf ""
foreach r $results {
    puts $sf [format "  %-8s %s" [lindex $r 1] [lindex $r 0]]
}
puts $sf ""
puts $sf "$npass passed, $nfail failed"
close $sf

if {$nfail > 0} {
    echo ""
    echo " Open regression.log and search for \[FAIL\] to see what broke."
} else {
    echo ""
    echo " All tests passed."
}

echo ""
echo " Summary also saved to:"
echo "   $QUESTA_DIR/regression_summary.txt"
echo "   $QUESTA_DIR/regression.log        (full output)"
echo ""
echo " Questa is still open - nothing has been closed."
echo " Type  quit  when you are done reading."
echo ""
echo " Next: capture waveforms one script at a time, e.g."
echo "   do unit/ro_puf.do"
echo "============================================================"

# Only exit automatically when explicitly asked for batch mode:
#     vsim -c -do "set TC_BATCH 1; do regression.do"
if {[info exists TC_BATCH]} {
    if {$nfail > 0} { quit -code 1 } else { quit -code 0 }
}
