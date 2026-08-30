// ============================================================
// ro_puf.v (v3)
//
// Lightweight Ring-Oscillator PUF (RO-PUF), kien truc so sanh
// cap co dien (Suh & Devadas, 2007).
//
// THAY DOI SO VOI v2 (sau khi ra soat lai bang Technology Map
// Viewer / phan tich RTL - xem ghi chu tung muc):
//
//   1. NUM_RO mac dinh: 128 -> 256.
//      NUM_PAIRS = 128 => raw_bits du 128 bit, KHONG con can
//      "puf_id = {raw_bits, ~raw_bits}" nua. Entropy vat ly
//      thuc te = do rong cua puf_id (128 bit thuc, khong phai
//      64 bit nhu ban truoc). Day la khac phuc truc tiep gioi
//      han da neu trong bao cao (dung NUM_RO=256).
//
//   2. Gating chuyen tu "AND o tang cuoi" sang "NAND o dau vong":
//        n0 = ~(n4 & ro_enable);   // NAND: 1 tang dao + gate
//        n1..n4 = inverter thuan.
//      Ly do: NAND o dau vong la ket cau kinh dien cho RO co the
//      bat/tat (gated ring oscillator). Khi ro_enable = 0, moi
//      node duoc ep ve mot gia tri XAC DINH thay vi mot to hop
//      AND+NOT gop chung tai 1 node duy nhat - ro rang hon cho
//      cong cu tong hop nhan dien day la 1 the bao (cell) rieng,
//      giam kha nang Quartus gop/toi uu sai cau truc.
//
//   3. Anh xa vat ly tuong minh bang primitive cyclonev_lcell_comb
//      thay vi 'assign' RTL thuan + assignment DONT_MERGE cap QSF.
//      LY DO: 'DONT_MERGE' bi Quartus Prime 25.1 Standard tu choi
//      khi ap cho wire (loi bien dich da gap). Thay vi doan sai cu
//      phap assignment khac ma khong the tu compile kiem chung
//      trong sandbox nay (khong co Quartus/mang), giai phap chac
//      chan hon ve ky thuat la: instantiate truc tiep LUT vat ly
//      (LCELL) cho tung tang cua RO. Primitive duoc Quartus xem la
//      "black box" ban chat vat ly - KHONG bi gop/toi uu boi
//      Synthesis nhu 'assign' thuan, nen khong con phu thuoc vao
//      assignment DONT_MERGE nua (co the bo hoan toan dong
//      DONT_MERGE trong .qsf).
//      => Neu project khong dung duoc primitive nay (vi du sai ten
//      thu vien do phien ban Quartus khac), FALLBACK duoc giu lai
//      qua macro `RO_PUF_USE_ASSIGN_FALLBACK` (xem duoi) - dung lai
//      'assign' + (* keep = "true" *) nhu ban v2, VAN CAN QSF giu
//      "PRESERVE_REGISTER" (van hop le) nhung KHONG con dung
//      DONT_MERGE (da bi loai khoi ro_puf_constraints.qsf v3).
//      *** Viec dau tien ban PHAI lam: bien dich thu voi
//      RO_PUF_USE_ASSIGN_FALLBACK KHONG dinh nghia (dung primitive).
//      Neu Quartus bao loi "cyclonev_lcell_comb khong ton tai" hoac
//      loi tuong tu, dinh nghia macro fallback va bien dich lai. ***
//
//   4. Them trang thai S_FREEZE_WAIT: sau khi ro_enable = 0, cho
//      them FREEZE_WAIT_CYCLES chu ky he thong (mac dinh 4) truoc
//      khi doc ro_cnt de so sanh, thay vi doc ngay 1 chu ky sau.
//      LY DO: ro_cnt duoc dem theo canh len ro_out[gi] (mien clock
//      rieng cua tung RO) va reset bat dong bo qua negedge
//      ro_enable. ro_enable duoc tao dong bo trong mien CLOCK_50,
//      nen canh xuong cua no co the roi vao dung luc mot ro_out[gi]
//      dang chuyen canh len - day la nguy co metastability/race
//      kinh dien khi mot thanh ghi duoc dieu khien boi 2 nguon
//      clock khac nhau. Cho them vai chu ky he thong (~80ns o
//      50MHz, lon hon nhieu so voi thoi gian dao dong 1 vong cua
//      RO - thuong vai ns) de dam bao moi qua do da tat han truoc
//      khi doc gia tri, giam dang ke rui ro nay. Day la giam rui ro,
//      KHONG loai bo hoan toan (RO-PUF dua tren counter luon co mot
//      xac suat metastability du nho); ban san xuat that nen dung
//      dong ho lay mau (sampling flip-flop) 2 tang cho tung bit
//      ro_cnt thay vi doc truc tiep.
//
// GIOI HAN CON LAI (giu nguyen tu v2, van chua giai quyet - neu ro
// trong bao cao):
//   - Do rong CNT_WIDTH=16 => cua so do 2^16 chu ky @ 50MHz ~ 1.3ms;
//     chua danh gia do nhay nhiet do/dien ap thuc te tren board.
//
// THAY DOI v4 - MAJORITY-VOTE STABILIZATION (fuzzy-extractor rut gon):
//
//   Van de: mot lan do RO-PUF duy nhat (nhu v3) co co the cho ra vai bit
//   sai lech giua cac lan bat nguon khac nhau, do nhieu nhiet/dien ap
//   lam mot vai cap RO co tan so qua gan nhau bi doi thu tu ai-nhanh-
//   ai-cham ngau nhien. Day chinh la gioi han "chua co fuzzy-extractor"
//   da neu tu v2/v3.
//
//   Giai phap trong ban nay: THAY VI mot bo trich xuat entropy day du
//   (fuzzy extractor voi ma sua loi BCH + helper data cong khai luu
//   san xuat - dung ky thuat, nhung ton nhieu thoi gian trien khai va
//   KHO kiem chung dung dan khi khong the mo phong trong sandbox nay),
//   ap dung MAJORITY VOTING theo thoi gian (temporal majority vote):
//     - Lap lai toan bo chu trinh do (S_SAMPLE -> S_FREEZE_WAIT ->
//       S_COMPARE) ROUNDS lan (mac dinh 7, SO LE de khong co the hoa).
//     - Voi moi cap RO, dem so lan "RO chan thang" qua ca ROUNDS lan do
//       (vote_cnt).
//     - Bit cuoi cung = 1 neu vote_cnt > ROUNDS/2 (da so), 0 neu nguoc
//       lai.
//   Ly do ky thuat: neu mot cap RO co tan so qua gan nhau (dam bat on
//   dinh cao), ket qua so sanh cua no se "lat qua lat lai" ngau nhien
//   giua cac lan do - bo phieu da so se on dinh hoa nhung bit co do
//   tin cay thap ve gia tri xuat hien NHIEU HON trong ROUNDS lan do,
//   giam xac suat loi bit tren toan bo puf_id so voi chi do 1 lan.
//
//   VAN LA GIAI PHAP RUT GON, KHONG PHAI FUZZY EXTRACTOR DAY DU:
//     - Khong co helper data cong khai + ma sua loi (ECC/BCH) theo
//       dung dinh nghia hoc thuat cua fuzzy extractor (Dodis et al.,
//       2004) - ky thuat nay CHI giam xac suat loi bit thong ke qua
//       nhieu lan do TRONG CUNG MOT LAN BAT NGUON, khong dam bao sua
//       duoc sai lech GIUA CAC LAN BAT NGUON khac nhau (VD nhiet do
//       luc do khac nhau 20 do C).
//     - Neu can dat chuan hoc thuat day du cho bao cao, day la huong
//       mo rong tiep theo (ghi ro trong bao cao la "further work").
//   => Da NEU RO trong README/bao cao, khong che giau gioi han nay.
//
//   Chi phi: thoi gian do tang tuyen tinh theo ROUNDS (ROUNDS=7 =>
//   ~7 x (2^WINDOW_BITS + FREEZE_WAIT_CYCLES) chu ky thay vi 1 lan.
//   Voi WINDOW_BITS=16 @ 50MHz: ~7 x 1.3ms = ~9.2ms tong thoi gian
//   khoi dong PUF - van nho hon nhieu so voi thoi gian cho 20ms trong
//   cac test Python hien co.
// ============================================================

