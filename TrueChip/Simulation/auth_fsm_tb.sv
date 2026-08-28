// ============================================================
// auth_fsm_tb.sv - TrueChip v7.1 auth_fsm unit test
// ============================================================
// Run:
//   iverilog -g2012 -o auth_fsm_tb.out Simulation/auth_fsm_tb.sv RTL/auth_fsm.v
//   vvp auth_fsm_tb.out
//
// v7.1 fix - RACE CONDITIONS REMOVED
// ----------------------------------
// The v7 version of this file failed with
//     "TIMEOUT waiting for tx_start, expected a5"
// even though auth_fsm itself was correct.  Two separate races caused it:
//
//   1. Stimulus was driven with a blocking assignment AT the clock edge:
//          cmd_get_id = 1; @(posedge clk); cmd_get_id = 0;
//      The DUT samples on that same edge, so whether it saw a 1 or a 0 was
//      scheduler-dependent.  Fix: drive every stimulus on @(negedge clk),
//      half a period away from the sampling edge.
//
//   2. Edge watchers were armed AFTER the edge had already occurred:
//          cmd_challenge = 0;  // <- consumes the time step
//          fork @(posedge aes_start); ...
//      aes_start had already pulsed, so the fork waited forever.
//      Fix: never wait on @(posedge <dut_signal>).  Poll the signal
//      once per clock, just after the non-blocking update region
//      (@(posedge clk); #1;), with an explicit cycle budget.
//
// Both fixes are testbench-only.  auth_fsm.v is unchanged by this file.
// ============================================================

