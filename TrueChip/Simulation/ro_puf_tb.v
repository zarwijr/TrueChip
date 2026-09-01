// ============================================================
// ro_puf_tb.v - TrueChip v7.2 RO-PUF regression test
// ============================================================
// Run:
//   iverilog -g2012 -DRO_PUF_SIM -o ro_puf_tb.out \
//       Simulation/ro_puf_tb.v RTL/ro_puf.v
//   vvp ro_puf_tb.out
//
// PORTABILITY NOTE
// ----------------
// This file is plain Verilog-2001 on purpose so it compiles in Questa
// without -sv. Two SystemVerilog constructs were deliberately avoided:
//   * fork ... join_none  -> the watchdog is its own initial block;
//   * $fatal              -> replaced by $display("[FAIL] ...") + $finish.
// Failure is still detected: both run_regression.sh (Icarus) and
// questa/regression.do scan for lines beginning with [FAIL].
//
// -DRO_PUF_SIM is REQUIRED.  It switches the ring oscillators to a
// delay-annotated simulation model (see ro_puf.v).  Without it the rings
// are zero-delay combinational loops and the simulator hangs at time 0.
// The macro is simulation-only and never affects synthesis.
//
// WHY THIS FILE EXISTS
// --------------------
// Up to v7.1 ro_puf.v had a silent P0 functional defect: the same signal
// (ro_enable) both gated the oscillators and asynchronously CLEARED the
// per-ring counters.  Ending a measurement window therefore zeroed every
// counter at the exact moment its value was supposed to be frozen, so
// S_COMPARE always compared 0 against 0, every majority vote resolved to
// 0, and puf_id came out as 128'd0 on every board.
//
// Nothing in the existing flow caught this:
//   * Quartus compiled it with 0 errors (it is legal RTL);
//   * timing closed;
//   * the FPGA demo still authenticated correctly, because a constant
//     puf_id still produces a consistent diversified_key;
//   * the server still returned AUTHENTIC.
// The only thing that broke was the per-device uniqueness claim - which
// is the entire security argument of the project.
//
// TEST 1 below is the direct regression for that bug.  It fails loudly on
// the pre-v7.2 RTL and passes on the fixed RTL.
// ============================================================

