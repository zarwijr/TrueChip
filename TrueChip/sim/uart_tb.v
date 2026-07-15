`timescale 1ns/1ps

module uart_tb;
    parameter CLKS_PER_BIT = 434;
    
    reg clk = 0; 
    reg rst_n = 0;
    reg tx_start = 0; 
    reg [7:0] tx_byte = 0;
    
    wire tx_serial;
    wire tx_busy;
    wire rx_valid; 
    wire [7:0] rx_byte;

    always #10 clk = ~clk;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx(
        .clk(clk), 
        .tx_start(tx_start), 
        .tx_byte(tx_byte),
        .tx_serial(tx_serial), 
        .tx_busy(tx_busy)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx(
        .clk(clk), 
        .rst_n(rst_n),
        .rx_serial(tx_serial),
        .rx_valid(rx_valid), 
        .rx_byte(rx_byte)
    );

    initial begin
        rst_n = 1'b0; 
        tx_start = 1'b0;
        #100;
        rst_n = 1'b1;
        #100;
        
        @(posedge clk); 
        tx_byte <= 8'hAB;
        tx_start <= 1'b1; 
        @(posedge clk); 
        tx_start <= 1'b0; 
        
        @(posedge rx_valid); 
        if (rx_byte == 8'hAB) 
            $display("MO PHONG THANH CONG! Nhan chinh xac byte: 0x%h", rx_byte); 
        else                    
            $display("LOI LOGIC! Nhan sai du lieu: 0x%h", rx_byte); 
            
        #1000;
        $finish;
    end
    
    initial begin
        $dumpfile("uart_sim.vcd");
        $dumpvars(0, uart_tb);
    end
endmodule