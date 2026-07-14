`timescale 1ns/1ps

module cmd_parser_tb;
    reg clk = 0;
    reg rst_n = 0;
    reg rx_valid = 0;
    reg [7:0] rx_byte = 0;
    
    wire cmd_get_id;
    wire cmd_challenge;
    wire [127:0] challenge_nonce;
    wire [7:0] status_byte;

    always #10 clk = ~clk;

    cmd_parser uut (
        .clk(clk), .rst_n(rst_n),
        .rx_valid(rx_valid), .rx_byte(rx_byte),
        .cmd_get_id(cmd_get_id), .cmd_challenge(cmd_challenge),
        .challenge_nonce(challenge_nonce), .status_byte(status_byte)
    );

    task send_byte(input [7:0] data);
        begin
            @(posedge clk);
            rx_valid <= 1;
            rx_byte <= data;
            @(posedge clk);
            rx_valid <= 0;
            #50;
        end
    endtask

    integer i;

    initial begin
        rst_n = 0; #50; rst_n = 1; #50;

        $display("--- Test CMD_GET_ID ---");
        send_byte(8'h01);
        #20;
        if (cmd_get_id) $display("PASS: Nhan dung lenh GET_ID");
        else $display("FAIL: Khong nhan duoc lenh GET_ID");

        #100;
        
        $display("--- Test CMD_CHALLENGE ---");
        send_byte(8'h02);
        for (i = 1; i <= 16; i = i + 1) begin
            send_byte(i * 8'h11);
        end
        
        #20;
        if (cmd_challenge) begin
            $display("PASS: Nhan dung lenh CHALLENGE");
            $display("Nonce nhan duoc: %h", challenge_nonce);
        end else begin
            $display("FAIL: Khong nhan duoc lenh CHALLENGE");
        end

        #100;
        $finish;
    end
endmodule