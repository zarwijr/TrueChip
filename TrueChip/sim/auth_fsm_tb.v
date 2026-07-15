`timescale 1ns/1ps

module auth_fsm_tb;
    reg clk = 0;
    reg rst_n = 0;
    reg cmd_get_id = 0;
    reg cmd_challenge = 0;
    reg [127:0] challenge_nonce = 0;
    reg [127:0] aes_ciphertext = 0;
    reg aes_done = 0;
    reg [127:0] chip_uid = 128'hDEAD_BEEF_CAFE_BABE_1234_5678_ABCD_EF01;
    reg [127:0] secret_key = 128'h2B7E_1516_28AE_D2A6_ABF7_1588_09CF_4F3C;
    reg tx_busy = 0;

    wire aes_start;
    wire [127:0] aes_plaintext, aes_key;
    wire tx_start;
    wire [7:0] tx_byte;
    wire [2:0] led_state;

    always #10 clk = ~clk;

    auth_fsm uut (
        .clk(clk), .rst_n(rst_n),
        .cmd_get_id(cmd_get_id), .cmd_challenge(cmd_challenge),
        .challenge_nonce(challenge_nonce),
        .aes_ciphertext(aes_ciphertext), .aes_done(aes_done),
        .chip_uid(chip_uid), .secret_key(secret_key),
        .aes_start(aes_start), .aes_plaintext(aes_plaintext), .aes_key(aes_key),
        .tx_start(tx_start), .tx_byte(tx_byte), .tx_busy(tx_busy),
        .led_state(led_state)
    );

    initial begin
        rst_n = 0; #50; rst_n = 1; #50;

        $display("--- KICH BAN 1: TEST GET_ID ---");
        @(posedge clk); cmd_get_id <= 1;
        @(posedge clk); cmd_get_id <= 0;
        
        repeat(16) begin
            @(posedge tx_start);
            tx_busy <= 1;
            #40; 
            tx_busy <= 0;
        end
        #100;

        $display("--- KICH BAN 2: TEST CHALLENGE ---");
        challenge_nonce <= 128'h112233445566778899AABBCCDDEEFF00;
        @(posedge clk); cmd_challenge <= 1;
        @(posedge clk); cmd_challenge <= 0;

        @(posedge aes_start);
        $display("FSM da kich hoat AES. Plaintext: %h", aes_plaintext);
        
        #200;
        aes_ciphertext <= 128'h99999999999999999999999999999999;
        @(posedge clk); aes_done <= 1;
        @(posedge clk); aes_done <= 0;

        repeat(16) begin
            @(posedge tx_start);
            tx_busy <= 1;
            #40; 
            tx_busy <= 0;
        end

        #100;
        $display("Hoan tat mo phong FSM!");
        $finish;
    end
endmodule