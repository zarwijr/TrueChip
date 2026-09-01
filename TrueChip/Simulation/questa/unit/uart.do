# ============================================================
# unit/uart.do - UART TX + RX loopback
# ============================================================
# Evidence value: MEDIUM. Proves the serial layer everything rides on:
# framing, bit timing, and the two-flop CDC synchroniser.
#
# Run from Simulation/questa:   do unit/uart.do
# ============================================================

do common.do
tc_reset_sim
tc_compile

vsim -voptargs=+acc -onfinish stop work.uart_tb
tc_wave_setup

add wave -divider "CLOCK / RESET"
add wave -radix binary /uart_tb/clk
add wave -radix binary /uart_tb/rst_n

add wave -divider "TRANSMIT SIDE"
add wave -radix binary      /uart_tb/tx_start
add wave -radix hexadecimal /uart_tb/tx_byte
add wave -radix binary      /uart_tb/tx_busy
add wave -radix binary      /uart_tb/tx_serial

add wave -divider "TX INTERNALS"
add wave -radix unsigned /uart_tb/u_tx/state
add wave -radix unsigned /uart_tb/u_tx/bit_idx
add wave -radix unsigned /uart_tb/u_tx/clk_cnt

add wave -divider "RECEIVE SIDE"
add wave -radix binary      /uart_tb/rx_valid
add wave -radix hexadecimal /uart_tb/rx_byte

add wave -divider "RX CDC SYNCHRONISER"
add wave -radix binary   /uart_tb/u_rx/rx_d1
add wave -radix binary   /uart_tb/u_rx/rx_d2
add wave -radix unsigned /uart_tb/u_rx/state
add wave -radix unsigned /uart_tb/u_rx/bit_idx

run -all
wave zoom full

tc_done "UART loopback unit test" \
  "One byte (0xAB) leaving on tx_serial as start + 8 data + stop, then\n   arriving back as rx_byte with rx_valid pulsing high."
