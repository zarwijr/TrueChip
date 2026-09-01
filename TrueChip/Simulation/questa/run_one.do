# ============================================================
# run_one.do - run ONE testbench with its evidence waveform, then stop
# ============================================================
# This is the simple entry point for screenshots. It dispatches to the
# matching script under unit/, integration/ or top/.
#
# Usage from Simulation/questa:
#
#     set TC_TEST ro_puf_tb
#     do run_one.do
#
# Or in one line:
#
#     do run_one.do ro_puf_tb
#
# Valid names:
#     tb_aes128            uart_tb            uart_echo_tb
#     cmd_parser_tb        ro_puf_tb          auth_fsm_tb
#     secure_soc_top_tb    secure_asic_top_tb
#
# Each selected script compiles, opens the grouped waveform, runs to
# completion, and leaves Questa open for a screenshot.
# ============================================================

# Accept the test name as an argument to `do`, or from TC_TEST.
if {[info exists 1]} {
    set TC_TEST $1
}
if {![info exists TC_TEST]} {
    echo ""
    echo "ERROR: no test named."
    echo ""
    echo "  do run_one.do ro_puf_tb"
    echo ""
    echo "  or:  set TC_TEST ro_puf_tb"
    echo "       do run_one.do"
    echo ""
    echo "  Names: tb_aes128 uart_tb uart_echo_tb cmd_parser_tb"
    echo "         ro_puf_tb auth_fsm_tb secure_soc_top_tb secure_asic_top_tb"
    return
}

# One command per test. The individual script owns compilation,
# waveform grouping, run, and the final STOP banner.
array set TC_SCRIPT {
    tb_aes128          unit/aes128.do
    uart_tb            unit/uart.do
    uart_echo_tb       unit/uart_echo.do
    cmd_parser_tb      unit/cmd_parser.do
    ro_puf_tb           unit/ro_puf.do
    auth_fsm_tb         integration/auth_fsm.do
    secure_soc_top_tb  top/secure_soc_top.do
    secure_asic_top_tb top/secure_asic_top.do
}

if {![info exists TC_SCRIPT($TC_TEST)]} {
    echo "ERROR: unknown test name: $TC_TEST"
    echo "Names: tb_aes128 uart_tb uart_echo_tb cmd_parser_tb ro_puf_tb auth_fsm_tb secure_soc_top_tb secure_asic_top_tb"
    return
}

do $TC_SCRIPT($TC_TEST)
