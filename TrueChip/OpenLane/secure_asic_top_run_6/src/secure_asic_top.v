// ============================================================
// secure_asic_top.v - TrueChip digital ASIC hardening target (v7)
// ============================================================
// Purpose:
//   Synthesizable top for OpenLane/OpenROAD + SKY130.
//   It keeps the UART + protocol parser + command FIFO + AES-128 KDF +
//   challenge/response + replay/rate-limit/lockout path used by the FPGA
//   prototype, but it intentionally does NOT instantiate the FPGA RO-PUF.
//
// Why the RO-PUF is not in this top:
//   RTL ring oscillators are technology/placement dependent combinational
//   loops. A production SKY130 RO-PUF must be hardened as a dedicated macro
//   (LEF/GDS + timing/black-box views) and integrated hierarchically. Feeding
//   the FPGA-specific ro_puf.v directly to a normal digital RTL->GDS flow can
//   be optimized away or make STA/PnR invalid.
//
// Current layout-only substitution:
//   LAYOUT_DEVICE_SEED is a deterministic stand-in for the future PUF/OTP
//   macro output. It is NOT claimed to be unclonable or production-secure.
//   The competition report must label this GDS as the "digital AES/UART
//   security core hardening target" and the RO-PUF as a separate FPGA proof
//   of concept / future ASIC macro integration item.
// ============================================================

