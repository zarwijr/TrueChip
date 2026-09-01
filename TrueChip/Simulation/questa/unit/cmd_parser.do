# ============================================================
# unit/cmd_parser.do - Protocol V2 frame parser + CRC16-CCITT
# ============================================================
# Evidence value: HIGH. The frame-integrity boundary: a good frame is
# accepted, a corrupted-CRC frame is silently discarded.
#
# Run from Simulation/questa:   do unit/cmd_parser.do
# ============================================================

do common.do
tc_reset_sim
tc_compile

vsim -voptargs=+acc -onfinish stop work.cmd_parser_tb
tc_wave_setup

add wave -divider "CLOCK / RESET"
add wave -radix binary /cmd_parser_tb/clk
add wave -radix binary /cmd_parser_tb/rst_n

add wave -divider "INCOMING BYTE STREAM"
add wave -radix binary      /cmd_parser_tb/rx_valid
add wave -radix hexadecimal /cmd_parser_tb/rx_byte

add wave -divider "PARSER STATE MACHINE"
add wave -radix unsigned    /cmd_parser_tb/uut/state
add wave -radix hexadecimal /cmd_parser_tb/uut/cmd_reg
add wave -radix unsigned    /cmd_parser_tb/uut/payload_count

add wave -divider "CRC16-CCITT (running) + received high byte"
add wave -radix hexadecimal /cmd_parser_tb/uut/crc_reg
add wave -radix hexadecimal /cmd_parser_tb/uut/crc_hi_reg

add wave -divider "DECODED COMMANDS"
add wave -radix binary      /cmd_parser_tb/cmd_get_id
add wave -radix binary      /cmd_parser_tb/cmd_challenge
add wave -radix hexadecimal /cmd_parser_tb/challenge_nonce

add wave -divider "ERROR FLAGS"
add wave -radix binary /cmd_parser_tb/crc_error
add wave -radix binary /cmd_parser_tb/packet_error

run -all
wave zoom full

tc_done "Command parser unit test" \
  "GET_ID and CHALLENGE pulsing for good frames; on the bad-CRC frame\n   crc_error pulses and NEITHER command pulse fires."