`timescale 1ns/1ps

module auth_fsm_tb;

    // ------------------------------------------------------------
    // Clock / DUT connections
    // ------------------------------------------------------------
    localparam integer CLK_HALF     = 10;    // 20 ns period = 50 MHz
    localparam integer WAIT_BUDGET  = 200;   // max clocks for any single wait

    reg         clk = 0;
    reg         rst_n = 0;
    reg         cmd_get_id = 0;
    reg         cmd_challenge = 0;
    reg [127:0] challenge_nonce = 0;
    reg [127:0] aes_ciphertext = 0;
    reg         aes_done = 0;
    reg         tx_busy = 0;

    reg [127:0] chip_uid   = 128'hDEADBEEFCAFEBABE12345678ABCDEF01;
    reg [127:0] secret_key = 128'h2B7E151628AED2A6ABF7158809CF4F3C;

    wire         aes_start;
    wire [127:0] aes_plaintext;
    wire [127:0] aes_key;
    wire         tx_start;
    wire [7:0]   tx_byte;
    wire         auth_ready;
    wire         locked_out;
    wire [2:0]   led_state;

    integer errors = 0;
    integer i;

    always #CLK_HALF clk = ~clk;

    // Replay-focused unit test: COOLDOWN_CYCLES = 0 so that an immediate
    // reuse of the same nonce reaches the replay detector instead of being
    // short-circuited by RATE_LIMIT.  Cooldown/lockout behaviour is covered
    // by test/test_uart_challenge.py on real hardware.
    auth_fsm #(
        .COOLDOWN_CYCLES(0)
    ) uut (
        .CLOCK_50        (clk),
        .rst_n           (rst_n),
        .cmd_get_id      (cmd_get_id),
        .cmd_challenge   (cmd_challenge),
        .challenge_nonce (challenge_nonce),
        .aes_ciphertext  (aes_ciphertext),
        .aes_done        (aes_done),
        .chip_uid        (chip_uid),
        .secret_key      (secret_key),
        .aes_start       (aes_start),
        .aes_plaintext   (aes_plaintext),
        .aes_key         (aes_key),
        .tx_start        (tx_start),
        .tx_byte         (tx_byte),
        .tx_busy         (tx_busy),
        .auth_ready      (auth_ready),
        .locked_out      (locked_out),
        .led_state       (led_state)
    );

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    task fail(input [1023:0] msg);
        begin
            errors = errors + 1;
            $display("[FAIL] %0s  (t=%0t)", msg, $time);
        end
    endtask

    // Advance exactly one clock and settle into the post-NBA region.
    task step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    // Issue a one-cycle command pulse WITHOUT racing the DUT.
    // Both edges of the pulse land on negedge, so the value is already
    // stable when the DUT samples it on the following posedge.
    task pulse_get_id;
        begin
            @(negedge clk);
            cmd_get_id = 1'b1;
            @(negedge clk);
            cmd_get_id = 1'b0;
        end
    endtask

    task pulse_challenge(input [127:0] nonce);
        begin
            @(negedge clk);
            challenge_nonce = nonce;
            cmd_challenge   = 1'b1;
            @(negedge clk);
            cmd_challenge   = 1'b0;
        end
    endtask

    // Wait for tx_start by POLLING, never by @(posedge tx_start).
    // Then model a UART that is busy for 3 clocks.
    task expect_tx_byte(input [7:0] expected, input [1023:0] label);
        integer n;
        begin
            n = 0;
            while (tx_start !== 1'b1 && n < WAIT_BUDGET) begin
                step;
                n = n + 1;
            end

            if (tx_start !== 1'b1) begin
                fail({label, " : TIMEOUT waiting for tx_start"});
                $display("        expected byte = %02h", expected);
            end else if (tx_byte !== expected) begin
                fail({label, " : TX BYTE MISMATCH"});
                $display("        expected = %02h  got = %02h", expected, tx_byte);
            end

            // uart_tx raises tx_busy one clock after seeing tx_start.
            // Drive it on negedge so the DUT never samples a mid-edge value.
            @(negedge clk);
            tx_busy = 1'b1;
            repeat (3) @(negedge clk);
            tx_busy = 1'b0;
        end
    endtask

    // Poll for aes_start instead of waiting on its edge.
    task expect_aes_start(input [1023:0] label);
        integer n;
        begin
            n = 0;
            while (aes_start !== 1'b1 && n < WAIT_BUDGET) begin
                step;
                n = n + 1;
            end
            if (aes_start !== 1'b1)
                fail({label, " : TIMEOUT waiting for aes_start"});
        end
    endtask

    // Hand the DUT one AES result, again entirely on negedge.
    task drive_aes_done(input [127:0] ct);
        begin
            @(negedge clk);
            aes_ciphertext = ct;
            aes_done       = 1'b1;
            @(negedge clk);
            aes_done       = 1'b0;
        end
    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    initial begin
        $dumpfile("auth_fsm_tb.vcd");
        $dumpvars(0, auth_fsm_tb);

        // Global safety net: never hang the regression.
        fork
            begin
                #500000;
                $display("[FAIL] GLOBAL TIMEOUT - testbench did not finish");
                $fatal(1);
            end
        join_none

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        if (auth_ready !== 1'b1)
            fail("auth_ready should be HIGH in IDLE after reset");
        if (locked_out !== 1'b0)
            fail("locked_out should be LOW after reset");

        // ----------------------------------------------------------
        // 1. GET_ID -> A5 01 00 10 + 16-byte UID
        // ----------------------------------------------------------
        pulse_get_id;

        expect_tx_byte(8'hA5, "GET_ID magic");
        expect_tx_byte(8'h01, "GET_ID version");
        expect_tx_byte(8'h00, "GET_ID status");
        expect_tx_byte(8'h10, "GET_ID length");

        for (i = 0; i < 16; i = i + 1)
            expect_tx_byte(chip_uid[127 - i*8 -: 8], "GET_ID uid byte");

        if (errors == 0)
            $display("[PASS] GET_ID frame = A5 01 00 10 + 16-byte UID");

        // ----------------------------------------------------------
        // 2. Fresh CHALLENGE -> AES(secret_key, nonce XOR uid)
        // ----------------------------------------------------------
        pulse_challenge(128'h112233445566778899AABBCCDDEEFF00);

        expect_aes_start("fresh challenge");

        if (aes_plaintext !== (128'h112233445566778899AABBCCDDEEFF00 ^ chip_uid))
            fail("AES plaintext must be (nonce XOR uid)");
        if (aes_key !== secret_key)
            fail("AES key must be the diversified secret_key");

        drive_aes_done(128'h99999999999999999999999999999999);

        expect_tx_byte(8'hA5, "CHALLENGE magic");
        expect_tx_byte(8'h01, "CHALLENGE version");
        expect_tx_byte(8'h00, "CHALLENGE status");
        expect_tx_byte(8'h10, "CHALLENGE length");
        for (i = 0; i < 16; i = i + 1)
            expect_tx_byte(8'h99, "CHALLENGE payload byte");

        if (errors == 0)
            $display("[PASS] CHALLENGE frame = A5 01 00 10 + AES ciphertext");

        // ----------------------------------------------------------
        // 3. Same nonce again -> STATUS_REPLAY (0x03), zero payload
        // ----------------------------------------------------------
        pulse_challenge(128'h112233445566778899AABBCCDDEEFF00);

        expect_tx_byte(8'hA5, "REPLAY magic");
        expect_tx_byte(8'h01, "REPLAY version");
        expect_tx_byte(8'h03, "REPLAY status");
        expect_tx_byte(8'h00, "REPLAY length");

        if (locked_out !== 1'b0)
            fail("a single replay must NOT lock the chip out");

        if (errors == 0)
            $display("[PASS] Replay of a used nonce -> STATUS_REPLAY (0x03)");

        // ----------------------------------------------------------
        // 4. History window: an older nonce is still remembered
        //    (HIST_DEPTH = 8, so nonce #1 must still be rejected after
        //     several distinct nonces have gone through).
        // ----------------------------------------------------------
        for (i = 0; i < 3; i = i + 1) begin
            pulse_challenge(128'hA000_0000_0000_0000_0000_0000_0000_0000 + i);
            expect_aes_start("history-fill challenge");
            drive_aes_done(128'h11111111111111111111111111111111);
            expect_tx_byte(8'hA5, "history-fill magic");
            expect_tx_byte(8'h01, "history-fill version");
            expect_tx_byte(8'h00, "history-fill status");
            expect_tx_byte(8'h10, "history-fill length");
            repeat (16) expect_tx_byte(8'h11, "history-fill payload");
        end

        pulse_challenge(128'h112233445566778899AABBCCDDEEFF00);
        expect_tx_byte(8'hA5, "window-replay magic");
        expect_tx_byte(8'h01, "window-replay version");
        expect_tx_byte(8'h03, "window-replay status");
        expect_tx_byte(8'h00, "window-replay length");

        if (errors == 0)
            $display("[PASS] Nonce still rejected 3 entries deep in the history window");

        // ----------------------------------------------------------
        // Summary
        // ----------------------------------------------------------
        repeat (4) @(negedge clk);

        if (errors == 0)
            $display("=== AUTH_FSM UNIT TESTS PASSED ===");
        else begin
            $display("=== AUTH_FSM UNIT TESTS FAILED: %0d error(s) ===", errors);
            $fatal(1);
        end

        $finish;
    end

endmodule
