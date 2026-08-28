# TrueChip v7.1 validation note — 25/08/2026

File này ghi lại **chính xác** những gì đã được chạy thật trong workspace review,
để lần review sau không nhầm lẫn giữa kiểm tra tĩnh và kết quả tool thật.

Khác biệt lớn nhất so với `VALIDATION_v7.md`: v7 chỉ parse tĩnh vì workspace
không có tool. Lần này **Icarus Verilog 12.0 và Verilator 5.020 đã được cài và
chạy thật**.

---

## 1. Đã CHẠY THẬT trong workspace review

### 1.1 Mô phỏng RTL — Icarus Verilog 12.0

Lệnh: `bash Simulation/run_regression.sh` → **exit code 0**

```
[PASS] AES 82fdca6456d22b89ed31a03a7ccbb6aa
[PASS] AES be1dbd7b5fefe7b9bc0cc66030a25d61
[PASS] AES a1f6258c877d5fcd8964484538bfc92c
[PASS] UART loopback byte=ab
[PASS] GET_ID Protocol V2 + CRC
[PASS] CHALLENGE Protocol V2 nonce=00112233445566778899aabbccddeeff
[PASS] Bad CRC rejected
[PASS] GET_ID frame = A5 01 00 10 + 16-byte UID
[PASS] CHALLENGE frame = A5 01 00 10 + AES ciphertext
[PASS] Replay of a used nonce -> STATUS_REPLAY (0x03)
[PASS] Nonce still rejected 3 entries deep in the history window
[PASS] UART echo smoke test completed
[PASS] Boot KDF completed, key_ready_o HIGH after 14 clocks
[PASS] GET_ID -> A5 01 00 10 + UID 25832583258325832583258325832583
[PASS] CHALLENGE#1 nonce=00112233445566778899aabbccddeeff
[PASS] Immediate 2nd CHALLENGE -> STATUS_RATE_LIMIT (0x04), 0-byte payload
[PASS] Replayed nonce after cooldown -> STATUS_REPLAY (0x03)
[PASS] Frame with corrupted CRC silently discarded
[PASS] CHALLENGE#2 nonce=0f1e2d3c4b5a69788796a5b4c3d2e1f0
[PASS] secure_soc_top elaborates cleanly

REGRESSION SUMMARY: 7 passed, 0 failed
```

### 1.2 Lõi AES đối chiếu chuẩn độc lập

3 vector trong `tb_aes128.v` được đối chiếu với **pycryptodome**, cộng thêm vector
chuẩn **FIPS-197** (`key=000102...0f`, `pt=00112233445566778899aabbccddeeff`
→ `ct=69c4e0d86a7b0430d8cdb78070b4c55a`). Tất cả khớp. Lõi AES-128 đúng.

### 1.3 Mutation test — chứng minh testbench không phải "PASS giả"

Cố tình bỏ phép XOR UID trong `auth_fsm.v`:
`aes_plaintext <= cur_nonce ^ chip_uid;` → `aes_plaintext <= cur_nonce;`

`secure_asic_top_tb.v` bắt được ngay và thoát bằng `$fatal`:

```
[FAIL] CHALLENGE#1 payload mismatch
        expected = 2090ad5530f3783ddbfc906f96a0a330
        got      = 6918578413e70725a64adaa490423ae8
=== FULL-CHIP TESTS FAILED: 2 error(s) ===
```

### 1.4 Lint — Verilator 5.020

- `verilator --lint-only -Wall --top-module secure_asic_top OpenLane/secure_asic_top/src/*.v`
  → **0 error, 0 warning**
- `--top-module secure_soc_top RTL/*.v` → còn 3 `BLKLOOPINIT` + 1 `UNOPTFLAT`,
  **tất cả trong `ro_puf.v`**. Đây là giới hạn của Verilator với ring oscillator
  (vòng lặp tổ hợp) và gán non-blocking vào mảng trong for-loop — không phải lỗi
  thiết kế, và Quartus 25.1 biên dịch file này với 0 Error.

### 1.5 Kiểm tra tĩnh

- Parse toàn bộ file Python bằng `ast`: **0 lỗi cú pháp**.
- Parse `OpenLane/secure_asic_top/config.json` bằng JSON strict: **hợp lệ**, 22 key.
- `sync_rtl.py`: 8/8 file trong `OpenLane/secure_asic_top/src/` khớp
  **byte-for-byte** với `RTL/`.
- Khung tham chiếu Protocol V2 (tính lại độc lập, khớp `VALIDATION_v7.md`):
  - GET_ID: `A5010100C89D`
  - CHALLENGE payload `00112233445566778899AABBCCDDEEFF` → CRC `9174`
  - CHALLENGE payload `0F1E2D3C4B5A69788796A5B4C3D2E1F0` → CRC `5169`

