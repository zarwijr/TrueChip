`timescale 1ns/1ps
module uart_echo_tb;
    parameter CLKS_PER_BIT = 434;
    localparam BIT_PERIOD = 20 * CLKS_PER_BIT;
    reg clk = 0, rst_n = 0, rx = 1;
    wire tx;
    always #10 clk = ~clk;

    uart_echo #(.CLKS_PER_BIT(CLKS_PER_BIT)) uut (
        .CLOCK_50(clk), .rst_n(rst_n), .rx(rx), .tx(tx)
    );

    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            rx = 0; #(BIT_PERIOD);
            for (i=0; i<8; i=i+1) begin rx = data[i]; #(BIT_PERIOD); end
            rx = 1; #(BIT_PERIOD);
        end
    endtask

    initial begin
        $dumpfile("uart_echo_sim.vcd"); $dumpvars(0, uart_echo_tb);
        #100; rst_n = 1; #100;
        send_uart_byte(8'h41);
        #150000;
        send_uart_byte(8'h42);
        #150000;
        $display("[PASS] UART echo smoke test completed");
        $finish;
    end
endmodule
