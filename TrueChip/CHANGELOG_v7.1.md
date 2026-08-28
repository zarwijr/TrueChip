# TrueChip v7.1 change log — 25/08/2026

Bản vá lỗi trên nền v7. **Không thay đổi giao thức, không thay đổi thuật toán,
không thay đổi kiến trúc.** Toàn bộ thay đổi thuộc 4 nhóm: sửa testbench hỏng,
dọn cảnh báo tool, siết ràng buộc vật lý, và vá lỗi runtime phía Python.

---

## 1. Verification — nhóm sửa quan trọng nhất

### 1.1 `Simulation/auth_fsm_tb.sv` — viết lại, từ FAIL thành PASS

Bản v7 **luôn luôn thất bại** khi chạy thật:

```
FATAL: auth_fsm_tb.sv:35: TIMEOUT waiting for tx_start, expected a5
       Time: 1090000
```

`auth_fsm.v` không có lỗi. Testbench có hai race condition riêng biệt:

**Race 1 — kích thích được drive đúng tại sườn clock.**

```verilog
cmd_get_id = 1; @(posedge clk); cmd_get_id = 0;   // v7 — SAI
```

`cmd_get_id = 0` là phép gán blocking thực thi đúng tại thời điểm `posedge`,
trong khi DUT cũng lấy mẫu tại chính sườn đó. Thứ tự giữa hai tiến trình do
scheduler quyết định → DUT có thể thấy `0` và bỏ lỡ lệnh.

**Sửa:** mọi kích thích chuyển sang `@(negedge clk)`, cách sườn lấy mẫu nửa chu kỳ.

**Race 2 — "gắn" bộ chờ sườn sau khi sườn đã đi qua.**

```verilog
cmd_challenge = 0;                    // tiêu tốn time step
fork @(posedge aes_start); ... join_any   // v7 — SAI, aes_start đã lên rồi
```

**Sửa:** không bao giờ dùng `@(posedge <tín hiệu DUT>)`. Thay bằng vòng lặp lấy
mẫu mỗi chu kỳ sau vùng cập nhật non-blocking (`@(posedge clk); #1;`) với ngân
sách chu kỳ tường minh.

Đồng thời bổ sung một bài test mới: xác minh nonce vẫn bị từ chối khi đã nằm sâu
3 vị trí trong cửa sổ lịch sử `HIST_DEPTH = 8` (v7 chỉ test replay ngay lập tức).

### 1.2 Xóa `Simulation/auth_fsm_tb.v`

CHANGELOG_v7 ghi *"Removed duplicate auth_fsm_tb.v"* nhưng file vẫn còn trong ZIP.
Biên dịch cả thư mục sẽ hỏng ngay:

```
error: 'auth_fsm_tb' has already been declared in this scope
```

Bản `.v` còn thiếu port `auth_ready` / `locked_out` và dính đúng race ở trên.

### 1.3 Xóa `Simulation/secure_soc_top_tb.v` — testbench "PASS giả"

Đây là lỗi nguy hiểm nhất trong v7. File này:

- gửi khung **thiếu 2 byte CRC** (định dạng V1 cũ) → `cmd_parser` không bao giờ
  nhận lệnh;
- **không kiểm tra bất cứ thứ gì** — chỉ `$display("[PASS] ...")` rồi `$finish`;
- **giống hệt byte-for-byte** file `Simulation/fpga_only/secure_soc_top_tb_legacy.v`
  đã bị khai tử.

Nó báo "PASS" ngay cả khi thiết kế chết hoàn toàn. Đã xóa; bản legacy vẫn nằm
đúng chỗ trong `fpga_only/`.

### 1.4 Thêm mới `Simulation/secure_asic_top_tb.v` — testbench full-chip tự kiểm tra

Đây là bằng chứng verification mạnh nhất trong gói nộp. Nó lái khung Protocol V2
thật (có CRC16-CCITT) vào chân `uart_rx_i` của `secure_asic_top`, giải mã byte
trả về từ `uart_tx_o`, và so sánh với **giá trị vàng tính độc lập bằng
pycryptodome** (không lấy từ lần chạy RTL trước — nên đây là kiểm tra tham chiếu
thật, không phải regression tự thỏa mãn).

