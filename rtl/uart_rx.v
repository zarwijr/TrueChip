module uart_rx #(
    parameter CLKS_PER_BIT = 434
)(
    input  wire        CLOCK_50,
    input  wire        UART_RXD,  
    input  wire        rst_n,
    output reg         rx_valid,
    output reg  [7:0]  rx_byte
);

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0]  state    = IDLE;
    reg [12:0] clk_cnt  = 0;
    reg [2:0]  bit_idx  = 0;
    reg [7:0]  rx_shift = 0;

    reg rx_d1, rx_d2;

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            rx_d1 <= 1'b1;
            rx_d2 <= 1'b1;
        end else begin
            rx_d1 <= UART_RXD; 
            rx_d2 <= rx_d1;
        end
    end

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            clk_cnt  <= 0;
            bit_idx  <= 0;
            rx_shift <= 8'h00;
            rx_byte  <= 8'h00;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0; 

            case (state)
                IDLE: begin
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (rx_d2 == 1'b0) 
                        state <= START;
                end

                START: begin
                    if (clk_cnt == (CLKS_PER_BIT - 1) / 2) begin
                        if (rx_d2 == 1'b0) begin
                            clk_cnt <= 0;
                            state   <= DATA;
                        end else
                            state <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end

                DATA: begin
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        rx_shift[bit_idx] <= rx_d2; 
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
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        rx_valid <= 1'b1;      
                        rx_byte  <= rx_shift;   
                        clk_cnt  <= 0;
                        state    <= IDLE;    
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule