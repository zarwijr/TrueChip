module uart_echo #(
    parameter CLKS_PER_BIT = 434
)(
    input  wire CLOCK_50,
    input  wire rst_n,
    input  wire rx,
    output wire tx
);
    wire       rx_valid;
    wire [7:0] rx_byte;
    wire       tx_busy;

    reg        tx_start;
    reg [7:0]  tx_byte;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .CLOCK_50(CLOCK_50),
        .rst_n(rst_n),
        .rx(rx),
        .rx_valid(rx_valid),
        .rx_byte(rx_byte)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .CLOCK_50(CLOCK_50),
        .rst_n(rst_n),
        .tx(tx),
        .tx_start(tx_start),
        .tx_byte(tx_byte),
        .tx_busy(tx_busy)
    );

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            tx_start <= 1'b0;
            tx_byte  <= 8'h00;
        end else begin
            tx_start <= 1'b0;
            if (rx_valid && !tx_busy) begin
                tx_byte  <= rx_byte;
                tx_start <= 1'b1;
            end
        end
    end
endmodule
