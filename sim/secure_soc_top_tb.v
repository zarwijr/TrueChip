`timescale 1ns/1ps

module secure_soc_top_tb;
    parameter CLKS_PER_BIT = 4;
    
    reg clk = 0;
    reg rst_n = 0;
    reg rx = 1;
    
    wire tx;
    wire [2:0] led_state;

    always #10 clk = ~clk;

    secure_soc_top #(.CLKS_PER_BIT(CLKS_PER_BIT)) uut (
        .clk(clk), .rst_n(rst_n), .rx(rx),
        .tx(tx), .led_state(led_state)
    );

    task uart_send_pc(input [7:0] data);
        integer i;
        begin
            rx = 0; #(20 * CLKS_PER_BIT);
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i];
                #(20 * CLKS_PER_BIT);
            end
            rx = 1; #(20 * CLKS_PER_BIT);
            #100;
        end
    endtask

    initial begin
        $dumpfile("soc_top.vcd");
        $dumpvars(0, secure_soc_top_tb);

        rst_n = 0; rx = 1; #100; rst_n = 1; #100;

        $display("=== BAT DAU TEST TOP-LEVEL ===");
        
        $display("PC: Gui lenh CMD_GET_ID (0x01)...");
        uart_send_pc(8'h01);
        
        #5000;
        
        $display("PC: Gui lenh CMD_CHALLENGE (0x02) va 16 byte Nonce...");
        uart_send_pc(8'h02);
        
        uart_send_pc(8'h00); uart_send_pc(8'h11); uart_send_pc(8'h22); uart_send_pc(8'h33);
        uart_send_pc(8'h44); uart_send_pc(8'h55); uart_send_pc(8'h66); uart_send_pc(8'h77);
        uart_send_pc(8'h88); uart_send_pc(8'h99); uart_send_pc(8'hAA); uart_send_pc(8'hBB);
        uart_send_pc(8'hCC); uart_send_pc(8'hDD); uart_send_pc(8'hEE); uart_send_pc(8'hFF);

        $display("PC: Cho FPGA tinh toan AES va tra ve qua TX...");
        #10000;
        
        $display("=== HOAN THANH MO PHONG ===");
        $finish;
    end
endmodule