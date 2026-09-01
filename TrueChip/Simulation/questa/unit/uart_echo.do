# ============================================================
# unit/uart_echo.do - UART echo integration smoke test
# ============================================================
# Run from Simulation/questa:
#     do unit/uart_echo.do
# ============================================================

do common.do
tc_reset_sim
tc_compile

vsim -voptargs=+acc -onfinish stop work.uart_echo_tb
tc_wave_setup

add wave -divider "CLOCK / RESET"
add wave -radix binary /uart_echo_tb/clk
add wave -radix binary /uart_echo_tb/rst_n

add wave -divider "UART PINS"
add wave -radix binary /uart_echo_tb/rx
add wave -radix binary /uart_echo_tb/tx

add wave -divider "RX SIDE"
add wave -radix binary      /uart_echo_tb/uut/rx_valid
add wave -radix hexadecimal /uart_echo_tb/uut/rx_byte
add wave -radix binary      /uart_echo_tb/uut/u_rx/rx_d1
add wave -radix binary      /uart_echo_tb/uut/u_rx/rx_d2
add wave -radix unsigned    /uart_echo_tb/uut/u_rx/state
add wave -radix unsigned    /uart_echo_tb/uut/u_rx/bit_idx

add wave -divider "TX SIDE"
add wave -radix binary      /uart_echo_tb/uut/tx_start
add wave -radix hexadecimal /uart_echo_tb/uut/tx_byte
add wave -radix binary      /uart_echo_tb/uut/tx_busy
add wave -radix unsigned    /uart_echo_tb/uut/u_tx/state
add wave -radix unsigned    /uart_echo_tb/uut/u_tx/bit_idx

run -all
wave zoom full

tc_done "UART echo integration test" \
  "The testbench sends 0x41 and 0x42 into rx; tx must return the same bytes.\n   Include rx, tx and the PASS line in the screenshot."
