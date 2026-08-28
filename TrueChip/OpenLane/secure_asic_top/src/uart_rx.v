module uart_rx #(
    parameter CLKS_PER_BIT = 434
)(
    input  wire        CLOCK_50, 
    input  wire        rx,  
    input  wire        rst_n,
    output reg         rx_valid,
    output reg  [7:0]  rx_byte
);
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0]  state;
    reg [12:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  rx_shift;

    // CDC synchronizer for the asynchronous UART input. The attribute is
    // understood by several synthesis/STA flows; the two-flop structure is
    // also explicitly constrained in the ASIC SDC.
    (* async_reg = "true" *) reg rx_d1, rx_d2;
    
    // Synchronize RX signal to clock domain
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            rx_d1 <= 1'b1;
            rx_d2 <= 1'b1;
        end else begin
            rx_d1 <= rx;
            rx_d2 <= rx_d1;
        end
    end

    // FSM for UART Receiver
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
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
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
                        // Basic framing check: accept a byte only when the
                        // stop bit is high. A low stop bit is discarded and
                        // the receiver resynchronizes in IDLE.
                        if (rx_d2 == 1'b1) begin
                            rx_valid <= 1'b1;
                            rx_byte  <= rx_shift;
                        end
                        clk_cnt <= 0;
                        state   <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
