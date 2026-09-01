// ============================================================
// secure_soc_top_tb.v - TrueChip FPGA top-level testbench
// ============================================================
// This is the FPGA top: secure_soc_top = the ASIC core PLUS the real
// RO-PUF.  It is the only testbench that exercises the complete chain
//
//     RO-PUF measurement -> KDF -> UART protocol -> authentication
//
// which is exactly what runs on the DE-SoC board.
//
// Run (Questa):   do Simulation/questa/top/secure_soc_top.do
// Run (Icarus):
//   iverilog -g2012 -DRO_PUF_SIM -o soc.out \
//       Simulation/secure_soc_top_tb.v RTL/*.v
//   vvp soc.out
//
// -DRO_PUF_SIM is REQUIRED (delay-annotated ring oscillators).
//
// ------------------------------------------------------------
// WHY defparam, AND WHY NOT A PARAMETER PASS-THROUGH
// ------------------------------------------------------------
// At its production size the PUF is 256 ring oscillators free-running for
// 2^16 x 7 clock cycles.  That is hundreds of millions of simulation
// events - not practical to run, let alone to capture in a waveform.
//
// The obvious fix is to add PUF_* parameters to secure_soc_top and pass
// them down.  That was tried and REJECTED: even with default values
// identical to ro_puf.v's own defaults, Yosys produced a different netlist
// (58,927 vs 45,961 cells), most likely because re-deriving the module
// changes how the tool treats the ring oscillators' combinational loops.
// A simulation convenience must never risk changing the synthesised
// hardware, so the RTL was left untouched.
//
// defparam does the same job entirely inside the testbench.  Nothing in
// RTL/ changes, so the Quartus build is provably unaffected.
//
// WHAT THE SHRUNK PUF DOES AND DOES NOT PROVE
// -------------------------------------------
// PROVES : the RO-PUF -> KDF -> UART -> auth chain wires up and runs;
//          puf_valid rises; a non-zero puf_id is produced and held;
//          the derived key is then used for a real challenge.
// DOES NOT PROVE : entropy, uniqueness or stability of the production
//          256-ring PUF.  That needs measurements on real silicon.
//
// Because the key depends on the simulated PUF, this testbench does NOT
// hard-code an expected ciphertext.  It derives the answer the same way
// the server would - by reading the chip's own diversified key - and then
// checks the chip's response against an independent AES computation.
// ============================================================