// Keep the RTL and testbench on the same simulator time scale.
// Questa/ModelSim reports TSCALE when another compiled module
// already has an explicit timeunit/timeprecision.
`timescale 1ns/1ps

// DA KIEM CHUNG bang log Quartus Prime 25.1std.0 THAT: voi macro
// nay o trang thai BAT (nhu duoi day), Analysis & Synthesis/Fitter/
// Assembler/Timing Analyzer bien dich SACH LOI (0 errors), va bang
// chung gian tiep (dem hau to n0~NNN trong canh bao combinational
// loop, chay 512..767 = 256 gia tri) cho thay du 256 vong dao dong
// con nguyen ven, khong bi gop. => KHONG can chuyen sang nhanh
// primitive cyclonev_lcell_comb (con lai duoi day nhu phuong an du
// phong, NHUNG cu phap cua no chua duoc bien dich thu - neu dung,
// tu kiem tra ky).
`define RO_PUF_USE_ASSIGN_FALLBACK

module ro_puf #(
    parameter integer NUM_RO             = 256,  // phai la so chan; NUM_RO/2 = do rong entropy that
    parameter integer WINDOW_BITS        = 16,   // do dai cua so do (2^WINDOW_BITS chu ky clk)
    // Cửa sổ đo mặc định là 2^16 / 50 MHz = 1.31 ms.
    // 16 bit chỉ đếm tối đa 65,535 cạnh, sẽ overflow nếu RO > 50 MHz.
    // 24 bit chịu được tới 16.7 triệu cạnh/cửa sổ.
    parameter integer CNT_WIDTH          = 24,   // do rong bo dem moi vong dao dong
    parameter integer FREEZE_WAIT_CYCLES = 4,    // so chu ky he thong cho "on dinh" sau khi tat RO, truoc khi doc
    parameter integer ROUNDS             = 7     // so lan do lap lai de bo phieu da so (PHAI LA SO LE); <=15
)(
    input  wire         clk,
    input  wire         rst_n,
    output reg  [127:0] puf_id,
    output reg          puf_valid
);

    localparam integer NUM_PAIRS = NUM_RO/2;
    // Do rong dem cho S_FREEZE_WAIT tinh theo FREEZE_WAIT_CYCLES de
    // an toan neu tham so nay duoc doi > 8 (tranh tran so 3-bit cu).
    localparam integer FREEZE_CNT_WIDTH =
        (FREEZE_WAIT_CYCLES <= 1) ? 1 :
        (FREEZE_WAIT_CYCLES <= 2) ? 1 :
        (FREEZE_WAIT_CYCLES <= 4) ? 2 :
        (FREEZE_WAIT_CYCLES <= 8) ? 3 :
        (FREEZE_WAIT_CYCLES <= 16) ? 4 : 8;

    // Do rong bo dem phieu bau: du de dem toi ROUNDS (ROUNDS<=15 => 4 bit)
    localparam integer VOTE_CNT_WIDTH =
        (ROUNDS <= 1)  ? 1 :
        (ROUNDS <= 3)  ? 2 :
        (ROUNDS <= 7)  ? 3 :
        (ROUNDS <= 15) ? 4 : 8;

    // Nguong da so: vote_cnt > ROUNDS/2 (ROUNDS le nen khong the hoa)
    localparam integer MAJORITY_THRESH = ROUNDS/2;

    // ------------------------------------------------------------
    // Vong dao dong co gate (gated ring oscillator), NAND o dau vong.
    // ------------------------------------------------------------
    reg ro_enable;

    // v7.2: dedicated asynchronous clear for the per-ring counters.
    // Active LOW.  Deliberately SEPARATE from ro_enable - see the long
    // note above the gen_cnt block.  Only ever pulsed while ro_enable = 0.
    reg cnt_clr_n;

    wire [NUM_RO-1:0] ro_out;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_RO; gi = gi + 1) begin : gen_ro

