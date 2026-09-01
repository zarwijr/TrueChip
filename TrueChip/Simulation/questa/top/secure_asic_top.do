# ============================================================
# top/secure_asic_top.do - ASIC top level, full chip
# ============================================================
# Evidence value: HIGHEST. This is the exact module that was hardened
# to GDS on SKY130A in run_5, driven through its real UART pins with
# real Protocol V2 frames. Nothing is poked hierarchically: stimulus
# goes in on uart_rx_i and results are decoded from uart_tx_o.
#
# Expected values are golden constants computed independently with
# pycryptodome, NOT read back from the DUT:
#     diversified_key = AES(master_key, LAYOUT_DEVICE_SEED)
#                     = D56DB0F67612790CE56147A44F67AF6F
#
# Covers: boot KDF, GET_ID, CHALLENGE, rate limit, replay, bad CRC
# discarded, and a fresh nonce still working afterwards.
#
# NOTE ON RUNTIME: this test waits out the real 500,000-cycle cooldown
# twice, so it simulates ~20 ms and takes a few minutes. That is
# expected - do not kill it. Watch the transcript for progress.
#
# Run from Simulation/questa:   do top/secure_asic_top.do
# ============================================================

do common.do
tc_reset_sim
tc_compile

vsim -voptargs=+acc -onfinish stop work.secure_asic_top_tb
tc_wave_setup

add wave -divider "CHIP PINS - this is all the outside world sees"
add wave -radix binary /secure_asic_top_tb/clk
add wave -radix binary /secure_asic_top_tb/rst_n
add wave -radix binary /secure_asic_top_tb/uart_rx_i
add wave -radix binary /secure_asic_top_tb/uart_tx_o
add wave -radix binary /secure_asic_top_tb/key_ready_o
add wave -radix binary /secure_asic_top_tb/locked_out_o
add wave -radix binary /secure_asic_top_tb/fifo_overflow_o

add wave -divider "BOOT KEY DERIVATION"
add wave -radix unsigned    /secure_asic_top_tb/dut/kdf_state
add wave -radix binary      /secure_asic_top_tb/dut/kdf_start
add wave -radix hexadecimal /secure_asic_top_tb/dut/diversified_key

add wave -divider "PARSED COMMANDS"
add wave -radix binary      /secure_asic_top_tb/dut/parser_cmd_get_id
add wave -radix binary      /secure_asic_top_tb/dut/parser_cmd_challenge
add wave -radix hexadecimal /secure_asic_top_tb/dut/parser_challenge_nonce
add wave -radix binary      /secure_asic_top_tb/dut/u_cmd_parser/crc_error

add wave -divider "COMMAND FIFO"
add wave -radix unsigned /secure_asic_top_tb/dut/fifo_count
add wave -radix binary   /secure_asic_top_tb/dut/fifo_push
add wave -radix binary   /secure_asic_top_tb/dut/fifo_pop

add wave -divider "AUTHENTICATION"
add wave -radix unsigned    /secure_asic_top_tb/dut/u_auth_fsm/state
add wave -radix unsigned    /secure_asic_top_tb/dut/u_auth_fsm/cooldown_cnt
add wave -radix unsigned    /secure_asic_top_tb/dut/u_auth_fsm/fail_cnt
add wave -radix hexadecimal /secure_asic_top_tb/dut/aes_plaintext
add wave -radix hexadecimal /secure_asic_top_tb/dut/aes_ciphertext

add wave -divider "TESTBENCH DECODER"
add wave -radix hexadecimal /secure_asic_top_tb/status
add wave -radix hexadecimal /secure_asic_top_tb/len
add wave -radix unsigned    /secure_asic_top_tb/errors

run -all
wave zoom full

tc_done "secure_asic_top full-chip test" \
  "Seven \[PASS\] lines. key_ready_o rising early, then bursts of UART\n   traffic. Zoom on one exchange to show the frame:\n     wave zoom range 0 200us"