`timescale 1ns/1ps

module secure_soc_top_tb;

    localparam integer CLKS_PER_BIT = 8;
    localparam integer CLK_HALF     = 10;                 // 20 ns -> 50 MHz
    localparam integer BIT_PERIOD   = 2 * CLK_HALF * CLKS_PER_BIT;

    localparam [7:0] MAGIC         = 8'hA5;
    localparam [7:0] VERSION       = 8'h01;
    localparam [7:0] CMD_GET_ID    = 8'h01;
    localparam [7:0] CMD_CHALLENGE = 8'h02;
    localparam [7:0] STATUS_OK     = 8'h00;

    reg         CLOCK_50 = 1'b0;
    reg  [1:0]  KEY      = 2'b11;      // KEY[0]=rst_n, KEY[1]=clear overflow
    wire [35:0] GPIO;
    wire [9:0]  LEDR;

    // GPIO[0] is the UART RX pin (an input to the DUT).
    reg  uart_rx_drv = 1'b1;
    assign GPIO[0] = uart_rx_drv;

    wire uart_tx = GPIO[1];            // GPIO[1] is the UART TX pin

    integer errors = 0;
    integer i;

    always #CLK_HALF CLOCK_50 = ~CLOCK_50;

    secure_soc_top #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) uut (
        .CLOCK_50 (CLOCK_50),
        .KEY      (KEY),
        .GPIO     (GPIO),
        .LEDR     (LEDR)
    );

    // Shrink the PUF for simulation only - see the header note.
    // 8 rings -> 4 entropy bits, 3 rounds of majority voting.
    defparam uut.u_ro_puf.NUM_RO      = 8;
    defparam uut.u_ro_puf.WINDOW_BITS = 6;
    defparam uut.u_ro_puf.CNT_WIDTH   = 10;
    defparam uut.u_ro_puf.ROUNDS      = 3;

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
    // CRC16-CCITT, poly 0x1021, init 0xFFFF
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
    // UART
    // ------------------------------------------------------------
    task uart_send_byte(input [7:0] data);
        integer b;
        begin
            uart_rx_drv = 1'b0;                       // start bit
            #(BIT_PERIOD);
            for (b = 0; b < 8; b = b + 1) begin
                uart_rx_drv = data[b];
                #(BIT_PERIOD);
            end
            uart_rx_drv = 1'b1;                       // stop bit
            #(BIT_PERIOD);
        end
    endtask

    task uart_recv_byte(output [7:0] data, output timed_out,
                        input integer max_bit_periods);
        integer b, guard;
        begin
            data      = 8'h00;
            timed_out = 1'b0;
            guard     = 0;
            while (uart_tx !== 1'b0 && guard < max_bit_periods) begin
                #(BIT_PERIOD / 8);
                guard = guard + 1;
            end
            if (uart_tx !== 1'b0) begin
                timed_out = 1'b1;
            end else begin
                #(BIT_PERIOD + BIT_PERIOD / 2);       // mid data0
                for (b = 0; b < 8; b = b + 1) begin
                    data[b] = uart_tx;
                    #(BIT_PERIOD);
                end
                if (uart_tx !== 1'b1)
                    fail("UART framing error: stop bit not high");
                #(BIT_PERIOD / 2);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Frames
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

    task send_challenge(input [127:0] nonce);
        reg [15:0] crc;
        integer k;
        begin
            crc = 16'hFFFF;
            crc = crc16_update(crc, VERSION);
            crc = crc16_update(crc, CMD_CHALLENGE);
            crc = crc16_update(crc, 8'h10);
            for (k = 0; k < 16; k = k + 1)
                crc = crc16_update(crc, nonce[127 - k*8 -: 8]);
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

    task recv_frame(output [7:0] status, output [7:0] len,
                    output [127:0] payload, output t_out,
                    input [1023:0] label);
        reg [7:0] b;
        reg       t;
        integer   k;
        begin
            t_out   = 1'b0;
            status  = 8'hFF;
            len     = 8'hFF;
            payload = 128'd0;

            uart_recv_byte(b, t, 6000);
            if (t) begin
                t_out = 1'b1;
                fail({label, " : no response (timeout waiting for MAGIC)"});
            end else begin
                check_byte(b, MAGIC, {label, " MAGIC"});
                uart_recv_byte(b, t, 64);
                check_byte(b, VERSION, {label, " VERSION"});
                uart_recv_byte(status, t, 64);
                uart_recv_byte(len,    t, 64);
                if (len == 8'h10) begin
                    for (k = 0; k < 16; k = k + 1) begin
                        uart_recv_byte(b, t, 64);
                        payload = {payload[119:0], b};
                    end
                end
            end
        end
    endtask

    // ------------------------------------------------------------
    // Independent AES reference model (testbench-side only)
    //
    // Declared HERE, above the test sequence that uses it. Verilog-2001
    // requires declaration before use; Icarus tolerates a forward
    // reference but Questa rejects it (vlog-2730 'Undefined variable').
    // ------------------------------------------------------------
    reg          ref_start = 1'b0;
    reg  [127:0] ref_plain = 128'd0;
    reg  [127:0] ref_key   = 128'd0;
    wire [127:0] ref_cipher;
    wire         ref_done;
    reg          ref_valid = 1'b0;

    aes128 u_ref_aes (
        .clk        (CLOCK_50),
        .rst_n      (KEY[0]),
        .start      (ref_start),
        .plaintext  (ref_plain),
        .key        (ref_key),
        .ciphertext (ref_cipher),
        .done       (ref_done)
    );

    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0])        ref_valid <= 1'b0;
        else if (ref_start) ref_valid <= 1'b0;
        else if (ref_done)  ref_valid <= 1'b1;
    end

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    reg [7:0]   status, len;
    reg [127:0] payload;
    reg         t_out;
    reg [127:0] uid_from_chip;
    reg [127:0] nonce;
    integer     guard;

    initial begin
        $dumpfile("secure_soc_top_tb.vcd");
        $dumpvars(0, secure_soc_top_tb);

        $display("=== TRUECHIP FPGA TOP-LEVEL TEST (secure_soc_top) ===");
        $display("    RO-PUF shrunk for simulation: 8 rings, 3 rounds");

        // ----------------------------------------------------------
        // 0. Reset via KEY[0], then wait for the PUF and the KDF
        // ----------------------------------------------------------
        KEY[0]      = 1'b0;
        uart_rx_drv = 1'b1;
        repeat (5) @(negedge CLOCK_50);

        if (uut.puf_valid !== 1'b0)
            fail("puf_valid must be LOW while in reset");

        KEY[0] = 1'b1;

        guard = 0;
        while (uut.puf_valid !== 1'b1 && guard < 200000) begin
            @(posedge CLOCK_50);
            guard = guard + 1;
        end
        if (uut.puf_valid !== 1'b1) begin
            fail("RO-PUF never completed: puf_valid stayed LOW");
            $finish;
        end
        $display("[PASS] RO-PUF measurement done after %0d clocks", guard);
        $display("       puf_id = %032h", uut.puf_id);

        // The v7.1 P0 bug made this exactly zero on every board.
        if (uut.puf_id === 128'd0)
            fail("puf_id is ALL ZERO - the counter-clear bug is back");

        guard = 0;
        while (uut.key_ready !== 1'b1 && guard < 200000) begin
            @(posedge CLOCK_50);
            guard = guard + 1;
        end
        if (uut.key_ready !== 1'b1) begin
            fail("KDF never completed: key_ready stayed LOW");
            $finish;
        end
        $display("[PASS] KDF done, key_ready HIGH");
        $display("       diversified_key = %032h", uut.diversified_key);

        // ----------------------------------------------------------
        // 1. GET_ID
        // ----------------------------------------------------------
        send_get_id;
        recv_frame(status, len, payload, t_out, "GET_ID");
        if (!t_out) begin
            check_byte(status, STATUS_OK, "GET_ID status");
            check_byte(len,    8'h10,     "GET_ID length");
            uid_from_chip = payload;
            if (payload !== uut.chip_uid)
                fail("GET_ID returned a UID that is not chip_uid");
            else
                $display("[PASS] GET_ID -> UID %032h", payload);
        end

        // ----------------------------------------------------------
        // 2. CHALLENGE, checked against an independent AES computation
        //
        //    The reference model below is the SAME check the server
        //    performs: AES(diversified_key, nonce XOR uid).  It is
        //    computed by a separate aes128 instance, not by reading the
        //    DUT's own result - so this is a real comparison.
        // ----------------------------------------------------------
        nonce = 128'h00112233445566778899AABBCCDDEEFF;

        ref_key   = uut.diversified_key;
        ref_plain = nonce ^ uid_from_chip;
        @(negedge CLOCK_50);
        ref_start = 1'b1;
        @(negedge CLOCK_50);
        ref_start = 1'b0;

        send_challenge(nonce);
        recv_frame(status, len, payload, t_out, "CHALLENGE");

        guard = 0;
        while (!ref_valid && guard < 1000) begin
            @(posedge CLOCK_50);
            guard = guard + 1;
        end

        if (!t_out) begin
            check_byte(status, STATUS_OK, "CHALLENGE status");
            check_byte(len,    8'h10,     "CHALLENGE length");
            if (!ref_valid) begin
                fail("reference AES model did not finish");
            end else if (payload !== ref_cipher) begin
                errors = errors + 1;
                $display("[FAIL] CHALLENGE response mismatch");
                $display("        chip     = %032h", payload);
                $display("        expected = %032h", ref_cipher);
            end else begin
                $display("[PASS] CHALLENGE nonce=%032h", nonce);
                $display("       response=%032h  (matches independent AES)",
                         ref_cipher);
            end
        end

        // ----------------------------------------------------------
        // 3. Status LEDs / flags
        // ----------------------------------------------------------
        if (uut.fifo_overflow !== 1'b0)
            fail("command FIFO overflowed during a normal session");
        if (uut.auth_locked_out !== 1'b0)
            fail("chip locked out unexpectedly");

        // ----------------------------------------------------------
        // Summary
        // ----------------------------------------------------------
        $display("");
        if (errors == 0) begin
            $display("=== FPGA TOP-LEVEL TESTS PASSED (secure_soc_top) ===");
            $display("NOTE: the PUF was shrunk to 8 rings for simulation.");
            $display("      This proves the chain works, NOT the entropy or");
            $display("      stability of the production 256-ring PUF.");
        end else begin
            $display("=== FPGA TOP-LEVEL TESTS FAILED: %0d error(s) ===", errors);
            $finish;
        end

        $finish;
    end

    // ------------------------------------------------------------
    // Global timeout watchdog.
    //
    // Written as its own initial block rather than fork/join_none:
    // fork...join_none is SystemVerilog, and Questa rejects it when a
    // .v file is compiled in plain Verilog mode. A separate initial
    // block is Verilog-2001 and behaves identically - it starts at
    // time 0 and is killed by $finish like everything else.
    // ------------------------------------------------------------
    initial begin
        #50_000_000;    // 50 ms - the run itself finishes near 120 us
        $display("[FAIL] GLOBAL TIMEOUT - testbench did not finish");
        $finish;
    end

endmodule