`ifdef RO_PUF_USE_ASSIGN_FALLBACK
            // --- FALLBACK: RTL thuan + attribute keep (nhu v2) ---
            // Neu dung nhanh nay: PHAI kiem tra Technology Map Viewer
            // sau Analysis & Synthesis de xac nhan 256 vong con nguyen
            // ven, KHONG bi Quartus gop lai.
            (* keep = "true" *) wire n0, n1, n2, n3, n4;

`ifdef RO_PUF_SIM
            // ==========================================================
            // SIMULATION ONLY - never synthesised (guarded by RO_PUF_SIM)
            // ==========================================================
            // A zero-delay combinational ring oscillates infinitely at
            // time 0 and hangs any event-driven simulator, so a real
            // testbench cannot exercise this module without help.
            //
            // Giving each stage a small, ring-dependent delay does two
            // things: it makes the loop advance in simulated time, and it
            // makes the rings run at DIFFERENT frequencies - a crude
            // stand-in for the silicon process variation that the PUF
            // actually measures.  Without the per-ring difference every
            // counter would land on the same value and every comparison
            // would tie, which would hide exactly the class of bug this
            // model exists to catch.
            //
            // The delays are chosen so that adjacent rings (the pairs the
            // comparator uses) are never equal.
            localparam integer SIM_STAGE_DLY = 2 + (gi % 5);

            assign #SIM_STAGE_DLY n0 = ~(n4 & ro_enable);
            assign #SIM_STAGE_DLY n1 = ~n0;
            assign #SIM_STAGE_DLY n2 = ~n1;
            assign #SIM_STAGE_DLY n3 = ~n2;
            assign #SIM_STAGE_DLY n4 = ~n3;
