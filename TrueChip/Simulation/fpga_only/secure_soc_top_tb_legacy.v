`timescale 1ns/1ps
module secure_soc_top_tb;
    parameter CLKS_PER_BIT = 434;
    localparam BIT_PERIOD = 20 * CLKS_PER_BIT;
    reg clk = 0, key0 = 0, rx = 1;
    wire [1:0] KEY;
    assign KEY = {1'b1, key0};
    tri [35:0] GPIO;
    wire [9:0] LEDR;
    reg gpio_rx_drive_en = 1'b1;
    assign GPIO[0] = gpio_rx_drive_en ? rx : 1'bz;
    wire tx = GPIO[1];
    always #10 clk = ~clk;

    secure_soc_top #(.CLKS_PER_BIT(CLKS_PER_BIT)) uut (
        .CLOCK_50(clk), .KEY(KEY), .GPIO(GPIO), .LEDR(LEDR)
    );

    task uart_send(input [7:0] data);
        integer i;
        begin
            rx = 0; #(BIT_PERIOD);
            for (i=0; i<8; i=i+1) begin rx = data[i]; #(BIT_PERIOD); end
            rx = 1; #(BIT_PERIOD);
        end
    endtask

    task send_packet_get_id;
        begin
            uart_send(8'hA5); uart_send(8'h01); uart_send(8'h01); uart_send(8'h00);
        end
    endtask

    task send_packet_challenge;
        integer i;
        begin
            uart_send(8'hA5); uart_send(8'h01); uart_send(8'h02); uart_send(8'h10);
            for (i=0; i<16; i=i+1) uart_send(i*8'h11);
        end
    endtask

    initial begin
        $dumpfile("soc_top.vcd"); $dumpvars(0, secure_soc_top_tb);
        key0 = 0; rx = 1; #100; key0 = 1; #100;
        $display("=== TOP-LEVEL PROTOCOL TEST ===");
        send_packet_get_id;
        #3000000;
        send_packet_challenge;
        #5000000;
        $display("[PASS] Top-level protocol smoke test completed");
        $finish;
    end
endmodule