Chứng minh 9 điểm:

| # | Nội dung |
|---|---|
| 1 | Boot KDF hoàn tất, `key_ready_o` lên sau 14 chu kỳ |
| 2 | GET_ID → `A5 01 00 10` + UID 128-bit |
| 3 | CHALLENGE → `A5 01 00 10` + AES-128(diversified_key, nonce XOR uid) |
| 4 | CHALLENGE thứ hai ngay lập tức → `A5 01 04 00` (RATE_LIMIT), payload rỗng |
| 5 | Replay nonce cũ sau cooldown → `A5 01 03 00` (REPLAY) |
| 6 | Khung có CRC hỏng → bị loại im lặng, chip không phát byte nào |
| 7 | Nonce mới sau tất cả cơ chế bảo vệ → xác thực lại đúng |
| 8 | `locked_out_o` và `fifo_overflow_o` giữ LOW suốt phiên |
| 9 | Khung UART đúng chuẩn 8N1 (kiểm tra cả stop bit) |

**Giá trị vàng:**

```
LAYOUT_DEVICE_SEED = A55A5AA51357246889ABCDEF01234567
master_key         = 12341234123412341234123412341234
diversified_key    = AES(master_key, seed) = D56DB0F67612790CE56147A44F67AF6F
chip_uid           = 25832583258325832583258325832583

nonce 00112233445566778899AABBCCDDEEFF -> 2090AD5530F3783DDBFC906F96A0A330  (CRC 9174)
nonce 0F1E2D3C4B5A69788796A5B4C3D2E1F0 -> 97990FF7A51804AF5A130D905B3E4802  (CRC 5169)
```

**Kiểm chứng testbench không phải "PASS giả" (mutation test).** Cố tình bỏ phép
XOR UID trong `auth_fsm.v` (`aes_plaintext <= cur_nonce;`) → testbench bắt được
ngay và thoát với `$fatal`:

```
[FAIL] CHALLENGE#1 payload mismatch
        expected = 2090ad5530f3783ddbfc906f96a0a330
        got      = 6918578413e70725a64adaa490423ae8
=== FULL-CHIP TESTS FAILED: 2 error(s) ===
```

### 1.5 Thêm mới `Simulation/run_regression.sh`

Chạy toàn bộ 7 hạng mục bằng một lệnh, thoát non-zero nếu có bất kỳ lỗi nào — an
toàn để dùng trong CI. Phát hiện lỗi qua **cả** exit code lẫn chuỗi `[FAIL]`
trong log, nên không thể bị qua mặt bởi testbench chỉ in text.

---

## 2. RTL — dọn cảnh báo tool, không đổi hành vi

| # | File | Sửa |
|---|---|---|
| 2.1 | `aes128.v`, `aes_sbox.v`, `auth_fsm.v`, `uart_rx.v`, `uart_tx.v` | Thêm newline cuối file — hết `%Warning-EOFNEWLINE` (5 cảnh báo Verilator trong `logs/synthesis/linter.log`) |
| 2.2 | `cmd_parser.v` | Đổi `CMD_GET_ID`/`CMD_CHALLENGE` → `REQ_GET_ID`/`REQ_CHALLENGE`. Hết Quartus `Info (10281)` "differs only in case from cmd_get_id/cmd_challenge" |
| 2.3 | `cmd_parser.v` | `nonce_reg` từ `[127:0]` xuống `[119:0]`. Hết `%Warning-UNUSEDSIGNAL: nonce_reg[127:120]`. Chỉ cần đệm 15 byte, byte thứ 16 ghép trực tiếp |
| 2.4 | `cmd_parser.v` | `lint_off BLKSEQ` quanh `crc16_byte()` — dùng blocking trong function là **bắt buộc** (`<=` trong function là bất hợp lệ), Verilator báo nhầm |
| 2.5 | `secure_soc_top.v` | `32'bz` → `{32{1'bz}}`. Hết Quartus `Warning (10273)` "extended using x or z" |
| 2.6 | `secure_soc_top.v` | Thêm `assign GPIO[0] = 1'bz;` — GPIO[0] là inout chỉ dùng làm input, phải drive high-Z tường minh thay vì để tool đoán hướng |
| 2.7 | `secure_soc_top.v`, `secure_asic_top.v` | `KDF_START`/`KDF_WAIT`/`KDF_DONE` → `KDF_ST_START`/`KDF_ST_WAIT`/`KDF_ST_DONE`. Hết `Info (10281)` với thanh ghi `kdf_start` |
| 2.8 | `secure_soc_top.v`, `secure_asic_top.v` | `lint_off PINCONNECTEMPTY` quanh `crc_error`/`packet_error` kèm giải thích |

