# ============================================================
# unit/aes128.do - AES-128 core, standalone
# ============================================================
# Evidence value: HIGH. The cryptographic heart of the design. The
# testbench checks it against vectors verified independently with
# pycryptodome, including the FIPS-197 reference vector.
#
# Run from Simulation/questa:   do unit/aes128.do
# ============================================================

do common.do
tc_reset_sim
tc_compile

vsim -voptargs=+acc -onfinish stop work.tb_aes128
tc_wave_setup

add wave -divider "TEST CONTROL"
add wave -radix binary      /tb_aes128/clk
add wave -radix binary      /tb_aes128/rst_n
add wave -radix binary      /tb_aes128/start
add wave -radix binary      /tb_aes128/done

add wave -divider "AES INPUTS"
add wave -radix hexadecimal /tb_aes128/key
add wave -radix hexadecimal /tb_aes128/plaintext

add wave -divider "AES OUTPUT"
add wave -radix hexadecimal /tb_aes128/ciphertext

add wave -divider "INTERNAL ROUND ENGINE"
add wave -radix unsigned    /tb_aes128/dut/round_num
add wave -radix binary      /tb_aes128/dut/active
add wave -radix hexadecimal /tb_aes128/dut/state
add wave -radix hexadecimal /tb_aes128/dut/round_key

run -all
wave zoom full

tc_done "AES-128 unit test" \
  "3 encryptions, each ending with done=1 and the expected ciphertext.\n   round_num should sweep 0..10 on every encryption."