`else
            assign n0 = ~(n4 & ro_enable);   // NAND: gate + 1 tang dao
            assign n1 = ~n0;
            assign n2 = ~n1;
            assign n3 = ~n2;
            assign n4 = ~n3;
`endif
            assign ro_out[gi] = n4;
`else
            // --- THAY THE: anh xa truc tiep vao LUT vat ly Cyclone V ---
            // cyclonev_lcell_comb: LUT 4-dau-vao vat ly, KHONG bi gop/
            // toi uu boi synthesis (duoc Quartus coi la primitive cong
            // nghe, khong phai RTL to hop thuan).
            wire n0, n1, n2, n3, n4_fb;

            cyclonev_lcell_comb #(
                .lut_mask(16'h7777),   // NAND(dataa, datab)
                .shared_arith("off"),
                .extended_lut("off")
            ) u_nand_gate (
                .dataa (n4_fb),
                .datab (ro_enable),
                .datac (1'b0),
                .datad (1'b0),
                .cin   (1'b0),
                .sharein(1'b0),
                .combout(n0)
            );

            cyclonev_lcell_comb #(
                .lut_mask(16'h5555),   // NOT(dataa)
                .shared_arith("off"),
                .extended_lut("off")
            ) u_inv1 (
                .dataa (n0), .datab(1'b0), .datac(1'b0), .datad(1'b0),
                .cin(1'b0), .sharein(1'b0), .combout(n1)
            );

            cyclonev_lcell_comb #(
                .lut_mask(16'h5555),
                .shared_arith("off"),
                .extended_lut("off")
            ) u_inv2 (
                .dataa (n1), .datab(1'b0), .datac(1'b0), .datad(1'b0),
                .cin(1'b0), .sharein(1'b0), .combout(n2)
            );

            cyclonev_lcell_comb #(
                .lut_mask(16'h5555),
                .shared_arith("off"),
                .extended_lut("off")
            ) u_inv3 (
                .dataa (n2), .datab(1'b0), .datac(1'b0), .datad(1'b0),
                .cin(1'b0), .sharein(1'b0), .combout(n3)
            );

            cyclonev_lcell_comb #(
                .lut_mask(16'h5555),
                .shared_arith("off"),
                .extended_lut("off")
            ) u_inv4 (
                .dataa (n3), .datab(1'b0), .datac(1'b0), .datad(1'b0),
                .cin(1'b0), .sharein(1'b0), .combout(n4_fb)
            );

            assign ro_out[gi] = n4_fb;

            // *** CANH BAO QUAN TRONG: cu phap chinh xac cua
            // cyclonev_lcell_comb (ten cong, thu tu tham so, ten port
            // sharein/cin co bat buoc hay khong) PHAI duoc doi chieu
            // voi Quartus Prime 25.1 that - khong co Quartus/mang
            // trong sandbox nay de tu bien dich kiem chung primitive
            // nay. Day la ly do macro RO_PUF_USE_ASSIGN_FALLBACK ton
            // tai: neu Analysis & Synthesis bao loi ve cyclonev_lcell_
            // comb (sai ten port/thieu thu vien), HAY BAT macro fallback
            // o dau file va bien dich lai bang nhanh 'assign' + keep -
            // van dung duoc, chi kem chac chan hon ve chong toi uu,
            // nen se can kiem tra ky Technology Map Viewer.
`endif

        end
    endgenerate

    // ------------------------------------------------------------
    // Bo dem rieng cho tung vong dao dong, dem canh len cua chinh no.
    // Giu ve 0 khi ro_enable = 0.
    // ------------------------------------------------------------
    // ============================================================
    // v7.2 BUG FIX - P0 FUNCTIONAL DEFECT
    // ============================================================
    // v7.1 and earlier used ro_enable as BOTH the oscillator gate AND
    // the asynchronous clear of the counters:
    //
    //     always @(posedge ro_out[gi] or negedge ro_enable)
    //         if (!ro_enable) cnt_r <= 0;          // <-- WRONG
    //         else            cnt_r <= cnt_r + 1;
    //
    // The controller ends a measurement window with
    //     ro_enable <= 1'b0;  state <= S_FREEZE_WAIT;
    // so the falling edge of ro_enable ZEROED every counter at exactly
    // the moment the value was supposed to be frozen for reading.  By
    // the time S_COMPARE ran, every ro_cnt was 0, so
    //     ro_cnt[2*k] > ro_cnt[2*k+1]   ->  0 > 0  ->  always false
    // every vote_cnt stayed 0, every raw_bit resolved to 0, and
    // puf_id came out as 128'd0 on EVERY board.
    //
    // Consequence: diversified_key = AES(master_key, 0) was identical on
    // every device.  The chip still answered challenges correctly, so the
    // FPGA demo and the server check both "passed" - which is exactly why
    // this survived Quartus, timing closure and board testing.  What was
    // silently lost was the entire per-device uniqueness claim.
    //
    // FIX: drive the counters from a dedicated active-low clear,
    // cnt_clr_n, that is pulsed ONLY at the start of a window (while the
    // rings are already stopped).  ro_enable now purely gates the
    // oscillators, so stopping them HOLDS the count instead of erasing it.
    //
    // Race safety is preserved: cnt_clr_n is only ever toggled while
    // ro_enable = 0, i.e. while ro_out[gi] is static.  There is therefore
    // no edge on the counter's clock when the asynchronous clear moves,
    // which is a stronger guarantee than the v7.1 arrangement had.
    // ============================================================
    wire [CNT_WIDTH-1:0] ro_cnt [0:NUM_RO-1];

    generate
        for (gi = 0; gi < NUM_RO; gi = gi + 1) begin : gen_cnt
            reg [CNT_WIDTH-1:0] cnt_r;
            always @(posedge ro_out[gi] or negedge cnt_clr_n) begin
                if (!cnt_clr_n)
                    cnt_r <= {CNT_WIDTH{1'b0}};
                else
                    cnt_r <= cnt_r + 1'b1;
            end
            assign ro_cnt[gi] = cnt_r;
        end
    endgenerate

    // ------------------------------------------------------------
    // Bo dieu khien mien CLOCK_50: mo cua so do, dong bang, CHO
    // ON DINH (FREEZE_WAIT_CYCLES chu ky), so sanh theo cap, LAP LAI
    // ROUNDS lan (tich luy vao vote_cnt), roi cuoi cung chot bit theo
    // da so (majority-vote stabilization - xem ghi chu v4 o dau file).
    // ------------------------------------------------------------
    reg [WINDOW_BITS-1:0] window_cnt;
    reg [3:0]             state;
    localparam S_IDLE        = 4'd0,
               S_SAMPLE      = 4'd1,
               S_FREEZE_WAIT = 4'd2,
               S_COMPARE     = 4'd3,
               S_NEXT_ROUND  = 4'd4,
               S_FINALIZE    = 4'd5,
               S_DONE        = 4'd6,
               // v7.2: new states. S_CLEAR holds cnt_clr_n low for a few
               // system cycles while the rings are stopped; S_ARM then
               // releases the clear and restarts the oscillators.  This
               // replaces the old (broken) "clear via ro_enable" scheme.
               S_CLEAR       = 4'd7,
               S_ARM         = 4'd8,
               S_START       = 4'd9;

    // How long cnt_clr_n is held low.  The clear is asynchronous and the
    // rings are stopped, so one cycle would be enough functionally; a few
    // cycles gives comfortable margin over clear-recovery time.
    localparam integer CLEAR_CYCLES = 4;

    localparam integer CLEAR_CNT_WIDTH =
        (CLEAR_CYCLES <= 1) ? 1 :
        (CLEAR_CYCLES <= 2) ? 1 :
        (CLEAR_CYCLES <= 4) ? 2 :
        (CLEAR_CYCLES <= 8) ? 3 :
        (CLEAR_CYCLES <= 16) ? 4 : 8;

    reg [FREEZE_CNT_WIDTH-1:0]   freeze_cnt;
    reg [CLEAR_CNT_WIDTH-1:0]    clear_cnt;
    reg [3:0]                    round_idx;   // gia dinh ROUNDS <= 15
    reg [VOTE_CNT_WIDTH-1:0]     vote_cnt [0:NUM_PAIRS-1];
    reg [NUM_PAIRS-1:0]          raw_bits;    // ket qua da so cuoi cung
    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            window_cnt <= {WINDOW_BITS{1'b0}};
            ro_enable  <= 1'b0;
            cnt_clr_n  <= 1'b0;     // hold counters cleared while in reset
            puf_valid  <= 1'b0;
            puf_id     <= 128'd0;
            raw_bits   <= {NUM_PAIRS{1'b0}};
            freeze_cnt <= {FREEZE_CNT_WIDTH{1'b0}};
            clear_cnt  <= {CLEAR_CNT_WIDTH{1'b0}};
            round_idx  <= 4'd0;
            for (k = 0; k < NUM_PAIRS; k = k + 1)
                vote_cnt[k] <= {VOTE_CNT_WIDTH{1'b0}};
        end else begin
            case (state)
                S_IDLE: begin
                    // v7.2: do NOT start the rings here.  Clear the
                    // counters first (rings still stopped), then arm.
                    ro_enable  <= 1'b0;
                    cnt_clr_n  <= 1'b0;
                    freeze_cnt <= {FREEZE_CNT_WIDTH{1'b0}};
                    clear_cnt  <= {CLEAR_CNT_WIDTH{1'b0}};
                    window_cnt <= {WINDOW_BITS{1'b0}};
                    round_idx  <= 4'd0;
                    for (k = 0; k < NUM_PAIRS; k = k + 1)
                        vote_cnt[k] <= {VOTE_CNT_WIDTH{1'b0}};
                    state      <= S_CLEAR;
                end

                // ------------------------------------------------------
                // S_CLEAR: rings are stopped, hold the asynchronous clear
                // low for CLEAR_CYCLES so every cnt_r is definitely zero
                // before a new window opens.
                // ------------------------------------------------------
                S_CLEAR: begin
                    // RO đã dừng. Giữ clear thấp đủ lâu để xóa toàn bộ counter.
                    ro_enable <= 1'b0;
                    cnt_clr_n <= 1'b0;

                    if (clear_cnt == CLEAR_CYCLES[CLEAR_CNT_WIDTH-1:0] - 1'b1) begin
                        clear_cnt <= {CLEAR_CNT_WIDTH{1'b0}};
                        state     <= S_ARM;
                    end else begin
                        clear_cnt <= clear_cnt + 1'b1;
                    end
                end

                // ------------------------------------------------------
                // S_ARM: release the clear one cycle BEFORE enabling the
                // rings, so the clear de-assertion can never coincide
                // with a ro_out edge.
                // ------------------------------------------------------
                S_ARM: begin
                    // Chỉ nhả clear. RO vẫn tắt trong cả chu kỳ này.
                    // Như vậy clear release không trùng cạnh ro_out.
                    cnt_clr_n <= 1'b1;
                    ro_enable <= 1'b0;
                    state     <= S_START;
                end

                S_START: begin
                    // Sang chu kỳ kế tiếp mới bật RO.
                    cnt_clr_n  <= 1'b1;
                    ro_enable  <= 1'b1;
                    window_cnt <= {WINDOW_BITS{1'b0}};
                    state      <= S_SAMPLE;
                end

                S_SAMPLE: begin
                    if (window_cnt == {WINDOW_BITS{1'b1}}) begin
                        // v7.2: stop the oscillators only.  cnt_clr_n stays
                        // HIGH, so every counter HOLDS its value for
                        // S_COMPARE to read.  (Pre-v7.2 this line also
                        // zeroed every counter - the P0 bug.)
                        ro_enable  <= 1'b0;
                        freeze_cnt <= {FREEZE_CNT_WIDTH{1'b0}};
                        state      <= S_FREEZE_WAIT;
                    end else begin
                        window_cnt <= window_cnt + 1'b1;
                    end
                end

                S_FREEZE_WAIT: begin
                    // Cho them vai chu ky de moi RO tat han va het
                    // nguy co race giua negedge ro_enable va posedge
                    // ro_out[gi] truoc khi doc ro_cnt (xem ghi chu #4
                    // o dau file).
                    if (freeze_cnt == FREEZE_WAIT_CYCLES[FREEZE_CNT_WIDTH-1:0] - 1'b1)
                        state <= S_COMPARE;
                    else
                        freeze_cnt <= freeze_cnt + 1'b1;
                end

                S_COMPARE: begin
                    // Cong don phieu bau cho vong do nay (KHONG ghi
                    // truc tiep vao raw_bits nhu v3 - phai qua tich
                    // luy nhieu vong roi moi chot o S_FINALIZE).
                    for (k = 0; k < NUM_PAIRS; k = k + 1)
                        if (ro_cnt[2*k] > ro_cnt[2*k+1])
                            vote_cnt[k] <= vote_cnt[k] + 1'b1;
                    state <= S_NEXT_ROUND;
                end

                S_NEXT_ROUND: begin
                    if (round_idx == ROUNDS[3:0] - 1'b1) begin
                        state <= S_FINALIZE;
                    end else begin
                        // v7.2: next round goes through S_CLEAR so the
                        // counters are zeroed while the rings are stopped,
                        // instead of relying on a ro_enable edge.
                        round_idx  <= round_idx + 1'b1;
                        ro_enable  <= 1'b0;
                        cnt_clr_n  <= 1'b0;
                        freeze_cnt <= {FREEZE_CNT_WIDTH{1'b0}};
                        clear_cnt  <= {CLEAR_CNT_WIDTH{1'b0}};
                        window_cnt <= {WINDOW_BITS{1'b0}};
                        state      <= S_CLEAR;
                    end
                end

                S_FINALIZE: begin
                    // Chot bit cuoi cung theo da so qua ROUNDS lan do.
                    for (k = 0; k < NUM_PAIRS; k = k + 1)
                        raw_bits[k] <= (vote_cnt[k] > MAJORITY_THRESH[VOTE_CNT_WIDTH-1:0]);
                    state <= S_DONE;
                end

                S_DONE: begin
                    // NUM_RO=256 => NUM_PAIRS=128 => raw_bits da du
                    // 128 bit that (khong con can ghep {raw,~raw}).
                    // Neu ai do doi NUM_RO < 256, phan cao tu dong
                    // zero-pad (KHONG con nhan doi bit thap nhu ban
                    // v2 - tranh gay hieu lam ve entropy thuc).
                    puf_id    <= {{(128-NUM_PAIRS){1'b0}}, raw_bits};
                    puf_valid <= 1'b1;
                    // giu nguyen o day cho den khi reset; PUF chi do 1 lan/lan bat nguon
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