---

## 2. Đã ĐỌC LẠI từ log trong ZIP (không chạy lại tool)

### 2.1 Quartus Prime 25.1 — `run` của người dùng

- Analysis & Synthesis: **Successful**, top = `secure_soc_top`
- Fitter: **Successful**, device 5CSXFC6D6F31C6
- **0 Error, 0 Critical Warning** trong `map/fit/sta/asm.qmsg`
- 6.566 / 41.910 ALM (16%), 8.441 register, 49 pin, 0 RAM, 0 DSP, 0 PLL
- Timing (worst corner Slow 1100mV 85C):
  setup **+7.271 ns**, hold **+0.304 ns**, TNS = 0.000 — **đóng timing**

### 2.2 OpenLane / OpenROAD — `runs/run_2`, SKY130A + sky130_fd_sc_hd

- `flow_status = flow completed`, tổng 34m52s
- DRC (Magic) = **0**, LVS = **0**, XOR (KLayout) = **0**, TritonRoute = **0**
- Short / MetSpc / OffGrid / MinHole / Other violations = **0**
- Die area 0.7569 mm², 23.280 cell sau synthesis, 89.763 cell tổng
- **STA signoff sau route — tất cả các góc đều đạt:**

| Log | wns | tns | worst slack (setup / hold) |
|---|---|---|---|
| `26-rcx_mcsta.min.log` | 0.00 | 0.00 | +1.84 / +0.10 |
| `28-rcx_mcsta.max.log` | 0.00 | 0.00 | +1.08 / +0.10 |
| `30-rcx_mcsta.nom.log` | 0.00 | 0.00 | +1.46 / +0.10 |
| `31-rcx_sta.log` | 0.00 | 0.00 | +10.92 / +0.31 |

### 2.3 ⚠️ Điểm dễ hiểu nhầm trong `metrics.csv`

Cột `wns = -27.02` / `tns = -86022.05` trong `reports/metrics.csv` lấy từ
`logs/synthesis/2-sta.log` — **STA trước place, dùng wireload model**, không phải
kết quả signoff. Bảng ở mục 2.2 mới là số thật. Báo cáo dự thi phải trích log
signoff, không trích cột này.

### 2.4 Vấn đề còn tồn đọng trong `run_2`

`pin_antenna_violations = 129`, `net_antenna_violations = 86`.
`config.json` v7.1 đã bổ sung cấu hình chèn diode để xử lý — **cần chạy lại
OpenLane** và kiểm tra 2 con số này trong `metrics.csv` mới.

---

## 3. CHƯA được kiểm chứng trong workspace này

Workspace review không có Quartus, Yosys, OpenROAD, OpenLane hay phần cứng thật.
Do đó bản review này **KHÔNG** khẳng định:

- Quartus 25.1 biên dịch lại thành công **sau các sửa đổi RTL của v7.1**
  (thay đổi rất nhỏ và an toàn, nhưng vẫn phải chạy lại để xác nhận);
- OpenLane chạy lại thành công với `config.json` / `constraints.sdc` mới;
- số antenna sau khi bật chèn diode;
- ảnh hưởng của các ràng buộc SDC mới lên timing signoff (khả năng cao slack sẽ
  **giảm** vì trước đó đường I/O hoàn toàn không bị ràng buộc — đây là kết quả
  **đúng hơn**, không phải hồi quy);
- kết quả test UART trên board thật (`test/test_uart_challenge.py`);
- tính đúng của GDS cuối.

---

## 4. Việc cần làm tiếp trên máy có tool

1. `cd Quartus && quartus_sh --flash TrueChip.qpf` (hoặc compile trong GUI) —
   xác nhận vẫn 0 Error, và cụ thể là Warning 21074/15610 về `KEY[1]` đã biến mất.
2. `cd OpenLane/secure_asic_top && flow.tcl -design .` — chạy lại với config mới.
3. Đối chiếu `reports/metrics.csv` mới: `pin_antenna_violations` và
   `net_antenna_violations` phải giảm mạnh hoặc về 0.
4. Kiểm tra lại STA signoff sau khi có ràng buộc I/O — nếu slack âm, tăng
   `CLOCK_PERIOD` hoặc nới `input_budget`/`output_budget` trong `constraints.sdc`
   và ghi rõ lý do trong báo cáo.
5. Chạy `test/test_uart_challenge.py` trên board với `--secret-key D56DB0F67612790CE56147A44F67AF6F`
   (nếu dùng `LAYOUT_DEVICE_SEED` mặc định) — lưu ý board FPGA dùng RO-PUF thật
   nên `diversified_key` sẽ khác; dùng `--master-key` + `--device-id` đo được.
6. Bỏ log/report mới nhất vào ZIP kế tiếp và coi **chính các log đó** là nguồn sự thật.
