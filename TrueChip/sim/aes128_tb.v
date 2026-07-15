`timescale 1ns/1ps

module aes128_tb;
    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [127:0] plaintext;
    reg [127:0] key;
    
    wire [127:0] ciphertext;
    wire done;

    always #10 clk = ~clk;

    aes128 uut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .plaintext(plaintext), .key(key),
        .ciphertext(ciphertext), .done(done)
    );

    initial begin
        plaintext = 128'h3243f6a8885a308d313198a2e0370734;
        key       = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        
        rst_n = 0; #50; rst_n = 1; #50;

        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        @(posedge done);
        
        $display("Plaintext  : %h", plaintext);
        $display("Key        : %h", key);
        $display("Ciphertext : %h", ciphertext);
        
        if (ciphertext == 128'h3925841d02dc09fbdce11ea41428c253)
            $display("KET QUA: PASS");
        else
            $display("KET QUA: FAIL");

        #100;
        $finish;
    end
endmodule