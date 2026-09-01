module cmd_parser (
    input  wire         CLOCK_50,
    input  wire         rst_n,

    input  wire         rx_valid,
    input  wire [7:0]   rx_byte,

    output reg          cmd_get_id,
    output reg          cmd_challenge,
    output reg [127:0]  challenge_nonce,

    output reg          crc_error,
    output reg          packet_error
);

    // ============================================================
    // TRUECHIP UART PROTOCOL V2
    //
    // A5 | VER | CMD | LEN | PAYLOAD | CRC_H | CRC_L
    // CRC16-CCITT, polynomial 0x1021, init 0xFFFF.
    // CRC covers VER | CMD | LEN | PAYLOAD.
    // ============================================================

    localparam [7:0] MAGIC          = 8'hA5;
    localparam [7:0] VERSION        = 8'h01;
    localparam [7:0] REQ_GET_ID     = 8'h01;
    localparam [7:0] REQ_CHALLENGE  = 8'h02;
    localparam [7:0] LEN_GET_ID     = 8'h00;
    localparam [7:0] LEN_CHALLENGE  = 8'h10;

    localparam [3:0]
        S_IDLE      = 4'd0,
        S_VERSION   = 4'd1,
        S_CMD       = 4'd2,
        S_LEN       = 4'd3,
        S_PAYLOAD   = 4'd4,
        S_CRC_H     = 4'd5,
        S_CRC_L     = 4'd6;

    // 5 ms @ 50 MHz = 250,000 cycles. The previous 13000-cycle (~260us)
    // timeout was tight enough that ordinary PC/USB-UART driver latency
    // (COM port latency timers are often 1-16 ms) could insert an
    // inter-byte gap long enough to abort an otherwise-valid in-progress
    // frame. Widening this gives real host-side jitter room while still
    // recovering promptly from a genuinely truncated/dead frame.
    localparam [19:0] FRAME_TIMEOUT = 20'd250000;

    reg [3:0] state;
    reg [19:0] timeout_cnt;

    reg [7:0] cmd_reg;
    reg [4:0] payload_count;
    reg [119:0] nonce_reg;   // 15 buffered bytes; byte 16 is concatenated directly

    reg [15:0] crc_reg;
    reg [7:0]  crc_hi_reg;

    // verilator lint_off BLKSEQ
    // Blocking assignments are CORRECT here: this is a pure combinational
    // function, not a clocked process.  Verilator flags it only because the
    // function is *called* from an always @(posedge ...) block.  Using '<='
    // inside a function is illegal, so the warning is a false positive.
    function [15:0] crc16_byte;
        input [15:0] crc_in;
        input [7:0] data;
        reg [15:0] crc;
        integer i;
        begin
            crc = crc_in ^ {data,8'h00};
            for (i = 0; i < 8; i = i + 1) begin
                if (crc[15])
                    crc = (crc << 1) ^ 16'h1021;
                else
                    crc = crc << 1;
            end
            crc16_byte = crc;
        end
    endfunction
    // verilator lint_on BLKSEQ

    // Start a new frame.  The current A5 is consumed as MAGIC and
    // the following byte must be VERSION.
    task start_frame;
        begin
            state          <= S_VERSION;
            timeout_cnt    <= 20'd0;
            crc_reg        <= 16'hFFFF;
            crc_hi_reg     <= 8'h00;
            cmd_reg        <= 8'h00;
            payload_count  <= 5'd0;
            nonce_reg      <= 120'd0;
        end
    endtask

    // Return to idle after a bad/truncated frame.
    task abort_frame;
        begin
            state         <= S_IDLE;
            timeout_cnt   <= 20'd0;
            crc_reg       <= 16'hFFFF;
            crc_hi_reg    <= 8'h00;
            cmd_reg       <= 8'h00;
            payload_count <= 5'd0;
            nonce_reg     <= 120'd0;
        end
    endtask

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            timeout_cnt    <= 20'd0;
            cmd_reg        <= 8'h00;
            payload_count  <= 5'd0;
            nonce_reg      <= 120'd0;
            challenge_nonce<= 128'd0;
            crc_reg        <= 16'hFFFF;
            crc_hi_reg     <= 8'h00;
            cmd_get_id     <= 1'b0;
            cmd_challenge  <= 1'b0;
            crc_error      <= 1'b0;
            packet_error   <= 1'b0;
        end else begin
            // All event outputs are one-clock pulses.
            cmd_get_id    <= 1'b0;
            cmd_challenge <= 1'b0;
            crc_error     <= 1'b0;
            packet_error  <= 1'b0;

            if (rx_valid) begin
                timeout_cnt <= 20'd0;

                case (state)
                    // ------------------------------------------------
                    // IDLE: scan for MAGIC.  Arbitrary garbage is safe.
                    // ------------------------------------------------
                    S_IDLE: begin
                        if (rx_byte == MAGIC)
                            start_frame();
                    end

                    // ------------------------------------------------
                    // VERSION: if another A5 arrives, treat it as a
                    // fresh MAGIC.  This is important for stream
                    // recovery when garbage contains a partial header.
                    // ------------------------------------------------
                    S_VERSION: begin
                        if (rx_byte == VERSION) begin
                            crc_reg <= crc16_byte(16'hFFFF, rx_byte);
                            state   <= S_CMD;
                        end else if (rx_byte == MAGIC) begin
                            start_frame();
                        end else begin
                            packet_error <= 1'b1;
                            abort_frame();
                        end
                    end

                    // ------------------------------------------------
                    // CMD: only supported commands are accepted.
                    // A5 is a valid resynchronization point.
                    // ------------------------------------------------
                    S_CMD: begin
                        if ((rx_byte == REQ_GET_ID) ||
                            (rx_byte == REQ_CHALLENGE)) begin
                            cmd_reg <= rx_byte;
                            crc_reg <= crc16_byte(crc_reg, rx_byte);
                            state   <= S_LEN;
                        end else if (rx_byte == MAGIC) begin
                            packet_error <= 1'b1;
                            start_frame();
                        end else begin
                            packet_error <= 1'b1;
                            abort_frame();
                        end
                    end

                    // ------------------------------------------------
                    // LEN: validate the command-specific length.
                    // ------------------------------------------------
                    S_LEN: begin
                        crc_reg <= crc16_byte(crc_reg, rx_byte);

                        if (cmd_reg == REQ_GET_ID) begin
                            if (rx_byte == LEN_GET_ID) begin
                                state <= S_CRC_H;
                            end else begin
                                packet_error <= 1'b1;
                                if (rx_byte == MAGIC)
                                    start_frame();
                                else
                                    abort_frame();
                            end
                        end else if (cmd_reg == REQ_CHALLENGE) begin
                            if (rx_byte == LEN_CHALLENGE) begin
                                payload_count <= 5'd0;
                                nonce_reg     <= 120'd0;
                                state          <= S_PAYLOAD;
                            end else begin
                                packet_error <= 1'b1;
                                if (rx_byte == MAGIC)
                                    start_frame();
                                else
                                    abort_frame();
                            end
                        end else begin
                            packet_error <= 1'b1;
                            abort_frame();
                        end
                    end

                    // ------------------------------------------------
                    // PAYLOAD: fixed 16-byte challenge nonce.
                    // A5 is data here, not MAGIC, because the length is
                    // known and the frame is structurally valid.
                    // ------------------------------------------------
                    S_PAYLOAD: begin
                        nonce_reg <= {nonce_reg[111:0], rx_byte};
                        crc_reg   <= crc16_byte(crc_reg, rx_byte);

                        if (payload_count == 5'd15) begin
                            challenge_nonce <= {nonce_reg, rx_byte};
                            payload_count   <= 5'd0;
                            state           <= S_CRC_H;
                        end else begin
                            payload_count <= payload_count + 1'b1;
                        end
                    end

                    // ------------------------------------------------
                    // CRC high byte.
                    // ------------------------------------------------
                    S_CRC_H: begin
                        crc_hi_reg <= rx_byte;
                        state      <= S_CRC_L;
                    end

                    // ------------------------------------------------
                    // CRC low byte.  A valid packet produces exactly
                    // one command pulse.  If the low CRC byte itself is
                    // A5 on a bad packet, preserve it as next MAGIC.
                    // ------------------------------------------------
                    S_CRC_L: begin
                        // crc_reg already includes VER/CMD/LEN/PAYLOAD.
                        // Only the two CRC bytes are excluded.
                        if (crc_reg == {crc_hi_reg, rx_byte}) begin
                            // One-cycle event pulse. The top-level FIFO
                            // samples this pulse on the following clock.
                            if (cmd_reg == REQ_GET_ID) begin
                                cmd_get_id <= 1'b1;
                            end else if (cmd_reg == REQ_CHALLENGE) begin
                                cmd_challenge <= 1'b1;
                            end
                            state       <= S_IDLE;
                            timeout_cnt <= 20'd0;
                        end else begin
                            crc_error <= 1'b1;
                            // If the byte that failed CRC is itself A5,
                            // do not discard it: it is a valid MAGIC for
                            // the next frame in a continuous byte stream.
                            if (rx_byte == MAGIC)
                                start_frame();
                            else
                                abort_frame();
                        end
                    end

                    default: begin
                        abort_frame();
                    end
                endcase
            end else begin
                // Timeout incomplete frames so a truncated packet can
                // never poison the parser indefinitely.
                if (state != S_IDLE) begin
                    if (timeout_cnt < FRAME_TIMEOUT) begin
                        timeout_cnt <= timeout_cnt + 1'b1;
                    end else begin
                        abort_frame();
                    end
                end else begin
                    timeout_cnt <= 20'd0;
                end
            end
        end
    end
endmodule
