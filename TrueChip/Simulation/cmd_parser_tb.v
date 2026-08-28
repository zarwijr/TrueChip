`timescale 1ns/1ps
module cmd_parser_tb;
    reg clk = 0;
    reg rst_n = 0;
    reg rx_valid = 0;
    reg [7:0] rx_byte = 0;
    wire cmd_get_id;
    wire cmd_challenge;
    wire [127:0] challenge_nonce;
    wire crc_error;
    wire packet_error;

    always #10 clk = ~clk;

    cmd_parser uut (
        .CLOCK_50(clk),
        .rst_n(rst_n),
        .rx_valid(rx_valid),
        .rx_byte(rx_byte),
        .cmd_get_id(cmd_get_id),
        .cmd_challenge(cmd_challenge),
        .challenge_nonce(challenge_nonce),
        .crc_error(crc_error),
        .packet_error(packet_error)
    );

    task send_byte;
        input [7:0] data;
        begin
            @(negedge clk);
            rx_byte = data;
            rx_valid = 1'b1;
            @(negedge clk);
            rx_valid = 1'b0;
        end
    endtask

    task expect_get_id_pulse;
        begin
            send_byte(8'hA5);
            send_byte(8'h01);
            send_byte(8'h01);
            send_byte(8'h00);
            send_byte(8'hC8); // CRC16(01 01 00) = C89D
            @(negedge clk);
            rx_byte = 8'h9D;
            rx_valid = 1'b1;
            @(posedge clk); #1;
            if (!cmd_get_id)
                $fatal(1, "GET_ID not detected after valid CRC");
            @(negedge clk);
            rx_valid = 1'b0;
        end
    endtask

    integer i;
    initial begin
        #50;
        rst_n = 1'b1;
        #40;

        expect_get_id_pulse();
        $display("[PASS] GET_ID Protocol V2 + CRC");

        // CHALLENGE body = 01 02 10 00 11 22 ... EE FF
        // CRC16-CCITT(body) = 0x9174.
        send_byte(8'hA5);
        send_byte(8'h01);
        send_byte(8'h02);
        send_byte(8'h10);
        for (i = 0; i < 16; i = i + 1)
            send_byte(i * 8'h11);
        send_byte(8'h91);

        @(negedge clk);
        rx_byte = 8'h74;
        rx_valid = 1'b1;
        @(posedge clk); #1;
        if (!cmd_challenge)
            $fatal(1, "CHALLENGE not detected after valid CRC");
        if (challenge_nonce !== 128'h00112233445566778899AABBCCDDEEFF)
            $fatal(1, "Nonce mismatch: %h", challenge_nonce);
        @(negedge clk);
        rx_valid = 1'b0;
        $display("[PASS] CHALLENGE Protocol V2 nonce=%h", challenge_nonce);

        // Same request with bad CRC must not produce a command pulse.
        send_byte(8'hA5);
        send_byte(8'h01);
        send_byte(8'h01);
        send_byte(8'h00);
        send_byte(8'h00);
        @(negedge clk);
        rx_byte = 8'h00;
        rx_valid = 1'b1;
        @(posedge clk); #1;
        if (cmd_get_id || cmd_challenge)
            $fatal(1, "Bad CRC incorrectly accepted");
        if (!crc_error)
            $fatal(1, "Bad CRC did not assert crc_error");
        @(negedge clk);
        rx_valid = 1'b0;
        $display("[PASS] Bad CRC rejected");

        #100;
        $finish;
    end
endmodule
