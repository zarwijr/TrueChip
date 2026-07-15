module aes128 (
    input  wire         clk, 
    input  wire         rst_n, 
    input  wire         start,
    input  wire [127:0] plaintext, 
    input  wire [127:0] key,
    
    output reg  [127:0] ciphertext,
    output reg          done
);

    function [7:0] xtime(input [7:0] b);
        begin
            xtime = b[7] ? ({b[6:0], 1'b0} ^ 8'h1b) : {b[6:0], 1'b0};
        end
    endfunction

    function [127:0] shift_rows(input [127:0] s);
        begin
            shift_rows = {
                s[127:120], s[87:80],   s[47:40],   s[7:0],
                s[95:88],   s[55:48],   s[15:8],    s[103:96],
                s[63:56],   s[23:16],   s[111:104], s[71:64],
                s[31:24],   s[119:112], s[79:72],   s[39:32]
            };
        end
    endfunction

    function [127:0] mix_columns(input [127:0] s);
        reg [7:0] s0, s1, s2, s3, r0, r1, r2, r3;
        integer col; 
        reg [127:0] result;
        begin
            result = 0;
            for (col = 0; col < 4; col = col + 1) begin
                s0 = s[127 - 32*col -: 8]; 
                s1 = s[119 - 32*col -: 8];
                s2 = s[111 - 32*col -: 8]; 
                s3 = s[103 - 32*col -: 8];
                
                r0 = xtime(s0) ^ xtime(s1) ^ s1 ^ s2 ^ s3;
                r1 = s0 ^ xtime(s1) ^ xtime(s2) ^ s2 ^ s3;
                r2 = s0 ^ s1 ^ xtime(s2) ^ xtime(s3) ^ s3;
                r3 = xtime(s0) ^ s0 ^ s1 ^ s2 ^ xtime(s3);
                
                result[127 - 32*col -: 8] = r0; 
                result[119 - 32*col -: 8] = r1;
                result[111 - 32*col -: 8] = r2; 
                result[103 - 32*col -: 8] = r3;
            end
            mix_columns = result;
        end
    endfunction

    reg  [127:0] state;
    wire [127:0] state_sub;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_state_sbox
            aes_sbox sb_state (
                .in(state[127 - i*8 : 120 - i*8]),
                .out(state_sub[127 - i*8 : 120 - i*8])
            );
        end
    endgenerate

    reg  [127:0] round_key;
    reg  [3:0]   round_num;
    wire [127:0] next_round_key;
    wire [31:0]  key_sub;
    
    wire [31:0] w0 = round_key[127:96];
    wire [31:0] w1 = round_key[95:64];
    wire [31:0] w2 = round_key[63:32];
    wire [31:0] w3 = round_key[31:0];

    wire [31:0] rot_word = {w3[23:0], w3[31:24]};

    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_key_sbox
            aes_sbox sb_key (
                .in(rot_word[31 - i*8 : 24 - i*8]),
                .out(key_sub[31 - i*8 : 24 - i*8])
            );
        end
    endgenerate

    reg [7:0] rcon_val;
    always @(*) begin
        case(round_num)
            4'd1:  rcon_val = 8'h01;
            4'd2:  rcon_val = 8'h02;
            4'd3:  rcon_val = 8'h04;
            4'd4:  rcon_val = 8'h08;
            4'd5:  rcon_val = 8'h10;
            4'd6:  rcon_val = 8'h20;
            4'd7:  rcon_val = 8'h40;
            4'd8:  rcon_val = 8'h80;
            4'd9:  rcon_val = 8'h1B;
            4'd10: rcon_val = 8'h36;
            default: rcon_val = 8'h00;
        endcase
    end

    wire [31:0] next_w0 = w0 ^ key_sub ^ {rcon_val, 24'h000000};
    wire [31:0] next_w1 = w1 ^ next_w0;
    wire [31:0] next_w2 = w2 ^ next_w1;
    wire [31:0] next_w3 = w3 ^ next_w2;
    
    assign next_round_key = {next_w0, next_w1, next_w2, next_w3};

    reg active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            active    <= 0; 
            done      <= 0; 
            round_num <= 0; 
            state     <= 0;
            round_key <= 0;
            ciphertext <= 0;
        end else begin
            done <= 0;
            
            if (start && !active) begin
                state     <= plaintext ^ key; 
                round_key <= key;
                round_num <= 4'd1;
                active    <= 1;
            end 
            else if (active) begin
                if (round_num < 10) begin
                    state     <= mix_columns(shift_rows(state_sub)) ^ next_round_key;
                    round_key <= next_round_key;
                    round_num <= round_num + 1'b1;
                end 
                else if (round_num == 10) begin
                    ciphertext <= shift_rows(state_sub) ^ next_round_key;
                    active     <= 0;
                    done       <= 1;
                end
            end
        end
    end
endmodule