### 2.9 `KEY[1]` — từ chân chết thành chức năng thật

v7 để `KEY[1]` treo hoàn toàn (Quartus Warning 21074/15610 *"No output dependent
on input pin KEY[1]"*), chính comment trong code cũng thừa nhận *"Day la chan
input CHET THAT SU"*.

v7.1 nối nó qua bộ đồng bộ 2 flip-flop `(* async_reg = "true" *)` và dùng làm nút
**xóa cờ `fifo_overflow`** (LEDR[9] / GPIO debug).

**Ràng buộc bảo mật đã giữ nguyên có chủ đích:**

- `KEY[1]` **không** được nối vào `auth_fsm`.
- Nó **không** mở khóa được trạng thái lockout.
- Lockout vẫn chỉ thoát được bằng power-cycle thật qua `rst_n`, nên kẻ tấn công
  chỉ có UART không thể tự "hồi sinh" chip.
- Overflow thật luôn **thắng** nút xóa (`if (overflow) ... else if (clear)`), nên
  không thể giữ nút để che một overflow đang diễn ra.

**Kết quả lint sau khi sửa:** `verilator --lint-only -Wall` trên `secure_asic_top`
(toàn bộ 8 file đưa vào OpenLane) → **0 error, 0 warning**.

Trên `secure_soc_top` còn 3 `BLKLOOPINIT` + 1 `UNOPTFLAT`, tất cả nằm trong
`ro_puf.v`. Đây là **giới hạn của Verilator** với ring oscillator (vòng lặp tổ
hợp) và gán non-blocking vào mảng trong for-loop — **không phải lỗi Quartus**
(Quartus 25.1 biên dịch `secure_soc_top` với 0 Error, 0 Critical Warning). Đúng
như README đã nói, `ro_puf.v` là FPGA-only và không nằm trong luồng ASIC.

---

## 3. Physical design

### 3.1 `config.json` — dẹp 215 vi phạm antenna

`reports/metrics.csv` của `run_2` báo `pin_antenna_violations = 129` và
`net_antenna_violations = 86`. Nguyên nhân: run chỉ thừa hưởng mặc định một lượt
chèn diode của OpenLane. `GRT_MAX_DIODE_INS_ITERS` **chỉ tồn tại trong file rác
`config .json`** (có dấu cách trong tên — không được flow đọc), không có trong
`config.json` thật.

Đã bổ sung:

```json
"GRT_REPAIR_ANTENNAS": 1,
"GRT_MAX_DIODE_INS_ITERS": 5,
"DIODE_INSERTION_STRATEGY": 3,
"RUN_HEURISTIC_DIODE_INSERTION": 1
```

Đồng thời bật tường minh `RUN_MAGIC_DRC`, `RUN_KLAYOUT_DRC`, `RUN_LVS`,
`RUN_KLAYOUT_XOR` để mỗi lần chạy đều tự sinh lại bằng chứng DRC/LVS/XOR.

### 3.2 `constraints.sdc` — ràng buộc I/O thật

File v7 chỉ có `create_clock` + 2 dòng `set_false_path`. Vì nó được dùng làm
**cả** `PNR_SDC_FILE` lẫn `SIGNOFF_SDC_FILE`, nó thay thế hoàn toàn `base.sdc`
của OpenLane → **mọi đường I/O trong `run_2` hoàn toàn không bị ràng buộc**, và
slack báo cáo chỉ phủ đường register-to-register. Con số timing vì thế yếu hơn vẻ ngoài.

Đã bổ sung:

- `set_clock_uncertainty -setup 0.250` / `-hold 0.100` (không có PLL nên phải dự
  phòng skew + jitter), `set_clock_transition 0.150`, `set_propagated_clock`
- `set_input_delay` / `set_output_delay` = 20% chu kỳ mỗi chiều
- `set_driving_cell sky130_fd_sc_hd__inv_2` — v7 mặc định driver lý tưởng (trở kháng 0)
- `set_load 0.010` — v7 mặc định tải nhận 0 fF
- `set_max_fanout 10` (khớp `MAX_FANOUT_CONSTRAINT` sẵn có), `set_max_transition 1.5`

`rst_n` và `uart_rx_i` vẫn giữ `set_false_path` như v7 — chúng thực sự bất đồng bộ
và đi qua bộ đồng bộ 2 flop.

### 3.3 Dọn file rác

Xóa `runs/run_2/config .json` (tên có dấu cách, không được flow đọc, gây hiểu
nhầm khi review) và toàn bộ `.DS_Store`.

### 3.4 ⚠️ Lưu ý bắt buộc cho báo cáo: `wns = -27.02` KHÔNG phải lỗi

`reports/metrics.csv` có đúng một cột `wns`/`tns`, lấy từ
`logs/synthesis/2-sta.log` — tức là **STA trước khi place, dùng wireload model**.
Trong `run_2` cột đó ghi `wns = -27.02`, `tns = -86022.05`.

Số signoff thật nằm ở chỗ khác và **đều đạt**:

| Log | wns | tns | worst slack |
|---|---|---|---|
| `signoff/26-rcx_mcsta.min.log` | 0.00 | 0.00 | +1.84 / +0.10 |
| `signoff/28-rcx_mcsta.max.log` | 0.00 | 0.00 | +1.08 / +0.10 |
| `signoff/30-rcx_mcsta.nom.log` | 0.00 | 0.00 | +1.46 / +0.10 |
| `signoff/31-rcx_sta.log` | 0.00 | 0.00 | +10.92 / +0.31 |

Trong báo cáo hãy trích các log signoff này, **đừng trích cột trong metrics.csv**.
Ghi chú tương tự đã được nhúng vào cuối `constraints.sdc` để lần review sau không
mắc lại.

---

## 4. Python

| # | File | Lỗi | Sửa |
|---|---|---|---|
| 4.1 | `client/chip_tester.py` | `--repeat 0` bỏ qua vòng lặp scan rồi crash `IndexError` tại `results[0]` | Kiểm tra `args.repeat < 1` và báo lỗi rõ ràng, trả về mã 2 |
| 4.2 | `server/mock_server.py` | `init_db()` chạy trần lúc import. Nếu PostgreSQL chưa sẵn sàng (rất bình thường trên Render khi web service boot trước database), exception thoát khỏi import và **giết gunicorn worker ngay** — service trông như "chết" thay vì "đang đợi DB" | Bọc `try/except`, log cảnh báo, giữ process sống. Thêm `ensure_db_ready()` tạo bảng lazy ở request đầu tiên; nếu DB vẫn không có thì trả `503` với lý do rõ ràng |
| 4.3 | `server/mock_server.py` | `normalize_hex(chip["secret_key"], ...)` ném `SecureChipError` khi cột `secret_key` hỏng (sai độ dài, ký tự lạ, dòng cấp phát dở dang) → thoát khỏi `verify_payload()` thành HTTP 500 mù mờ | Bắt riêng, log kèm UID, trả `500` với thông báo tiếng Việt rõ ràng: cần cấp phát lại tại nhà máy |

Đã chạy `sync_rtl.py` để đồng bộ lại `OpenLane/secure_asic_top/src/` — 8/8 file
khớp byte-for-byte với `RTL/`.
