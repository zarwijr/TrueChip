# ============================================================
# top/secure_soc_top.do - FPGA top level, WITH the real RO-PUF
# ============================================================
# Evidence value: HIGHEST for the FPGA half of the project. This is the
# only test that exercises the complete chain that runs on the DE-SoC
# board:
#
#     RO-PUF measurement -> KDF -> UART protocol -> authentication
#
# The response is checked against a SEPARATE aes128 instance inside the
# testbench, so the comparison is real and not the DUT marking its own
# homework.
#
# IMPORTANT - THE PUF IS SHRUNK FOR SIMULATION
# --------------------------------------------
# The testbench uses defparam to cut the PUF from 256 rings to 8, and
# from 2^16 to 2^6 clocks per window. At production size the rings would
# generate hundreds of millions of events and the run would never finish.
#
# RTL/ is NOT modified to do this - defparam lives entirely in the
# testbench, so the Quartus build is provably unaffected. (A parameter
# pass-through was tried first and rejected: even with identical default
# values it changed the synthesised netlist.)
#
# So this waveform PROVES the chain wires up and runs, and that puf_id is
# non-zero and held. It does NOT prove the entropy, uniqueness or
# temperature stability of the production 256-ring PUF - that needs
# measurements on real boards, and the report says so explicitly.
#
# Run from Simulation/questa:   do top/secure_soc_top.do
# ============================================================

do common.do
tc_reset_sim
tc_compile

vsim -voptargs=+acc -onfinish stop work.secure_soc_top_tb
tc_wave_setup

add wave -divider "BOARD PINS"
add wave -radix binary /secure_soc_top_tb/CLOCK_50
add wave -radix binary /secure_soc_top_tb/KEY
add wave -radix binary /secure_soc_top_tb/uart_rx_drv
add wave -radix binary /secure_soc_top_tb/uart_tx
add wave -radix binary /secure_soc_top_tb/LEDR

add wave -divider ">>> RO-PUF: the real thing, shrunk to 8 rings <<<"
add wave -radix binary      /secure_soc_top_tb/uut/u_ro_puf/ro_enable
add wave -radix binary      /secure_soc_top_tb/uut/u_ro_puf/cnt_clr_n
add wave -radix unsigned    /secure_soc_top_tb/uut/u_ro_puf/state
add wave -radix unsigned    /secure_soc_top_tb/uut/u_ro_puf/round_idx
add wave -radix binary      /secure_soc_top_tb/uut/puf_valid
add wave -radix hexadecimal /secure_soc_top_tb/uut/puf_id

add wave -divider "KEY DERIVATION FROM THE PUF"
add wave -radix unsigned    /secure_soc_top_tb/uut/kdf_state
add wave -radix binary      /secure_soc_top_tb/uut/key_ready
add wave -radix hexadecimal /secure_soc_top_tb/uut/master_key
add wave -radix hexadecimal /secure_soc_top_tb/uut/diversified_key

add wave -divider "PROTOCOL"
add wave -radix binary      /secure_soc_top_tb/uut/parser_cmd_get_id
add wave -radix binary      /secure_soc_top_tb/uut/parser_cmd_challenge
add wave -radix hexadecimal /secure_soc_top_tb/uut/chip_uid
add wave -radix unsigned    /secure_soc_top_tb/uut/u_auth_fsm/state

add wave -divider "INDEPENDENT AES REFERENCE (testbench side)"
add wave -radix hexadecimal /secure_soc_top_tb/ref_plain
add wave -radix hexadecimal /secure_soc_top_tb/ref_key
add wave -radix hexadecimal /secure_soc_top_tb/ref_cipher
add wave -radix hexadecimal /secure_soc_top_tb/payload

add wave -divider "STATUS"
add wave -radix binary   /secure_soc_top_tb/uut/auth_locked_out
add wave -radix binary   /secure_soc_top_tb/uut/fifo_overflow
add wave -radix unsigned /secure_soc_top_tb/errors

run -all
wave zoom full

tc_done "secure_soc_top FPGA top-level test" \
  "Four \[PASS\] lines, ending with the chip's response equal to the\n   independent AES reference. Best single screenshot: zoom to the PUF\n   phase to show ro_enable toggling and puf_id landing non-zero:\n     wave zoom range 0 10us"
