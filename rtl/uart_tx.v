module uart_tx #(
    parameter CLKS_PER_BIT = 434
)(
    input  wire        CLOCK_50,
    input  wire        rst_n,     
    input  wire        tx_start,
    input  wire [7:0]  tx_byte,
    output reg         UART_TXD,   
    output reg         tx_busy
);

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0]  state   = IDLE;
    reg [12:0] clk_cnt = 0;
    reg [2:0]  bit_idx = 0;
    reg [7:0]  tx_data = 0;

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            UART_TXD <= 1'b1; 
            tx_busy  <= 1'b0;
            clk_cnt  <= 0;
            bit_idx  <= 0;
            tx_data  <= 8'h00;
        end else begin
            case (state)
                IDLE: begin
                    UART_TXD <= 1'b1;  
                    tx_busy  <= 1'b0;  
                    clk_cnt  <= 0;
                    bit_idx  <= 0;
                    if (tx_start) begin
                        tx_data  <= tx_byte; 
                        tx_busy  <= 1'b1;
                        state    <= START;
                    end
                end
                
                START: begin
                    UART_TXD <= 1'b0;  
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= 0;
                        state   <= DATA;
                    end
                end
                
                DATA: begin
                    UART_TXD <= tx_data[bit_idx]; 
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= 0;
                        if (bit_idx < 7) begin
                            bit_idx <= bit_idx + 1'b1;
                        end else begin
                            bit_idx <= 0;
                            state   <= STOP;
                        end
                    end
                end
                
                STOP: begin
                    UART_TXD <= 1'b1;  
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= 0;
                        tx_busy <= 1'b0; 
                        state   <= IDLE; 
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule