module secure_soc_top #(
    parameter CLKS_PER_BIT = 434
)(
    input  wire        CLOCK_50,
    // KEY[0] = rst_n (active-low push button).
    // KEY[1] = active-low "clear FIFO-overflow flag" debug button.
    input  wire [1:0]  KEY,
    inout  wire [35:0] GPIO,
    output wire [9:0]  LEDR
);

    wire clk   = CLOCK_50;
    wire rst_n = KEY[0];

    // ============================================================
    // SIGNAL DECLARATIONS (Khai bao toan bo wire/reg len dau)
    // ============================================================
    wire        key_ready_w;
    reg         key_ready;
    wire        auth_locked_out;
    wire [2:0]  auth_led_state;

    // GPIO UART
    wire UART_RXD = GPIO[0];
    wire UART_TXD;

    // UART internal signals
    wire        rx_valid;
    wire [7:0]  rx_byte;
    wire        tx_start;
    wire [7:0]  tx_byte;
    wire        tx_busy;

    // Parser signals
    wire        parser_cmd_get_id;
    wire        parser_cmd_challenge;
    wire [127:0] parser_challenge_nonce;

    // Chip ROM & PUF signals
    wire [127:0] chip_uid;
    wire [127:0] master_key;
    wire [127:0] puf_id;
    wire         puf_valid;

    // AES & KDF signals
    wire        aes_start_fsm;
    wire [127:0] aes_plaintext_fsm;
    wire [127:0] aes_key_fsm;
    wire [127:0] aes_ciphertext;
    wire        aes_done;
    reg  [127:0] diversified_key;
    reg         kdf_start;

    wire        aes_start     = key_ready ? aes_start_fsm     : kdf_start;
    wire [127:0] aes_plaintext = key_ready ? aes_plaintext_fsm : puf_id;
    wire [127:0] aes_key       = key_ready ? aes_key_fsm       : master_key;

    // Command FIFO declarations
    localparam integer FIFO_DEPTH = 8;
    reg         fifo_type  [0:FIFO_DEPTH-1];
    reg [127:0] fifo_nonce [0:FIFO_DEPTH-1];
    reg [2:0]   fifo_wr_ptr;
    reg [2:0]   fifo_rd_ptr;
    reg [3:0]   fifo_count;
    reg         fifo_overflow;

    wire fifo_empty = (fifo_count == 4'd0);
    wire fifo_full  = (fifo_count == 4'd8);
    wire fifo_push = parser_cmd_get_id || parser_cmd_challenge;
    wire fifo_push_type = parser_cmd_challenge;
    wire [127:0] fifo_push_nonce = parser_challenge_nonce;
    wire auth_ready;

    // ============================================================
    // GPIO ASSIGNMENTS
    // ============================================================
    assign GPIO[0]    = 1'bz;
    assign GPIO[1]    = UART_TXD;
    assign GPIO[2]    = key_ready;       // debug: diversified_key da san sang
    assign GPIO[3]    = auth_locked_out; // debug: chip da bi khoa (lockout)
    assign GPIO[35:4] = {32{1'bz}};

    // ============================================================
    // KEY[1] SYNCHRONIZER (active-low clear overflow button)
    // ============================================================
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg clr_ovf_d1;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg clr_ovf_d2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clr_ovf_d1 <= 1'b1;
            clr_ovf_d2 <= 1'b1;
        end else begin
            clr_ovf_d1 <= KEY[1];
            clr_ovf_d2 <= clr_ovf_d1;
        end
    end

    wire clear_overflow = ~clr_ovf_d2;

    // ============================================================
    // FIFO LOGIC
    // ============================================================
    wire auth_cmd_get_id = key_ready && !fifo_empty && !fifo_type[fifo_rd_ptr];
    wire auth_cmd_challenge = key_ready && !fifo_empty && fifo_type[fifo_rd_ptr];
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
            else if (clear_overflow)
                fifo_overflow <= 1'b0;

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
    // MODULE INSTANTIATIONS
    // ============================================================
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
        .CLOCK_50 (clk),
        .rx       (UART_RXD),
        .rst_n    (rst_n),
        .rx_valid (rx_valid),
        .rx_byte  (rx_byte)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .CLOCK_50 (clk),
        .tx       (UART_TXD),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_byte  (tx_byte),
        .tx_busy  (tx_busy)
    );

    cmd_parser u_cmd_parser (
        .CLOCK_50        (clk),
        .rst_n           (rst_n),
        .rx_valid        (rx_valid),
        .rx_byte         (rx_byte),
        .cmd_get_id      (parser_cmd_get_id),
        .cmd_challenge   (parser_cmd_challenge),
        .challenge_nonce (parser_challenge_nonce),
        .crc_error       (),
        .packet_error    ()
    );

    chip_rom u_chip_rom (
        .chip_uid   (chip_uid),
        .master_key (master_key)
    );

    ro_puf u_ro_puf (
        .clk       (clk),
        .rst_n     (rst_n),
        .puf_id    (puf_id),
        .puf_valid (puf_valid)
    );

    aes128 u_aes128 (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (aes_start),
        .plaintext  (aes_plaintext),
        .key        (aes_key),
        .ciphertext (aes_ciphertext),
        .done       (aes_done)
    );

    // KDF FSM
    localparam KDF_ST_WAIT_PUF = 2'd0,
               KDF_ST_START    = 2'd1,
               KDF_ST_WAIT     = 2'd2,
               KDF_ST_DONE     = 2'd3;
    reg [1:0] kdf_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kdf_state       <= KDF_ST_WAIT_PUF;
            kdf_start       <= 1'b0;
            key_ready       <= 1'b0;
            diversified_key <= 128'd0;
        end else begin
            kdf_start <= 1'b0;
            case (kdf_state)
                KDF_ST_WAIT_PUF: if (puf_valid) kdf_state <= KDF_ST_START;
                KDF_ST_START: begin
                    kdf_start <= 1'b1;
                    kdf_state <= KDF_ST_WAIT;
                end
                KDF_ST_WAIT: if (aes_done) begin
                    diversified_key <= aes_ciphertext;
                    key_ready       <= 1'b1;
                    kdf_state       <= KDF_ST_DONE;
                end
                KDF_ST_DONE: ;
                default: kdf_state <= KDF_ST_WAIT_PUF;
            endcase
        end
    end

    // AUTH FSM
    auth_fsm u_auth_fsm (
        .CLOCK_50        (clk),
        .rst_n           (rst_n),
        .cmd_get_id      (auth_cmd_get_id),
        .cmd_challenge   (auth_cmd_challenge),
        .challenge_nonce (auth_challenge_nonce),
        .aes_ciphertext  (aes_ciphertext),
        .aes_done        (aes_done),
        .chip_uid        (chip_uid),
        .secret_key      (diversified_key),
        .aes_start       (aes_start_fsm),
        .aes_plaintext   (aes_plaintext_fsm),
        .aes_key         (aes_key_fsm),
        .tx_start        (tx_start),
        .tx_byte         (tx_byte),
        .tx_busy         (tx_busy),
        .auth_ready      (auth_ready),
        .locked_out      (auth_locked_out),
        .led_state       (auth_led_state)
    );

    // ============================================================
    // DEBUG LEDs (Tách biệt hoàn toàn, không đè chân)
    // ============================================================
    assign LEDR[2:0] = auth_led_state; // FSM internal state
    assign LEDR[3]   = rx_valid;
    assign LEDR[4]   = tx_busy;
    assign LEDR[5]   = parser_cmd_get_id;
    assign LEDR[6]   = parser_cmd_challenge;
    assign LEDR[7]   = aes_start;
    assign LEDR[8]   = aes_done;
    assign LEDR[9]   = fifo_overflow;

endmodule