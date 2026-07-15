module auth_fsm (
    input  wire         CLOCK_50, 
    input  wire         rst_n,
    input  wire         cmd_get_id, 
    input  wire         cmd_challenge,
    input  wire [127:0] challenge_nonce,
    input  wire [127:0] aes_ciphertext,
    input  wire         aes_done,
    input  wire [127:0] chip_uid, 
    input  wire [127:0] secret_key,
    
    output reg          aes_start,
    output reg  [127:0] aes_plaintext, 
    output reg  [127:0] aes_key,
    output reg          tx_start,
    output reg  [7:0]   tx_byte,
    input  wire         tx_busy,
    output reg  [2:0]   led_state  
);

    localparam IDLE          = 4'd0;
    localparam SEND_UID      = 4'd1;
    localparam WAIT_TX_UID   = 4'd2;
    localparam PREP_AES      = 4'd3;
    localparam WAIT_AES      = 4'd4;
    localparam SEND_RESPONSE = 4'd5;
    localparam WAIT_TX_RESP  = 4'd6;

    reg [3:0]   state = IDLE;
    reg [4:0]   byte_idx = 0;
    reg [127:0] response_buf = 0;
    reg [127:0] last_nonce = 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin 
            state          <= IDLE; 
            aes_start      <= 1'b0; 
            tx_start       <= 1'b0; 
            led_state      <= 3'b001; 
            byte_idx       <= 5'd0;
            aes_plaintext  <= 128'd0;
            aes_key        <= 128'd0;
            tx_byte        <= 8'd0;
            response_buf   <= 128'd0;
            last_nonce     <= 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
        end else begin
            aes_start <= 1'b0; 
            tx_start  <= 1'b0;
            
            case (state)
                IDLE: begin
                    led_state <= 3'b001;
                    if (cmd_get_id) begin 
                        byte_idx <= 0; 
                        state    <= SEND_UID; 
                    end
                    else if (cmd_challenge) begin
                        if (challenge_nonce == last_nonce) begin
                            tx_byte  <= 8'hFF; 
                            tx_start <= 1'b1; 
                        end else begin
                            last_nonce <= challenge_nonce; 
                            state      <= PREP_AES;
                        end
                    end
                end
                
                SEND_UID: begin
                    if (!tx_busy) begin
                        tx_byte  <= chip_uid[127 - byte_idx*8 -: 8];
                        tx_start <= 1'b1;
                        state    <= WAIT_TX_UID;
                    end
                end
                
                WAIT_TX_UID: begin
                    if (!tx_busy && !tx_start) begin
                        if (byte_idx == 15) begin 
                            byte_idx <= 0; 
                            state    <= IDLE; 
                        end else begin 
                            byte_idx <= byte_idx + 1'b1;
                            state    <= SEND_UID; 
                        end
                    end
                end
                
                PREP_AES: begin
                    aes_plaintext <= challenge_nonce ^ chip_uid;
                    aes_key       <= secret_key;
                    aes_start     <= 1'b1;
                    led_state     <= 3'b010;
                    state         <= WAIT_AES;
                end
                
                WAIT_AES: begin
                    if (aes_done) begin
                        response_buf <= aes_ciphertext;
                        byte_idx     <= 0; 
                        state        <= SEND_RESPONSE;
                    end
                end
                
                SEND_RESPONSE: begin
                    led_state <= 3'b100;
                    if (!tx_busy) begin
                        tx_byte  <= response_buf[127 - byte_idx*8 -: 8];
                        tx_start <= 1'b1;
                        state    <= WAIT_TX_RESP;
                    end
                end
                
                WAIT_TX_RESP: begin
                    if (!tx_busy && !tx_start) begin
                        if (byte_idx == 15) begin 
                            byte_idx <= 0; 
                            state    <= IDLE; 
                        end else begin 
                            byte_idx <= byte_idx + 1'b1;
                            state    <= SEND_RESPONSE; 
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule