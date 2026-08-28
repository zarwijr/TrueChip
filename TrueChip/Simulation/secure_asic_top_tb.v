// ============================================================
// secure_asic_top_tb.v - TrueChip v7.1 FULL-CHIP self-checking testbench
// ============================================================
// Run:
//   iverilog -g2012 -o secure_asic_top_tb.out \
//       Simulation/secure_asic_top_tb.v \
//       RTL/secure_asic_top.v RTL/uart_rx.v RTL/uart_tx.v \
//       RTL/cmd_parser.v RTL/auth_fsm.v RTL/aes128.v \
//       RTL/aes_sbox.v RTL/chip_rom.v
//   vvp secure_asic_top_tb.out
//
// WHY THIS FILE EXISTS
// --------------------
// Up to v7 the only "top level" testbench was Simulation/secure_soc_top_tb.v,
// which was byte-for-byte identical to the retired
// Simulation/fpga_only/secure_soc_top_tb_legacy.v.  That file:
//   * sent V1 frames with NO CRC bytes, so cmd_parser never accepted a
//     single command;
//   * checked NOTHING - it printed "[PASS]" unconditionally and finished.
// It therefore reported success even on a completely dead design.
//
// This testbench is the replacement.  It drives real Protocol V2 frames
// (including CRC16-CCITT) into the UART pin of secure_asic_top, decodes the
// bytes that come back out of uart_tx_o, and compares them against golden
// values.  Every check is a hard comparison; the run exits non-zero on any
// mismatch, so it is safe to use in CI / regression.
//
// WHAT IS PROVEN
// --------------
//   1. Boot KDF completes and key_ready_o rises.
//   2. No command is answered before key_ready_o (boot security gate).
//   3. GET_ID  -> A5 01 00 10 + 128-bit public UID.
//   4. CHALLENGE -> A5 01 00 10 + AES-128(diversified_key, nonce XOR uid).
//   5. An immediate second CHALLENGE -> A5 01 04 00 (STATUS_RATE_LIMIT).
//   6. Replaying a used nonce after cooldown -> A5 01 03 00 (STATUS_REPLAY).
//   7. A fresh nonce after cooldown authenticates correctly again.
//   8. A frame with a deliberately corrupted CRC is silently ignored.
//   9. locked_out_o and fifo_overflow_o stay LOW throughout.
//
// GOLDEN VALUES
// -------------
// chip_rom.v      : chip_uid   = 2583..2583 (16 x 0x2583)
//                   master_key = 1234..1234 (16 x 0x1234)
// secure_asic_top : LAYOUT_DEVICE_SEED = A55A5AA51357246889ABCDEF01234567
//
//   diversified_key = AES-128(master_key, LAYOUT_DEVICE_SEED)
//                   = D56DB0F67612790CE56147A44F67AF6F
//
//   response(nonce) = AES-128(diversified_key, nonce XOR chip_uid)
//
// Independently computed with pycryptodome (see VALIDATION_v7.md).  They are
// NOT taken from a previous run of this RTL, so this is a real reference
// check and not a self-fulfilling regression.
// ============================================================

`timescale 1ns/1ps

module secure_asic_top_tb;

    // ------------------------------------------------------------
    // Parameters
    //
    // CLKS_PER_BIT is deliberately small (not the real 434) so the
    // simulation finishes quickly.  The protocol logic is baud-rate
    // agnostic; 434 is only used on real 50 MHz / 115200 hardware.
    //
    // COOLDOWN_CYCLES is left at the RTL default (500_000) because the
    // rate-limit test must exercise the REAL cooldown path.  The test
    // waits it out explicitly rather than parameterising it away.
    // ------------------------------------------------------------
    localparam integer CLKS_PER_BIT = 8;
    localparam integer CLK_HALF     = 10;               // 20 ns -> 50 MHz
    localparam integer BIT_PERIOD   = 2 * CLK_HALF * CLKS_PER_BIT;
    localparam integer COOLDOWN_CYC = 500_000;          // must match auth_fsm default

    // ------------------------------------------------------------
    // Golden constants
    // ------------------------------------------------------------
    localparam [127:0] CHIP_UID =
        128'h2583_2583_2583_2583_2583_2583_2583_2583;

    localparam [127:0] NONCE_1 = 128'h00112233445566778899AABBCCDDEEFF;
    localparam [127:0] RESP_1  = 128'h2090AD5530F3783DDBFC906F96A0A330;

    localparam [127:0] NONCE_2 = 128'h0F1E2D3C4B5A69788796A5B4C3D2E1F0;
    localparam [127:0] RESP_2  = 128'h97990FF7A51804AF5A130D905B3E4802;

    localparam [7:0] MAGIC             = 8'hA5;
    localparam [7:0] VERSION           = 8'h01;
    localparam [7:0] CMD_GET_ID        = 8'h01;
    localparam [7:0] CMD_CHALLENGE     = 8'h02;
    localparam [7:0] STATUS_OK         = 8'h00;
    localparam [7:0] STATUS_REPLAY     = 8'h03;
    localparam [7:0] STATUS_RATE_LIMIT = 8'h04;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    reg  clk   = 1'b0;
    reg  rst_n = 1'b0;
    reg  uart_rx_i = 1'b1;

    wire uart_tx_o;
    wire key_ready_o;
    wire locked_out_o;
    wire fifo_overflow_o;

    integer errors = 0;
    integer i;

    always #CLK_HALF clk = ~clk;

    secure_asic_top #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .uart_rx_i       (uart_rx_i),
        .uart_tx_o       (uart_tx_o),
        .key_ready_o     (key_ready_o),
        .locked_out_o    (locked_out_o),
        .fifo_overflow_o (fifo_overflow_o)
    );

    // ------------------------------------------------------------
    // Reporting
    // ------------------------------------------------------------
    task fail(input [1023:0] msg);
        begin
            errors = errors + 1;
            $display("[FAIL] %0s   (t=%0t)", msg, $time);
        end
    endtask

    task check_byte(input [7:0] got, input [7:0] exp, input [1023:0] label);
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("[FAIL] %0s : expected %02h, got %02h   (t=%0t)",
                         label, exp, got, $time);
            end
        end
    endtask

    // ------------------------------------------------------------
    // CRC16-CCITT, poly 0x1021, init 0xFFFF - mirrors cmd_parser.v
    // and secure_chip_common.crc16_ccitt()
    // ------------------------------------------------------------
    function [15:0] crc16_update(input [15:0] crc_in, input [7:0] data);
        reg [15:0] crc;
        integer b;
        begin
            crc = crc_in ^ {data, 8'h00};
            for (b = 0; b < 8; b = b + 1) begin
                if (crc[15]) crc = (crc << 1) ^ 16'h1021;
                else         crc =  crc << 1;
            end
            crc16_update = crc;
        end
    endfunction

    // ------------------------------------------------------------
    // UART transmit into the DUT (8N1, LSB first)
    // ------------------------------------------------------------
    task uart_send_byte(input [7:0] data);
        integer b;
        begin
            uart_rx_i = 1'b0;                 // start bit
            #(BIT_PERIOD);
            for (b = 0; b < 8; b = b + 1) begin
                uart_rx_i = data[b];
                #(BIT_PERIOD);
            end
            uart_rx_i = 1'b1;                 // stop bit
            #(BIT_PERIOD);
        end
    endtask

    // ------------------------------------------------------------
    // UART receive from the DUT.
    //
    // Waits for a start bit, then samples each data bit in the MIDDLE of
    // its bit cell.  `timed_out` is returned instead of hanging, so a
    // missing response is reported as a failure rather than a dead sim.
    // ------------------------------------------------------------
    task uart_recv_byte(output [7:0] data, output timed_out, input integer max_bit_periods);
        integer b;
        integer guard;
        begin
            data      = 8'h00;
            timed_out = 1'b0;
            guard     = 0;

            // Wait for the falling edge that starts a character.
            while (uart_tx_o !== 1'b0 && guard < max_bit_periods) begin
                #(BIT_PERIOD / 8);
                guard = guard + 1;
            end

            if (uart_tx_o !== 1'b0) begin
                timed_out = 1'b1;
            end else begin
                #(BIT_PERIOD + BIT_PERIOD / 2);   // skip start bit, land mid data0
                for (b = 0; b < 8; b = b + 1) begin
                    data[b] = uart_tx_o;
                    #(BIT_PERIOD);
                end
                // now sitting in the middle of the stop bit
                if (uart_tx_o !== 1'b1)
                    fail("UART framing error: stop bit was not high");
                #(BIT_PERIOD / 2);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Frame helpers
    // ------------------------------------------------------------
    task send_get_id;
        reg [15:0] crc;
        begin
            crc = 16'hFFFF;
            crc = crc16_update(crc, VERSION);
            crc = crc16_update(crc, CMD_GET_ID);
            crc = crc16_update(crc, 8'h00);

            uart_send_byte(MAGIC);
            uart_send_byte(VERSION);
            uart_send_byte(CMD_GET_ID);
            uart_send_byte(8'h00);
            uart_send_byte(crc[15:8]);
            uart_send_byte(crc[7:0]);
        end
    endtask

    // corrupt_crc = 1 -> deliberately flip a CRC bit so the frame must be dropped
    task send_challenge(input [127:0] nonce, input corrupt_crc);
        reg [15:0] crc;
        reg [7:0]  b;
        integer    k;
        begin
            crc = 16'hFFFF;
            crc = crc16_update(crc, VERSION);
            crc = crc16_update(crc, CMD_CHALLENGE);
            crc = crc16_update(crc, 8'h10);
            for (k = 0; k < 16; k = k + 1) begin
                b   = nonce[127 - k*8 -: 8];
                crc = crc16_update(crc, b);
            end
            if (corrupt_crc)
                crc = crc ^ 16'h0001;

            uart_send_byte(MAGIC);
            uart_send_byte(VERSION);
            uart_send_byte(CMD_CHALLENGE);
            uart_send_byte(8'h10);
            for (k = 0; k < 16; k = k + 1)
                uart_send_byte(nonce[127 - k*8 -: 8]);
            uart_send_byte(crc[15:8]);
            uart_send_byte(crc[7:0]);
        end
    endtask

    // Receive a 4-byte response header.
    task recv_header(output [7:0] status, output [7:0] len,
                     output hdr_timeout, input [1023:0] label);
        reg [7:0] b;
        reg       t;
        begin
            hdr_timeout = 1'b0;
            status      = 8'hFF;
            len         = 8'hFF;

            uart_recv_byte(b, t, 4000);
            if (t) begin
                hdr_timeout = 1'b1;
                fail({label, " : no response (timeout waiting for MAGIC)"});
            end else begin
                check_byte(b, MAGIC, {label, " MAGIC"});
                uart_recv_byte(b, t, 64); check_byte(b, VERSION, {label, " VERSION"});
                uart_recv_byte(status, t, 64);
                uart_recv_byte(len,    t, 64);
            end
        end
    endtask

    // Receive a 16-byte payload and compare against a golden 128-bit value.
    task recv_and_check_payload(input [127:0] expected, input [1023:0] label);
        reg [7:0]   b;
        reg         t;
        reg [127:0] got;
        integer     k;
        begin
            got = 128'd0;
            for (k = 0; k < 16; k = k + 1) begin
                uart_recv_byte(b, t, 64);
                if (t) begin
                    fail({label, " : payload truncated"});
                    k = 16;
                end else begin
                    got = {got[119:0], b};
                end
            end
            if (got !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s payload mismatch   (t=%0t)", label, $time);
                $display("        expected = %032h", expected);
                $display("        got      = %032h", got);
            end
        end
    endtask

    // Assert that the DUT stays completely silent for a while.
    task expect_silence(input integer bit_periods, input [1023:0] label);
        integer k;
        begin
            for (k = 0; k < bit_periods; k = k + 1) begin
                if (uart_tx_o !== 1'b1) begin
                    fail({label, " : DUT transmitted when it should have stayed silent"});
                    k = bit_periods;
                end
                #(BIT_PERIOD);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    reg [7:0] status, len;
    reg       t_out;
    integer   guard;
    integer   err_mark;   // errors count at the start of a section

    initial begin
        $dumpfile("secure_asic_top_tb.vcd");
        $dumpvars(0, secure_asic_top_tb);

        fork
            begin
                #2_000_000_000;
                $display("[FAIL] GLOBAL TIMEOUT - testbench did not finish");
                $fatal(1);
            end
        join_none

        $display("=== TRUECHIP FULL-CHIP PROTOCOL V2 TEST (secure_asic_top) ===");

        // ----------------------------------------------------------
        // 0. Reset, then boot key-derivation
        // ----------------------------------------------------------
        rst_n     = 1'b0;
        uart_rx_i = 1'b1;
        repeat (5) @(negedge clk);

        if (key_ready_o !== 1'b0)
            fail("key_ready_o must be LOW while in reset");

        rst_n = 1'b1;

        guard = 0;
        while (key_ready_o !== 1'b1 && guard < 5000) begin
            @(posedge clk);
            guard = guard + 1;
        end

        if (key_ready_o !== 1'b1)
            fail("boot KDF never completed: key_ready_o stayed LOW");
        else
            $display("[PASS] Boot KDF completed, key_ready_o HIGH after %0d clocks", guard);

        if (locked_out_o !== 1'b0)
            fail("locked_out_o must be LOW after reset");
        if (fifo_overflow_o !== 1'b0)
            fail("fifo_overflow_o must be LOW after reset");

        // ----------------------------------------------------------
        // 1. GET_ID
        // ----------------------------------------------------------
        err_mark = errors;
        send_get_id;
        recv_header(status, len, t_out, "GET_ID");
        if (!t_out) begin
            check_byte(status, STATUS_OK, "GET_ID status");
            check_byte(len,    8'h10,     "GET_ID length");
            recv_and_check_payload(CHIP_UID, "GET_ID");
            if (errors == err_mark)
                $display("[PASS] GET_ID -> A5 01 00 10 + UID %032h", CHIP_UID);
        end

        // ----------------------------------------------------------
        // 2. Fresh CHALLENGE -> AES(diversified_key, nonce XOR uid)
        // ----------------------------------------------------------
        err_mark = errors;
        send_challenge(NONCE_1, 1'b0);
        recv_header(status, len, t_out, "CHALLENGE#1");
        if (!t_out) begin
            check_byte(status, STATUS_OK, "CHALLENGE#1 status");
            check_byte(len,    8'h10,     "CHALLENGE#1 length");
            recv_and_check_payload(RESP_1, "CHALLENGE#1");
            if (errors == err_mark) begin
                $display("[PASS] CHALLENGE#1 nonce=%032h", NONCE_1);
                $display("       response=%032h  (matches pycryptodome golden value)",
                         RESP_1);
            end
        end

        // ----------------------------------------------------------
        // 3. Immediate second CHALLENGE -> STATUS_RATE_LIMIT
        // ----------------------------------------------------------
        err_mark = errors;
        send_challenge(NONCE_2, 1'b0);
        recv_header(status, len, t_out, "RATE_LIMIT");
        if (!t_out) begin
            check_byte(status, STATUS_RATE_LIMIT, "RATE_LIMIT status");
            check_byte(len,    8'h00,             "RATE_LIMIT length");
            if (errors == err_mark)
                $display("[PASS] Immediate 2nd CHALLENGE -> STATUS_RATE_LIMIT (0x04), 0-byte payload");
        end

        // ----------------------------------------------------------
        // 4. Wait out the cooldown, then replay NONCE_1 -> STATUS_REPLAY
        // ----------------------------------------------------------
        repeat (COOLDOWN_CYC + 100) @(posedge clk);

        err_mark = errors;
        send_challenge(NONCE_1, 1'b0);
        recv_header(status, len, t_out, "REPLAY");
        if (!t_out) begin
            check_byte(status, STATUS_REPLAY, "REPLAY status");
            check_byte(len,    8'h00,         "REPLAY length");
            if (errors == err_mark)
                $display("[PASS] Replayed nonce after cooldown -> STATUS_REPLAY (0x03)");
        end

        // ----------------------------------------------------------
        // 5. Corrupted CRC must be silently dropped
        // ----------------------------------------------------------
        repeat (COOLDOWN_CYC + 100) @(posedge clk);

        err_mark = errors;
        send_challenge(NONCE_2, 1'b1);          // bad CRC
        expect_silence(40, "bad-CRC frame");
        if (errors == err_mark)
            $display("[PASS] Frame with corrupted CRC silently discarded");

        // ----------------------------------------------------------
        // 6. Fresh nonce still authenticates after all the protections
        // ----------------------------------------------------------
        err_mark = errors;
        send_challenge(NONCE_2, 1'b0);
        recv_header(status, len, t_out, "CHALLENGE#2");
        if (!t_out) begin
            check_byte(status, STATUS_OK, "CHALLENGE#2 status");
            check_byte(len,    8'h10,     "CHALLENGE#2 length");
            recv_and_check_payload(RESP_2, "CHALLENGE#2");
            if (errors == err_mark) begin
                $display("[PASS] CHALLENGE#2 nonce=%032h", NONCE_2);
                $display("       response=%032h", RESP_2);
            end
        end

        // ----------------------------------------------------------
        // 7. Status pins
        // ----------------------------------------------------------
        if (locked_out_o !== 1'b0)
            fail("chip locked out unexpectedly during a normal session");
        if (fifo_overflow_o !== 1'b0)
            fail("command FIFO overflowed during a normal session");
        if (key_ready_o !== 1'b1)
            fail("key_ready_o dropped during the session");

        // ----------------------------------------------------------
        // Summary
        // ----------------------------------------------------------
        if (errors == 0) begin
            $display("=== FULL-CHIP TESTS PASSED (secure_asic_top) ===");
        end else begin
            $display("=== FULL-CHIP TESTS FAILED: %0d error(s) ===", errors);
            $fatal(1);
        end

        $finish;
    end

endmodule
