# ============================================================
# integration/auth_fsm.do - authentication FSM
# ============================================================
# Evidence value: HIGH. This is where the security policy lives, and it
# is an INTEGRATION test because auth_fsm coordinates three separate
# blocks at once: the AES core, the UART transmitter, and the nonce
# history that implements replay protection.
#
# Shows, in one waveform:
#   GET_ID  -> A5 01 00 10 + UID
#   CHALLENGE -> AES(key, nonce XOR uid), full handshake
#   replay of a used nonce -> STATUS_REPLAY (0x03), zero payload
#   the nonce still rejected 3 entries deep in the history window
#
# Run from Simulation/questa:   do integration/auth_fsm.do
# ============================================================

do common.do
tc_reset_sim
tc_compile

vsim -voptargs=+acc -onfinish stop work.auth_fsm_tb
tc_wave_setup

add wave -divider "CLOCK / RESET"
add wave -radix binary /auth_fsm_tb/clk
add wave -radix binary /auth_fsm_tb/rst_n

add wave -divider "COMMANDS IN"
add wave -radix binary      /auth_fsm_tb/cmd_get_id
add wave -radix binary      /auth_fsm_tb/cmd_challenge
add wave -radix hexadecimal /auth_fsm_tb/challenge_nonce

add wave -divider "FSM STATE"
add wave -radix unsigned /auth_fsm_tb/uut/state
add wave -radix binary   /auth_fsm_tb/auth_ready

add wave -divider "AES HANDSHAKE"
add wave -radix binary      /auth_fsm_tb/aes_start
add wave -radix hexadecimal /auth_fsm_tb/aes_plaintext
add wave -radix hexadecimal /auth_fsm_tb/aes_key
add wave -radix binary      /auth_fsm_tb/aes_done
add wave -radix hexadecimal /auth_fsm_tb/aes_ciphertext

add wave -divider "RESPONSE FRAME OUT"
add wave -radix binary      /auth_fsm_tb/tx_start
add wave -radix hexadecimal /auth_fsm_tb/tx_byte
add wave -radix binary      /auth_fsm_tb/tx_busy
add wave -radix hexadecimal /auth_fsm_tb/uut/tx_header
add wave -radix unsigned    /auth_fsm_tb/uut/pld_idx

add wave -divider ">>> SECURITY: replay / rate-limit / lockout <<<"
# These are unpacked Verilog arrays. Add individual elements and protect
# [index] from Tcl command substitution with braces.
add wave -divider "NONCE HISTORY"
add wave -radix hexadecimal {/auth_fsm_tb/uut/nonce_hist[0]}
add wave -radix hexadecimal {/auth_fsm_tb/uut/nonce_hist[1]}
add wave -radix hexadecimal {/auth_fsm_tb/uut/nonce_hist[2]}
add wave -radix hexadecimal {/auth_fsm_tb/uut/nonce_hist[3]}
add wave -radix hexadecimal {/auth_fsm_tb/uut/nonce_hist[4]}
add wave -radix hexadecimal {/auth_fsm_tb/uut/nonce_hist[5]}
add wave -radix hexadecimal {/auth_fsm_tb/uut/nonce_hist[6]}
add wave -radix hexadecimal {/auth_fsm_tb/uut/nonce_hist[7]}
add wave -radix binary      {/auth_fsm_tb/uut/hist_valid[0]}
add wave -radix binary      {/auth_fsm_tb/uut/hist_valid[1]}
add wave -radix binary      {/auth_fsm_tb/uut/hist_valid[2]}
add wave -radix binary      {/auth_fsm_tb/uut/hist_valid[3]}
add wave -radix binary      {/auth_fsm_tb/uut/hist_valid[4]}
add wave -radix binary      {/auth_fsm_tb/uut/hist_valid[5]}
add wave -radix binary      {/auth_fsm_tb/uut/hist_valid[6]}
add wave -radix binary      {/auth_fsm_tb/uut/hist_valid[7]}
add wave -radix unsigned    /auth_fsm_tb/uut/hist_wr_ptr
add wave -radix unsigned    /auth_fsm_tb/uut/cooldown_cnt
add wave -radix unsigned    /auth_fsm_tb/uut/fail_cnt
add wave -radix binary      /auth_fsm_tb/locked_out
add wave -radix binary      /auth_fsm_tb/led_state

run -all
wave zoom full

tc_done "auth_fsm integration test" \
  "Four \[PASS\] lines in the transcript. In the wave: the first CHALLENGE\n   drives aes_start with plaintext = nonce XOR uid; the repeat of the\n   SAME nonce produces status byte 0x03 and length 0x00 instead."
