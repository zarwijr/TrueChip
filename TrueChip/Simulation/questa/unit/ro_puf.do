# ============================================================
# unit/ro_puf.do - Ring-Oscillator PUF
# ============================================================
# Evidence value: HIGHEST. This is the regression for the v7.1 P0 bug,
# where ro_enable both gated the oscillators AND asynchronously cleared
# the counters - so every counter was wiped at the exact moment its
# value was supposed to be frozen, and puf_id came out 128'd0 on every
# board.
#
# THE MONEY SHOT for the report is the relationship between:
#     ro_enable   - now ONLY gates the oscillators
#     cnt_clr_n   - now the ONLY thing that clears the counters
#     ro_cnt[*]   - must HOLD its value when ro_enable falls
#
# Zoom into the moment ro_enable goes low at the end of a measurement
# window: the counters must stay put, not drop to zero. Pre-v7.2 they
# dropped to zero there.
#
# Run from Simulation/questa:   do unit/ro_puf.do
# ============================================================

do common.do
tc_reset_sim
tc_compile

vsim -voptargs=+acc -onfinish stop work.ro_puf_tb
tc_wave_setup

add wave -divider "CLOCK / RESET"
add wave -radix binary /ro_puf_tb/clk
add wave -radix binary /ro_puf_tb/rst_n

add wave -divider ">>> THE FIX: enable vs clear are now SEPARATE <<<"
add wave -radix binary /ro_puf_tb/dut/ro_enable
add wave -radix binary /ro_puf_tb/dut/cnt_clr_n

add wave -divider "CONTROLLER"
add wave -radix unsigned /ro_puf_tb/dut/state
add wave -radix unsigned /ro_puf_tb/dut/window_cnt
add wave -radix unsigned /ro_puf_tb/dut/freeze_cnt
add wave -radix unsigned /ro_puf_tb/dut/round_idx

add wave -divider "RING COUNTERS - must HOLD when ro_enable falls"
# Braces protect Verilog array indices from Tcl command substitution.
add wave -radix unsigned {/ro_puf_tb/dut/gen_cnt[0]/cnt_r}
add wave -radix unsigned {/ro_puf_tb/dut/gen_cnt[1]/cnt_r}
add wave -radix unsigned {/ro_puf_tb/dut/gen_cnt[2]/cnt_r}
add wave -radix unsigned {/ro_puf_tb/dut/gen_cnt[3]/cnt_r}

add wave -divider "MAJORITY VOTE"
add wave -radix unsigned /ro_puf_tb/dut/vote_cnt

add wave -divider "RESULT - must NOT be all zero"
add wave -radix binary      /ro_puf_tb/puf_valid
add wave -radix hexadecimal /ro_puf_tb/puf_id

run -all
wave zoom full

tc_done "RO-PUF unit test" \
  "puf_valid rising with a NON-ZERO puf_id.\n   Then zoom to where ro_enable falls: cnt_r must HOLD, not reset.\n   Suggested: wave zoom range 2us 4us"
