module secure_soc_top #(
    parameter CLKS_PER_BIT = 434
)(
    input  wire        CLOCK_50,
    input  wire        UART_RXD, 
    output wire        UART_TXD,
    output wire [9:0]  LEDR
);

    wire clk = CLOCK_50;
    wire rst_n = 1'b1;

    wire         rx_valid;
    wire [7:0]   rx_byte;
    wire         tx_start;
    wire [7:0]   tx_byte;
    wire         tx_busy;

    wire         cmd_get_id;
    wire         cmd_challenge;
    wire [127:0] challenge_nonce;
    
    wire [127:0] chip_uid;
    wire [127:0] secret_key;
    
    wire         aes_start;
    wire [127:0] aes_plaintext;
    wire [127:0] aes_key;
    wire [127:0] aes_ciphertext;
    wire         aes_done;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
        .CLOCK_50   (clk),
        .UART_RXD   (UART_RXD),   
        .rst_n      (rst_n),
        .rx_valid   (rx_valid),
        .rx_byte    (rx_byte)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .CLOCK_50   (clk),
        .rst_n      (rst_n),      
        .tx_start   (tx_start),
        .tx_byte    (tx_byte),
        .UART_TXD   (UART_TXD),   
        .tx_busy    (tx_busy)
    );

    cmd_parser u_cmd_parser (
        .CLOCK_50        (clk),
        .rst_n           (rst_n),
        .rx_valid        (rx_valid),
        .rx_byte         (rx_byte),
        .cmd_get_id      (cmd_get_id),
        .cmd_challenge   (cmd_challenge),
        .challenge_nonce (challenge_nonce),
        .status_byte     () 
    );

    chip_rom u_chip_rom (
        .chip_uid   (chip_uid),
        .secret_key (secret_key)
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

    auth_fsm u_auth_fsm (
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
        .led_state       (LEDR[2:0])
    );

    assign LEDR[3] = rx_valid;
    assign LEDR[4] = tx_busy;
    assign LEDR[5] = cmd_get_id;
    assign LEDR[6] = cmd_challenge;
    assign LEDR[7] = aes_start;
    assign LEDR[8] = aes_done;
    assign LEDR[9] = 1'b1;

endmodule