`timescale 1ns/1ps

module ro_puf_tb;

    // ------------------------------------------------------------
    // Small configuration so the test runs in seconds.
    // The production instance in secure_soc_top uses
    // NUM_RO=256, WINDOW_BITS=16, ROUNDS=7.  The FSM, the counter
    // clear/enable split and the majority vote are identical; only the
    // sizes differ, which is what makes a scaled-down test valid here.
    // ------------------------------------------------------------
    localparam integer NUM_RO       = 16;
    localparam integer NUM_PAIRS    = NUM_RO/2;
    localparam integer WINDOW_BITS  = 7;
    localparam integer CNT_WIDTH    = 12;
    localparam integer ROUNDS       = 3;

    reg          clk = 1'b0;
    reg          rst_n = 1'b0;
    wire [127:0] puf_id;
    wire         puf_valid;

    integer errors = 0;
    integer guard;

    always #10 clk = ~clk;      // 50 MHz

    ro_puf #(
        .NUM_RO             (NUM_RO),
        .WINDOW_BITS        (WINDOW_BITS),
        .CNT_WIDTH          (CNT_WIDTH),
        .FREEZE_WAIT_CYCLES (4),
        .ROUNDS             (ROUNDS)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .puf_id    (puf_id),
        .puf_valid (puf_valid)
    );

    task fail(input [1023:0] msg);
        begin
            errors = errors + 1;
            $display("[FAIL] %0s   (t=%0t)", msg, $time);
        end
    endtask

    // Wait for puf_valid with a hard cycle budget.
    task wait_valid(output integer cycles);
        begin
            cycles = 0;
            while (puf_valid !== 1'b1 && cycles < 2000000) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
        end
    endtask

    integer i;
    reg [127:0] id_run1;
    reg [127:0] id_run2;
    reg [NUM_PAIRS-1:0] bits;
    integer ones;

    initial begin
        $dumpfile("ro_puf_tb.vcd");
        $dumpvars(0, ro_puf_tb);

        $display("=== TRUECHIP RO-PUF TEST (NUM_RO=%0d, ROUNDS=%0d) ===",
                 NUM_RO, ROUNDS);

        // ----------------------------------------------------------
        // Bring-up
        // ----------------------------------------------------------
        rst_n = 1'b0;
        repeat (5) @(negedge clk);

        if (puf_valid !== 1'b0)
            fail("puf_valid must be LOW while in reset");
        if (puf_id !== 128'd0)
            fail("puf_id must be 0 while in reset");

        rst_n = 1'b1;

        wait_valid(guard);
        if (puf_valid !== 1'b1) begin
            fail("puf_valid never asserted");
            $finish;
        end
        $display("[PASS] puf_valid asserted after %0d clock cycles", guard);

        id_run1 = puf_id;
        bits    = puf_id[NUM_PAIRS-1:0];

        // ----------------------------------------------------------
        // TEST 1 - THE REGRESSION FOR THE v7.1 P0 BUG
        //
        // On the broken RTL every counter was cleared before S_COMPARE
        // read it, so every comparison was 0 > 0 (false), every majority
        // vote lost, and puf_id was exactly 128'd0.
        // ----------------------------------------------------------
        if (puf_id === 128'd0) begin
            fail("puf_id is ALL ZERO - the v7.1 counter-clear bug is back");
            $display("        ro_enable must gate the rings ONLY;");
            $display("        the counters must be cleared by cnt_clr_n");
            $display("        while the rings are already stopped.");
        end else begin
            $display("[PASS] puf_id is non-zero: %032h", puf_id);
        end

        // ----------------------------------------------------------
        // TEST 2 - the response must not be degenerate
        //
        // All-zero is caught above; all-ones would mean the comparison is
        // stuck the other way.  A healthy measurement gives a mix.
        // ----------------------------------------------------------
        ones = 0;
        for (i = 0; i < NUM_PAIRS; i = i + 1)
            if (bits[i]) ones = ones + 1;

        $display("       %0d of %0d entropy bits are 1", ones, NUM_PAIRS);

        if (ones == 0)
            fail("every PUF bit is 0 - comparator or counters are stuck");
        else if (ones == NUM_PAIRS)
            fail("every PUF bit is 1 - comparator or counters are stuck");
        else
            $display("[PASS] PUF bits are a mix of 0 and 1, not a stuck pattern");

        // ----------------------------------------------------------
        // TEST 3 - unused high bits must be zero-padded, not duplicated
        //
        // NUM_PAIRS < 128 here, so puf_id[127:NUM_PAIRS] must be 0.
        // (v2 used to mirror the low bits into the high half, which
        // doubled the apparent entropy without adding any.)
        // ----------------------------------------------------------
        if (puf_id[127:NUM_PAIRS] !== {(128-NUM_PAIRS){1'b0}})
            fail("puf_id high bits must be zero-padded when NUM_RO < 256");
        else
            $display("[PASS] puf_id high bits zero-padded (no fake entropy)");

        // ----------------------------------------------------------
        // TEST 4 - stability: a second measurement on the same instance
        //          must reproduce the same ID
        //
        // The delays in the simulation model are fixed per ring, so the
        // majority vote must land on the same answer every time.  If it
        // does not, the counters are being read at an unstable moment.
        // ----------------------------------------------------------
        repeat (20) @(negedge clk);
        rst_n = 1'b0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        wait_valid(guard);
        id_run2 = puf_id;

        if (id_run2 !== id_run1) begin
            fail("PUF ID changed between two power-up measurements");
            $display("        run 1 = %032h", id_run1);
            $display("        run 2 = %032h", id_run2);
        end else begin
            $display("[PASS] PUF ID is reproducible across a power cycle");
        end

        // ----------------------------------------------------------
        // TEST 5 - puf_valid must latch until reset
        // ----------------------------------------------------------
        repeat (200) @(posedge clk);
        if (puf_valid !== 1'b1)
            fail("puf_valid must stay HIGH until the next reset");
        if (puf_id !== id_run2)
            fail("puf_id must stay stable once puf_valid is HIGH");

        if (errors == 0)
            $display("[PASS] puf_valid and puf_id hold steady after completion");

        // ----------------------------------------------------------
        // Summary
        // ----------------------------------------------------------
        $display("");
        if (errors == 0) begin
            $display("=== RO-PUF TESTS PASSED ===");
            $display("NOTE: this proves the RTL measures and holds real counter");
            $display("      values.  It does NOT characterise silicon entropy,");
            $display("      uniqueness or stability across voltage/temperature -");
            $display("      that requires measurements on real boards.");
        end else begin
            $display("=== RO-PUF TESTS FAILED: %0d error(s) ===", errors);
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
        #200_000_000;
        $display("[FAIL] GLOBAL TIMEOUT - ro_puf never finished");
        $finish;
    end

endmodule
