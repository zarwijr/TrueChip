`timescale 1ns/1ps
module uart_tb;
    parameter CLKS_PER_BIT = 434;
    reg clk=0, rst_n=0, tx_start=0;
    reg [7:0] tx_byte=0;
    wire tx_serial, tx_busy, rx_valid;
    wire [7:0] rx_byte;
    always #10 clk=~clk;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx(.CLOCK_50(clk),.rst_n(rst_n),.tx_start(tx_start),.tx_byte(tx_byte),.tx(tx_serial),.tx_busy(tx_busy));
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx(.CLOCK_50(clk),.rst_n(rst_n),.rx(tx_serial),.rx_valid(rx_valid),.rx_byte(rx_byte));
    initial begin
        $dumpfile("uart_sim.vcd"); $dumpvars(0, uart_tb);
        #100; rst_n=1; #100;
        @(negedge clk); tx_byte=8'hAB; tx_start=1;
        @(negedge clk); tx_start=0;
        @(posedge rx_valid);
        if (rx_byte !== 8'hAB) begin $display("[FAIL] UART RX mismatch: %h", rx_byte); $finish; end
        $display("[PASS] UART loopback byte=%h", rx_byte);
        #1000; $finish;
    end
endmodule
