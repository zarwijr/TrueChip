`timescale 1ns/1ps

module uart_echo_tb;
    parameter BIT_PERIOD = 8680; 

    reg clk = 0;
    reg rx = 1; 
    wire tx;

    always #10 clk = ~clk;

    uart_echo uut (
        .clk(clk),
        .rx(rx),
        .tx(tx)
    );

    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            rx = 0;
            #(BIT_PERIOD);
            
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i]; 
                #(BIT_PERIOD);
            end
            
            rx = 1;
            #(BIT_PERIOD);
            
            #1000;
        end
    endtask

    initial begin
        $dumpfile("uart_echo_sim.vcd");
        $dumpvars(0, uart_echo_tb);

        $display("--- BAT DAU MO PHONG UART ECHO ---");
        #100;

        $display("May tinh gui ky tu 'A' (0x41) xuong FPGA...");
        send_uart_byte(8'h41);

        #150000; 

        $display("May tinh gui ky tu 'B' (0x42) xuong FPGA...");
        send_uart_byte(8'h42);
        
        #150000;

        $display("--- MO PHONG HOAN TAT ---");
        $finish;
    end
endmodule