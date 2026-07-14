module cmd_parser (
    input  wire         CLOCK_50, 
    input  wire         rst_n,
    input  wire         rx_valid,
    input  wire [7:0]   rx_byte,
    
    output reg          cmd_get_id,
    output reg          cmd_challenge,
    output reg  [127:0] challenge_nonce,
    output reg  [7:0]   status_byte
);

    localparam WAIT_CMD   = 3'd0;
    localparam RECV_NONCE = 3'd1;

    localparam CMD_GET_ID    = 8'h01;
    localparam CMD_CHALLENGE = 8'h02;
    localparam CMD_STATUS    = 8'h03;

    reg [2:0]   state     = WAIT_CMD;
    reg [4:0]   byte_cnt  = 0; 
    reg [127:0] nonce_buf = 0;

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            state           <= WAIT_CMD; 
            cmd_get_id      <= 1'b0; 
            cmd_challenge   <= 1'b0;
            challenge_nonce <= 128'd0;
            status_byte     <= 8'd0;
            byte_cnt        <= 5'd0;
            nonce_buf       <= 128'd0;
        end else begin
            cmd_get_id    <= 1'b0; 
            cmd_challenge <= 1'b0;
            
            case (state)
                WAIT_CMD: begin
                    if (rx_valid) begin
                        case (rx_byte)
                            CMD_GET_ID: begin 
                                cmd_get_id <= 1'b1; 
                            end
                            CMD_CHALLENGE: begin
                                byte_cnt  <= 5'd0; 
                                nonce_buf <= 128'd0;
                                state     <= RECV_NONCE;
                            end
                            CMD_STATUS: begin
                                status_byte <= 8'hAA;
                            end
                            default: ;
                        endcase
                    end
                end
                
                RECV_NONCE: begin
                    if (rx_valid) begin
                        nonce_buf <= {nonce_buf[119:0], rx_byte}; 
                        byte_cnt  <= byte_cnt + 1'b1;
                        
                        if (byte_cnt == 5'd15) begin
                            challenge_nonce <= {nonce_buf[119:0], rx_byte};
                            cmd_challenge   <= 1'b1;
                            state           <= WAIT_CMD;
                        end
                    end
                end
                
                default: state <= WAIT_CMD;
            endcase
        end
    end
endmodule