module auth_fsm #(
    // Rate limiting: so chu ky he thong (CLOCK_50) phai cho giua 2 lan
    // phuc vu CHALLENGE lien tiep. Mac dinh 500_000 chu ky @ 50MHz =
    // ~10ms. Muc dich: khong anh huong 1 lan xac thuc hop le don le
    // (verify binh thuong khong can ban lien tuc), nhung lam cham dang
    // ke cac cuoc tan cong do lap lai nhieu lan (side-channel sampling,
    // brute-force do/thu) tu chuc nang truoc kia khong gioi han toc do.
    parameter integer COOLDOWN_CYCLES   = 500_000,
    // So lan lien tiep bi tu choi (replay HOAC rate-limit) truoc khi
    // chip tu khoa vinh vien (den khi power-cycle that). Day la lop
    // phong ve chong brute-force/do lap qua giao thuc CHALLENGE.
    parameter integer LOCKOUT_THRESHOLD = 5
)(
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

    output wire         auth_ready,

    // HIGH vinh vien sau khi bi khoa (chi ha xuong khi power-cycle
    // that qua rst_n) - dung cho LED/GPIO debug va cho bao cao chung
    // minh co che lockout hoat dong.
    output wire          locked_out,

    output reg  [2:0]   led_state
);

    // ============================================================
    // Response framing (paired with request Protocol V2)
    // ============================================================

    localparam MAGIC   = 8'hA5;
    localparam VERSION = 8'h01;

    localparam STATUS_OK          = 8'h00;
    localparam STATUS_REPLAY      = 8'h03;
    localparam STATUS_RATE_LIMIT  = 8'h04;
    localparam STATUS_LOCKED      = 8'h05;

    // ============================================================
    // FSM states
    // ============================================================

    localparam IDLE          = 4'd0;
    localparam SEND_HDR      = 4'd1;
    localparam WAIT_TX_HDR   = 4'd2;
    localparam SEND_PLD      = 4'd3;
    localparam WAIT_TX_PLD   = 4'd4;
    localparam PREP_AES      = 4'd5;
    localparam WAIT_AES      = 4'd6;
    localparam LOCKED        = 4'd7;

    reg [3:0] state;

    reg [2:0] hdr_idx;
    reg [4:0] pld_idx;

    reg [31:0]  tx_header;
    reg [127:0] tx_payload;
    reg [4:0]   payload_len;

    // ============================================================
    // Replay protection - cua so lich su HIST_DEPTH nonce gan nhat
    // (thay vi chi nho 1 nonce cuoi cung nhu ban truoc). Ke tan
    // cong xen ke vai nonce khong con bypass duoc de dang.
    //
    // Luu y: day la lop phong ve THEM tai chip, khong thay the
    // yeu cau server phai luon phat nonce ngau nhien/dung 1 lan -
    // do van la tuyen phong thu chinh chong replay tren toan he
    // thong.
    // ============================================================

    localparam integer HIST_DEPTH = 8;

    reg [127:0] nonce_hist  [0:HIST_DEPTH-1];
    reg         hist_valid  [0:HIST_DEPTH-1];
    reg [2:0]   hist_wr_ptr;

    // 'h' o muc module: dung cho vong lap reset dong bo cua
    // nonce_hist/hist_valid (always @(posedge CLOCK_50 ...) ben duoi).
    // Khoi do la tuan tu (suy luan flip-flop), KHONG bi canh bao latch
    // nhu khoi to hop, nen giu nguyen o day la dung.
    integer h;

    // Khoi to hop rieng dung bien vong lap TEN KHAC ('rh_idx'), khai
    // bao cuc bo trong named block - thay vi dung chung ten 'h' voi
    // block tren roi dua vao shadow-scope (chua duoc bien dich kiem
    // chung trong sandbox nay, nen tranh phu thuoc vao co che do de
    // an toan). Day la nguyen nhan goc cua Warning (10240) latch cho
    // bien vong lap trong khoi to hop - khai bao cuc bo giai quyet no.
    reg replay_hit;
    always @(*) begin : replay_check
        integer rh_idx;
        replay_hit = 1'b0;
        for (rh_idx = 0; rh_idx < HIST_DEPTH; rh_idx = rh_idx + 1)
            if (hist_valid[rh_idx] && (challenge_nonce == nonce_hist[rh_idx]))
                replay_hit = 1'b1;
    end

    // ============================================================
    // Nonce latch for the CHALLENGE currently being serviced.
    //
    // IMPORTANT: challenge_nonce is fed from the command FIFO's
    // read head (fifo_nonce[fifo_rd_ptr]) at the top level. The FIFO
    // pops (advances fifo_rd_ptr) the SAME cycle we leave IDLE, so
    // by the time we reach PREP_AES the live challenge_nonce port
    // no longer points at the nonce we just accepted - it points at
    // whatever is next in the FIFO (or an unwritten slot). We must
    // latch it in IDLE, before the FIFO head moves on, and use the
    // latched copy in PREP_AES instead of re-reading the port.
    // ============================================================

    reg [127:0] cur_nonce;

    // ============================================================
    // Rate limiting + lockout
    //
    // cooldown_cnt: dem nguoc sau moi lan phuc vu CHALLENGE (bat ke
    // ket qua) - trong khoang nay, moi yeu cau CHALLENGE moi bi tu
    // choi ngay (STATUS_RATE_LIMIT), KHONG chay AES (tranh cung cap
    // oracle cho tan cong do thoi gian/cong suat lap lai).
    //
    // fail_cnt: dem so lan TU CHOI LIEN TIEP (replay HOAC rate-limit).
    // Duoc dua ve 0 moi khi mot CHALLENGE MOI (khong bi tu choi) duoc
    // chap nhan - tuc la chi "hanh vi bi nghi ngo lien tuc" moi tich
    // luy, mot yeu cau hop le xen giua se "tha" bo dem.
    //
    // Khi fail_cnt cham LOCKOUT_THRESHOLD: chip gui 1 khung
    // STATUS_LOCKED roi chuyen vinh vien sang trang thai LOCKED - chi
    // thoat duoc bang power-cycle that (rst_n), khong co lenh phan mem
    // nao mo khoa duoc. Day la co y: bat buoc ke tan cong phai co
    // quyen truy cap VAT LY (rut nguon/cam lai) moi duoc thu tiep,
    // thay vi co the tu dong lap lai qua mang/UART vo han.
    // ============================================================

    reg [31:0] cooldown_cnt;
    reg [3:0]  fail_cnt;   // du cho LOCKOUT_THRESHOLD <= 15
    reg        going_to_lockout;

    assign locked_out = (state == LOCKED);

    // ============================================================
    // AUTH READY
    //
    // HIGH means auth_fsm can accept one command on the current clock.
    // The FIFO presents a stable command while valid; therefore the
    // consumer handshake is simply (cmd_valid && auth_ready).  The
    // existing interface has separate command bits, so IDLE itself is
    // the implicit command-valid acceptance point.
    // ============================================================

    assign auth_ready = (state == IDLE);

    // ============================================================
    // Main FSM
    // ============================================================

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin

            state             <= IDLE;

            aes_start         <= 1'b0;
            aes_plaintext     <= 128'd0;
            aes_key           <= 128'd0;

            tx_start          <= 1'b0;
            tx_byte           <= 8'd0;

            led_state         <= 3'b001;

            hdr_idx           <= 0;
            pld_idx           <= 0;

            tx_header         <= 32'd0;
            tx_payload        <= 128'd0;
            payload_len       <= 0;

            hist_wr_ptr       <= 3'd0;
            for (h = 0; h < HIST_DEPTH; h = h + 1) begin
                nonce_hist[h] <= 128'd0;
                hist_valid[h] <= 1'b0;
            end

            cur_nonce         <= 128'd0;

            cooldown_cnt      <= 32'd0;
            fail_cnt          <= 4'd0;
            going_to_lockout  <= 1'b0;

        end else begin

            // Default pulse outputs
            aes_start <= 1'b0;
            tx_start  <= 1'b0;

            // Dem nguoc cooldown moi chu ky (khong phu thuoc trang thai)
            if (cooldown_cnt != 32'd0)
                cooldown_cnt <= cooldown_cnt - 1'b1;

            case (state)

                // ==================================================
                // IDLE
                // ==================================================

                IDLE: begin

                    led_state <= 3'b001;

                    hdr_idx <= 0;
                    pld_idx <= 0;

                    // ------------------------------------------------
                    // GET_ID
                    // ------------------------------------------------

                    if (cmd_get_id && auth_ready) begin

                        tx_header   <= {
                            MAGIC,
                            VERSION,
                            STATUS_OK,
                            8'h10
                        };

                        tx_payload  <= chip_uid;
                        payload_len <= 5'd16;

                        state <= SEND_HDR;
                    end

                    // ------------------------------------------------
                    // CHALLENGE
                    // ------------------------------------------------

                    else if (cmd_challenge && auth_ready) begin

                        // Rate limit: con trong thoi gian cooldown ->
                        // tu choi ngay, KHONG chay AES, KHONG ghi vao
                        // lich su nonce (khong tieu ton tai nguyen cho
                        // yeu cau bi tu choi o buoc nay).
                        if (cooldown_cnt != 32'd0) begin

                            tx_header <= {
                                MAGIC,
                                VERSION,
                                STATUS_RATE_LIMIT,
                                8'h00
                            };

                            tx_payload  <= 128'd0;
                            payload_len <= 5'd0;

                            if (fail_cnt >= LOCKOUT_THRESHOLD[3:0] - 1'b1) begin
                                going_to_lockout <= 1'b1;
                                tx_header <= {
                                    MAGIC, VERSION, STATUS_LOCKED, 8'h00
                                };
                            end else begin
                                fail_cnt <= fail_cnt + 1'b1;
                            end

                            state <= SEND_HDR;

                        // Replay detection: kiem tra ca cua so
                        // HIST_DEPTH nonce gan nhat (to hop, xem
                        // replay_hit o phan khai bao).
                        end else if (replay_hit) begin

                            tx_header <= {
                                MAGIC,
                                VERSION,
                                STATUS_REPLAY,
                                8'h00
                            };

                            tx_payload  <= 128'd0;
                            payload_len <= 5'd0;

                            if (fail_cnt >= LOCKOUT_THRESHOLD[3:0] - 1'b1) begin
                                going_to_lockout <= 1'b1;
                                tx_header <= {
                                    MAGIC, VERSION, STATUS_LOCKED, 8'h00
                                };
                            end else begin
                                fail_cnt <= fail_cnt + 1'b1;
                            end

                            state <= SEND_HDR;

                        end else begin

                            // New nonce - latch it NOW, before the FIFO
                            // (at the top level) advances its read
                            // pointer on this same cycle's pop.
                            nonce_hist[hist_wr_ptr] <= challenge_nonce;
                            hist_valid[hist_wr_ptr] <= 1'b1;
                            hist_wr_ptr              <= hist_wr_ptr + 1'b1;

                            cur_nonce        <= challenge_nonce;

                            // Yeu cau hop le, khong bi tu choi -> "tha"
                            // bo dem fail_cnt (xem ghi chu o phan khai
                            // bao rate limiting + lockout).
                            fail_cnt <= 4'd0;

                            // Bat dau cooldown cho lan CHALLENGE ke tiep.
                            cooldown_cnt <= COOLDOWN_CYCLES[31:0];

                            state <= PREP_AES;
                        end
                    end
                end

                // ==================================================
                // PREP AES
                // ==================================================

                PREP_AES: begin

                    // Use the latched nonce, NOT the live challenge_nonce
                    // port - by this cycle the FIFO head has already
                    // moved past the entry we just accepted.
                    //
                    // Response framing (paired with request Protocol V2): plaintext = challenge_nonce ^ chip_uid,
                    // ma hoa bang secret_key = diversified_key (PUF-derived,
                    // xem key-derivation FSM o secure_soc_top.v). Khong con
                    // session_salt noi bo (da bo - xem README/bao cao thiet
                    // ke ve ly do: uu tien giao thuc don gian, dung, verify
                    // duoc o phia server hon la them 1 lop trang thai noi
                    // bo chua kiem chung duoc).
                    aes_plaintext <= cur_nonce ^ chip_uid;
                    aes_key       <= secret_key;

                    aes_start <= 1'b1;

                    led_state <= 3'b010;

                    state <= WAIT_AES;
                end

                // ==================================================
                // WAIT AES
                // ==================================================

                WAIT_AES: begin

                    if (aes_done) begin

                        tx_header <= {
                            MAGIC,
                            VERSION,
                            STATUS_OK,
                            8'h10
                        };

                        tx_payload  <= aes_ciphertext;
                        payload_len <= 5'd16;

                        state <= SEND_HDR;
                    end
                end

                // ==================================================
                // SEND HEADER
                // ==================================================

                SEND_HDR: begin

                    if (!tx_busy) begin

                        tx_byte <= tx_header[
                            31 - hdr_idx*8 -: 8
                        ];

                        tx_start <= 1'b1;

                        state <= WAIT_TX_HDR;
                    end
                end

                // ==================================================
                // WAIT HEADER BYTE
                // ==================================================

                WAIT_TX_HDR: begin

                    if (!tx_busy && !tx_start) begin

                        if (hdr_idx == 3) begin

                            if (going_to_lockout) begin
                                // Da gui xong khung STATUS_LOCKED - khoa
                                // vinh vien, khong quay lai IDLE nua.
                                state <= LOCKED;
                            end else if (payload_len == 0) begin
                                state <= IDLE;
                            end else begin
                                state <= SEND_PLD;
                            end

                        end else begin

                            hdr_idx <= hdr_idx + 1'b1;
                            state   <= SEND_HDR;

                        end
                    end
                end

                // ==================================================
                // SEND PAYLOAD
                // ==================================================

                SEND_PLD: begin

                    led_state <= 3'b100;

                    if (!tx_busy) begin

                        tx_byte <= tx_payload[
                            127 - pld_idx*8 -: 8
                        ];

                        tx_start <= 1'b1;

                        state <= WAIT_TX_PLD;
                    end
                end

                // ==================================================
                // WAIT PAYLOAD BYTE
                // ==================================================

                WAIT_TX_PLD: begin

                    if (!tx_busy && !tx_start) begin

                        if (pld_idx == payload_len - 1) begin

                            state <= IDLE;

                        end else begin

                            pld_idx <= pld_idx + 1'b1;
                            state   <= SEND_PLD;

                        end
                    end
                end

                // ==================================================
                // LOCKED - trang thai khoa vinh vien
                //
                // Khong lam gi ca. KHONG duoc de roi vao 'default'
                // (default: state <= IDLE se VO TINH TU MO KHOA moi
                // chu ky - day la loi nghiem trong neu bo sot). Chi
                // thoat duoc bang power-cycle that (nhanh reset o dau
                // always block).
                // ==================================================

                LOCKED: begin
                    // giu nguyen vinh vien
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule
