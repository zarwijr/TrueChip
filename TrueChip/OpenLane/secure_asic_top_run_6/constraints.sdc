# ============================================================
# TrueChip v7.1 - SKY130 physical-design constraints
# Target: secure_asic_top, sky130A / sky130_fd_sc_hd, 50 MHz
# ============================================================
#
# v7.1 CHANGES vs v7
# ------------------
# The v7 file constrained the clock and cut two asynchronous inputs, but it
# declared NO input/output delay, NO clock uncertainty and NO drive/load.
# Because this file is used as both PNR_SDC_FILE and SIGNOFF_SDC_FILE it
# fully replaces OpenLane's base.sdc, so every I/O path in run_2 was
# effectively unconstrained and the reported slack only covered
# register-to-register paths.  That makes the timing evidence weaker than it
# looks.  The budgets below are explicit and conservative so the numbers in
# the report mean something.
# ============================================================

# ------------------------------------------------------------
# Primary clock: 50 MHz
# ------------------------------------------------------------
set clk_period 20.000
create_clock -name clk -period $clk_period [get_ports clk]

# ------------------------------------------------------------
# Clock uncertainty and transition
#
# No PLL is used, so this budgets post-CTS skew plus jitter margin.
# Setup uses a larger uncertainty than hold, which is the usual split.
# ------------------------------------------------------------
set_clock_uncertainty -setup 0.250 [get_clocks clk]
set_clock_uncertainty -hold  0.100 [get_clocks clk]
set_clock_transition   0.150       [get_clocks clk]

set_propagated_clock [get_clocks clk]

# ------------------------------------------------------------
# Asynchronous inputs - genuinely not timed
# ------------------------------------------------------------

# rst_n is an asynchronous external reset.  Its assertion edge must not be
# timed as synchronous data.  Recovery/removal on the de-assertion edge stays
# a library/physical concern and should be reviewed in the final STA reports.
set_false_path -from [get_ports rst_n]

# uart_rx_i is asynchronous to clk and is intentionally captured through the
# two-flop synchronizer u_uart_rx.rx_d1 -> u_uart_rx.rx_d2 (see uart_rx.v).
# Cut ONLY the path from the external pin; every internal path after the
# synchronizer stays fully timed by clk.
set_false_path -from [get_ports uart_rx_i]

# ------------------------------------------------------------
# Input / output delay budget
#
# 20% of the period each way is the usual starting budget for a macro whose
# neighbour timing is not yet known.  If this core is later wrapped in a
# larger SoC, replace these with real numbers from the parent block.
# ------------------------------------------------------------
set input_budget  [expr {$clk_period * 0.20}]
set output_budget [expr {$clk_period * 0.20}]

# Every input except the clock and the two false-pathed async pins.
set data_inputs [remove_from_collection \
                    [all_inputs] \
                    [get_ports {clk rst_n uart_rx_i}]]

if {[sizeof_collection $data_inputs] > 0} {
    set_input_delay -clock clk -max $input_budget $data_inputs
    set_input_delay -clock clk -min 0.0           $data_inputs
}

# uart_tx_o, key_ready_o, locked_out_o and fifo_overflow_o are slow
# protocol/status signals rather than source-synchronous outputs.  v7 left
# them completely unconstrained, which means the tool never had to buffer or
# size their launch paths at all.  Give them a real budget so the output
# paths are optimised and actually appear in the STA report.
set_output_delay -clock clk -max $output_budget [all_outputs]
set_output_delay -clock clk -min 0.0            [all_outputs]

# ------------------------------------------------------------
# Drive strength and external load
#
# Without these the tool assumes an ideal (zero-resistance) driver on inputs
# and a zero-capacitance receiver on outputs, which flatters the numbers.
# sky130_fd_sc_hd__inv_2 is the conventional reference driver; 10 fF is a
# reasonable pad/neighbour load for a status pin at this stage.
# ------------------------------------------------------------
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y \
    [remove_from_collection [all_inputs] [get_ports clk]]

set_load 0.010 [all_outputs]

# ------------------------------------------------------------
# Design rule limits
#
# Matches MAX_FANOUT_CONSTRAINT = 10 already used by the flow, and keeps
# transition times inside what the sky130_fd_sc_hd characterisation covers.
# ------------------------------------------------------------
set_max_fanout     10  [current_design]
set_max_transition 1.5 [current_design]

# ============================================================
# v7.2 NOTE - THE 6 "UNCONSTRAINED ENDPOINTS" ARE EXPECTED
#
# check_setup on run_4 reported:
#     Warning: There are 6 unconstrained endpoints.
#       _40536_/D _40537_/D _40538_/D _40539_/D _40579_/D _40580_/D
#
# These are NOT a constraint mistake.  Netlist analysis of the synthesised
# design (yosys, see VALIDATION_v7.2.md) shows exactly 12 registers whose
# D-input cone never reaches another register:
#     * 1  flop driven only by the uart_rx_i port - that is u_uart_rx.rx_d1,
#          the first stage of the CDC synchroniser, which the
#          set_false_path above cuts ON PURPOSE;
#     * 11 flops whose D is a hard constant (the "<= 1'b1" status flags:
#          key_ready, kdf_start, aes_start, tx_start, hist_valid[k],
#          going_to_lockout, fifo_overflow, ...).
# After technology mapping most of the constant-D flops acquire a feedback
# mux for their enable, which gives them a real path; the handful that do
# not are the 6 that STA reports.
#
# An endpoint with no launching register has no setup check to perform, so
# there is nothing to constrain.  Do NOT "fix" this by deleting the
# uart_rx_i false path - that would time an asynchronous input as if it
# were synchronous data, which is worse than the warning.
#
# What to do instead: state the count in the report and note that it is
# stable. If the number ever moves, something structural changed.
# ============================================================

# ============================================================
# v7.2 NOTE - MAX FANOUT AND THE CLOCK TREE
#
# set_max_fanout below is a DATA-path rule.  CTS does not size the clock
# tree from it: it uses CTS_MAX_CAP and CTS_SINK_CLUSTERING_SIZE (25 sinks
# per leaf buffer by default), so clkbuf_*_clk/X pins legitimately show
# fanouts of 22-44 and appear as "violations" in report_check_types.
#
# In run_4, 125 of the 2151 fanout violations were clock buffers - those
# are expected.  The other 2026 were on data nets and were real: they came
# from 22826 antenna diodes added AFTER the resizer had already met the
# fanout rule, roughly doubling every net's pin count.
#
# check_signoff.py splits the two categories automatically.  Judge a run by
# the DATA count, not the total.  If you want the report to read literally
# zero, set CTS_SINK_CLUSTERING_SIZE to 10 in config.json and accept a
# larger clock tree.
# ============================================================

# ============================================================
# NOTE FOR THE COMPETITION REPORT
#
# reports/metrics.csv carries a single `wns` / `tns` column taken from
# logs/synthesis/2-sta.log - the PRE-PLACEMENT estimate that uses wireload
# models.  In run_2 that column read wns = -27.02 / tns = -86022, which is
# NOT the signoff result.  The real post-route numbers live in
# logs/signoff/26-rcx_mcsta.min.log, 28-rcx_mcsta.max.log,
# 30-rcx_mcsta.nom.log and 31-rcx_sta.log - all reported
# "wns 0.00 / tns 0.00" with positive worst slack (+1.08 to +10.92 ns).
# Quote the signoff logs in the report, not the metrics.csv column.
# ============================================================