module secure_asic_top #(
    parameter integer CLKS_PER_BIT = 434,
    parameter [127:0] LAYOUT_DEVICE_SEED =
        128'hA55A_5AA5_1357_2468_89AB_CDEF_0123_4567
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx_i,
    output wire uart_tx_o,
    output wire key_ready_o,
    output wire locked_out_o,
    output wire fifo_overflow_o
);

    // ============================================================
    // UART
    // ============================================================
    wire        rx_valid;
    wire [7:0]  rx_byte;
    wire        tx_start;
    wire [7:0]  tx_byte;
    wire        tx_busy;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
        .CLOCK_50(clk),
        .rx(uart_rx_i),
        .rst_n(rst_n),
        .rx_valid(rx_valid),
        .rx_byte(rx_byte)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .CLOCK_50(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_byte(tx_byte),
        .tx(uart_tx_o),
        .tx_busy(tx_busy)
    );

    // ============================================================
    // Protocol parser
    // ============================================================
    wire         parser_cmd_get_id;
    wire         parser_cmd_challenge;
    wire [127:0] parser_challenge_nonce;

    cmd_parser u_cmd_parser (
        .CLOCK_50(clk),
        .rst_n(rst_n),
        .rx_valid(rx_valid),
        .rx_byte(rx_byte),
        .cmd_get_id(parser_cmd_get_id),
        .cmd_challenge(parser_cmd_challenge),
        .challenge_nonce(parser_challenge_nonce),
        // crc_error / packet_error are one-clock telemetry pulses that count
        // malformed or corrupted frames.  They are deliberately NOT brought
        // out of this hardening target: adding ports would change the macro
        // pin list and force a full re-floorplan.  Exposing them as sticky
        // "attack indicator" status bits is a documented future improvement.
        // verilator lint_off PINCONNECTEMPTY
        .crc_error(),
        .packet_error()
        // verilator lint_on PINCONNECTEMPTY
    );

    // ============================================================
    // Command FIFO (8 entries)
    // ============================================================
    localparam integer FIFO_DEPTH = 8;
    reg         fifo_type  [0:FIFO_DEPTH-1];
    reg [127:0] fifo_nonce [0:FIFO_DEPTH-1];
    reg [2:0]   fifo_wr_ptr;
    reg [2:0]   fifo_rd_ptr;
    reg [3:0]   fifo_count;
    reg         fifo_overflow;

    wire fifo_empty = (fifo_count == 4'd0);
    wire fifo_full  = (fifo_count == 4'd8);
    wire fifo_push  = parser_cmd_get_id || parser_cmd_challenge;
    wire fifo_push_type = parser_cmd_challenge;
    wire [127:0] fifo_push_nonce = parser_challenge_nonce;

    wire auth_ready;
    reg  key_ready;

    // Boot security gate: no command is visible to auth_fsm until KDF done.
    wire auth_cmd_get_id =
        key_ready && !fifo_empty && !fifo_type[fifo_rd_ptr];
    wire auth_cmd_challenge =
        key_ready && !fifo_empty && fifo_type[fifo_rd_ptr];
    wire auth_cmd_valid = auth_cmd_get_id || auth_cmd_challenge;
    wire fifo_pop = auth_cmd_valid && auth_ready;
    wire [127:0] auth_challenge_nonce = fifo_nonce[fifo_rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr   <= 3'd0;
            fifo_rd_ptr   <= 3'd0;
            fifo_count    <= 4'd0;
            fifo_overflow <= 1'b0;
        end else begin
            if (fifo_push && fifo_full && !fifo_pop)
                fifo_overflow <= 1'b1;

            if (fifo_push && (!fifo_full || fifo_pop)) begin
                fifo_type[fifo_wr_ptr]  <= fifo_push_type;
                fifo_nonce[fifo_wr_ptr] <= fifo_push_nonce;
                fifo_wr_ptr             <= fifo_wr_ptr + 1'b1;
            end

            if (fifo_pop)
                fifo_rd_ptr <= fifo_rd_ptr + 1'b1;

            case ({fifo_push && (!fifo_full || fifo_pop), fifo_pop})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: fifo_count <= fifo_count - 1'b1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

    // ============================================================
    // Demo ROM / provisioning stand-in
    // ============================================================
    wire [127:0] chip_uid;
    wire [127:0] master_key;

    chip_rom u_chip_rom (
        .chip_uid(chip_uid),
        .master_key(master_key)
    );

    // Layout stand-in for a future hardened PUF/OTP macro.
    wire [127:0] puf_id = LAYOUT_DEVICE_SEED;

    // ============================================================
    // Shared AES-128 core + boot KDF
    // diversified_key = AES(master_key, puf_id)
    // ============================================================
    wire         aes_start_fsm;
    wire [127:0] aes_plaintext_fsm;
    wire [127:0] aes_key_fsm;
    wire [127:0] aes_ciphertext;
    wire         aes_done;

    reg  [127:0] diversified_key;
    reg          kdf_start;

    wire         aes_start     = key_ready ? aes_start_fsm     : kdf_start;
    wire [127:0] aes_plaintext = key_ready ? aes_plaintext_fsm : puf_id;
    wire [127:0] aes_key       = key_ready ? aes_key_fsm       : master_key;

    aes128 u_aes128 (
        .clk(clk),
        .rst_n(rst_n),
        .start(aes_start),
        .plaintext(aes_plaintext),
        .key(aes_key),
        .ciphertext(aes_ciphertext),
        .done(aes_done)
    );

    // v7.1: renamed from KDF_START/KDF_WAIT/KDF_DONE.  `KDF_START` differed
    // from the register `kdf_start` only in case, which Quartus reports as
    // Info (10281) and which is an easy source of human error in review.
    localparam KDF_ST_START = 2'd0,
               KDF_ST_WAIT  = 2'd1,
               KDF_ST_DONE  = 2'd2;
    reg [1:0] kdf_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kdf_state       <= KDF_ST_START;
            kdf_start       <= 1'b0;
            key_ready       <= 1'b0;
            diversified_key <= 128'd0;
        end else begin
            kdf_start <= 1'b0;
            case (kdf_state)
                KDF_ST_START: begin
                    kdf_start <= 1'b1;
                    kdf_state <= KDF_ST_WAIT;
                end

                KDF_ST_WAIT: begin
                    if (aes_done) begin
                        diversified_key <= aes_ciphertext;
                        key_ready       <= 1'b1;
                        kdf_state       <= KDF_ST_DONE;
                    end
                end

                KDF_ST_DONE: begin
                    // Hold until reset.
                end

                default: kdf_state <= KDF_ST_START;
            endcase
        end
    end

    // ============================================================
    // Authentication FSM
    // ============================================================
    wire auth_locked_out;
    wire [2:0] auth_led_unused;

    auth_fsm u_auth_fsm (
        .CLOCK_50(clk),
        .rst_n(rst_n),
        .cmd_get_id(auth_cmd_get_id),
        .cmd_challenge(auth_cmd_challenge),
        .challenge_nonce(auth_challenge_nonce),
        .aes_ciphertext(aes_ciphertext),
        .aes_done(aes_done),
        .chip_uid(chip_uid),
        .secret_key(diversified_key),
        .aes_start(aes_start_fsm),
        .aes_plaintext(aes_plaintext_fsm),
        .aes_key(aes_key_fsm),
        .tx_start(tx_start),
        .tx_byte(tx_byte),
        .tx_busy(tx_busy),
        .auth_ready(auth_ready),
        .locked_out(auth_locked_out),
        .led_state(auth_led_unused)
    );

    assign key_ready_o     = key_ready;
    assign locked_out_o    = auth_locked_out;
    assign fifo_overflow_o = fifo_overflow;

endmodule
