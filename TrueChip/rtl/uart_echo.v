module uart_echo #(
    parameter CLKS_PER_BIT = 434
)(
    input  wire clk,
    input  wire rst_n,
    input  wire rx,
    output wire tx
);
    wire rx_valid; 
    wire [7:0] rx_byte; 
    wire tx_busy;
    
    reg tx_start = 0; 
    reg [7:0] tx_byte_reg = 0;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), 
        .rst_n(rst_n),
        .rx_serial(rx), 
        .rx_valid(rx_valid), 
        .rx_byte(rx_byte)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), 
        .tx_start(tx_start), 
        .tx_byte(tx_byte_reg),
        .tx_serial(tx), 
        .tx_busy(tx_busy)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_start    <= 1'b0;
            tx_byte_reg <= 8'h00;
        end else begin
            tx_start <= 1'b0;
            
            if (rx_valid && !tx_busy) begin
                tx_byte_reg <= rx_byte; 
                tx_start    <= 1'b1;
            end
        end
    end
endmodule