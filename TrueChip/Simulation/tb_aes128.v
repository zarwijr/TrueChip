`timescale 1ns/1ps
module tb_aes128;
    reg clk = 0, rst_n = 0, start = 0;
    reg [127:0] plaintext = 0, key = 0;
    wire [127:0] ciphertext;
    wire done;
    always #10 clk = ~clk;
    aes128 dut (.clk(clk), .rst_n(rst_n), .start(start), .plaintext(plaintext), .key(key), .ciphertext(ciphertext), .done(done));

    task check_aes(input [127:0] test_pt, input [127:0] test_key, input [127:0] expected_ct);
        begin
            @(negedge clk); plaintext=test_pt; key=test_key; start=1;
            @(negedge clk); start=0;
            wait(done);
            if (ciphertext !== expected_ct) begin $display("[FAIL] AES FAIL: expected %h got %h", expected_ct, ciphertext); $finish; end
            $display("[PASS] AES %h", ciphertext);
            @(negedge clk);
        end
    endtask

    initial begin
        #25; rst_n=1; #20;
        check_aes(128'h25832583258325832583258325832583, 128'h12341234123412341234123412341234, 128'h82fdca6456d22b89ed31a03a7ccbb6aa);
        check_aes(128'h8431e657c075229b0cb96edf48fdaa13, 128'h12341234123412341234123412341234, 128'hbe1dbd7b5fefe7b9bc0cc66030a25d61);
        check_aes(128'h00000000000000000000000000000000, 128'hffffffffffffffffffffffffffffffff, 128'ha1f6258c877d5fcd8964484538bfc92c);
        $display("=== AES TESTS PASSED ===");
        $finish;
    end
endmodule
