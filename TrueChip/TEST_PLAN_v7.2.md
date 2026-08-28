# TrueChip v7.2 — Kịch bản test & checklist ảnh/video cho nhóm

Tài liệu này dùng cho buổi test cuối và buổi trình bày với nhóm.

> **ĐỌC TRƯỚC:** phải làm xong **Giai đoạn 0** rồi mới quay demo. Sau khi sửa
> lỗi RO-PUF, khóa trên board đã đổi — nếu chưa cấp phát lại database thì
> server sẽ trả `FAKE` ngay giữa buổi demo.

---

## Giai đoạn 0 — Bắt buộc làm trước (khoảng 1–2 giờ)

| # | Việc | Lệnh / thao tác | Tiêu chí đạt |
|---|---|---|---|
| 0.1 | Regression RTL | `bash Simulation/run_regression.sh` | `8 passed, 0 failed`, exit 0 |
| 0.2 | Compile Quartus | Mở `Quartus/TrueChip.qpf`, Compile Design | 0 Error, 0 Critical Warning. Kiểm tra Warning 21074/15610 về `KEY[1]` đã biến mất |
| 0.3 | Chạy OpenLane `run_5` | `flow.tcl -design .` trong `OpenLane/secure_asic_top` | `flow completed` |
| 0.4 | Chấm điểm signoff | `python3 check_signoff.py runs/run_5` | Không còn BLOCKER |
| 0.5 | KLayout DRC (nếu 0.4 vẫn báo NOT RUN) | `./run_klayout_drc.sh runs/run_5` | `RESULT: PASS` |
| 0.6 | Nạp bitstream mới lên board | Quartus Programmer | LED nguồn sáng, `key_ready` (GPIO[2]) lên mức cao |
| 0.7 | **Đọc lại diversified_key mới** | xem mục 0.7 bên dưới | Có 32 ký tự hex |
| 0.8 | **Cấp phát lại DB** | `python3 secure_chip_web/factory_tool.py` | `[THÀNH CÔNG] Đã ghi danh chip ...` |
| 0.9 | Thử một lần quét thật | `python3 secure_chip_web/client/chip_tester.py --port COM3` | `KẾT QUẢ: AUTHENTIC / HÀNG THẬT` |

### 0.7 — Lấy diversified_key mới

`puf_id` giờ là giá trị đo thật từ silicon, nên **mỗi board một khác**. Cách
lấy trong môi trường lab:

1. Dùng SignalTap trên tín hiệu `u_ro_puf.puf_id` (128 bit) sau khi
   `puf_valid` lên cao, ghi lại giá trị.
2. Tính khóa:
   ```bash
   python3 - <<'PY'
   from Crypto.Cipher import AES
   master = bytes.fromhex("12341234123412341234123412341234")
   puf_id = bytes.fromhex("<128 bit doc duoc tu SignalTap>")
   print(AES.new(master, AES.MODE_ECB).encrypt(puf_id).hex().upper())
   PY
   ```
3. Hoặc để script tự tính:
   ```bash
   python3 test/test_uart_challenge.py --port COM3 \
       --master-key 12341234123412341234123412341234 \
       --device-id <puf_id_hex>
   ```

> **Nếu nhóm chưa kịp làm SignalTap:** vẫn có thể demo bằng cách tạm dùng
> `secure_asic_top` (dùng `LAYOUT_DEVICE_SEED` hằng số, khóa cố định
> `D56DB0F67612790CE56147A44F67AF6F`). Nhưng khi đó **phải nói rõ** đây là
> nhánh ASIC không có PUF, đừng trình bày như bằng chứng per-device uniqueness.

---

## Giai đoạn 1 — Bộ mẫu test (7 kịch bản)

M��i kịch bản có: mục đích, thao tác, kết quả kỳ vọng, và ảnh cần chụp.

### TC-01 — Xác thực hàng thật (happy path)

- **Mục đích:** chứng minh luồng đầy đủ chip → UART → server → kết quả
- **Lệnh:** `python3 secure_chip_web/client/chip_tester.py --port COM3`
- **Kỳ vọng:**
  ```
  KẾT QUẢ: AUTHENTIC / HÀNG THẬT
  Sản phẩm      : ...
  Nhà sản xuất  : ...
  ```
- **📸 Ảnh:** toàn màn hình terminal + board trong khung hình

### TC-02 — Chống replay ở tầng server

- **Mục đích:** cùng một nonce dùng lại lần hai bị server chặn
- **Thao tác:** chạy TC-01 với `--json`, ghi lại `uid`/`nonce`/`response`,
  rồi POST lại đúng bộ đó:
  ```bash
  curl -X POST https://truechip-server.onrender.com/verify \
    -H "Content-Type: application/json" \
    -d '{"uid":"...","nonce":"...","response":"..."}'
  ```
- **Kỳ vọng:** `"authentic": false`, `"reason": "Nonce đã được sử dụng — nghi ngờ replay attack"`
- **📸 Ảnh:** hai lần gọi cạnh nhau — lần 1 AUTHENTIC, lần 2 bị chặn

### TC-03 — Chống replay ở tầng phần cứng

- **Mục đích:** chip tự nhớ 8 nonce gần nhất, không cần server
- **Lệnh:**
  ```bash
  python3 test/test_uart_challenge.py --port COM3 --secret-key <KEY>
  ```
- **Kỳ vọng:**
  ```
  [PASS] GET_ID: ...
  [PASS] Fresh CHALLENGE: ...
  [PASS] Immediate fresh CHALLENGE -> STATUS_RATE_LIMIT
  [PASS] Old nonce after cooldown -> STATUS_REPLAY
  [PASS] New CHALLENGE after protections: ...
  ```
- **📸 Ảnh:** toàn bộ output

### TC-04 — Hàng giả: UID không có trong database

- **Mục đích:** UID lạ bị từ chối
- **Lệnh:**
  ```bash
  curl -X POST <server>/verify -H "Content-Type: application/json" \
    -d '{"uid":"DEADBEEFDEADBEEFDEADBEEFDEADBEEF","nonce":"00112233445566778899AABBCCDDEEFF","response":"00000000000000000000000000000000"}'
  ```
- **Kỳ vọng:** `"reason": "UID không tồn tại trong database"`
- **📸 Ảnh:** output JSON

### TC-05 — Hàng giả: sao chép UID nhưng không có khóa

- **Mục đích:** đây là **kịch bản chống hàng giả quan trọng nhất** — kẻ làm
  giả đọc được UID (công khai) nhưng không thể tạo response đúng
- **Lệnh:** `python3 secure_chip_web/client/demo_scenarios.py --port COM3`
  (kịch bản 3 tự lật 1 bit trong response)
- **Kỳ vọng:** `"reason": "Response không khớp — chip giả hoặc secret key sai"`
- **📸 Ảnh:** output — nhấn mạnh **chỉ lật 1 bit** cũng bị bắt

### TC-06 — Khóa vĩnh viễn (lockout)

- **Mục đích:** brute-force qua UART bị chặn cứng, chỉ mở được bằng power-cycle
- **Lệnh:** `python3 test/test_uart_challenge.py --port COM3 --secret-key <KEY> --test-lockout`
- **Kỳ vọng:** 4 lần `RATE_LIMIT`, lần thứ 5 `LOCKED`, sau đó chip câm cho tới khi nhấn reset
- **⚠️ Làm cuối cùng** — chip sẽ khóa cho tới khi power-cycle
- **📸 Ảnh:** output + LED/GPIO[3] báo lockout
- **🎥 Video:** đoạn này rất hợp để quay — nhấn KEY[0] để "hồi sinh" chip

### TC-07 — Khung sai CRC bị loại im lặng

- **Mục đích:** chứng minh tính toàn vẹn khung truyền
- **Lệnh:**
  ```bash
  python3 - <<'PY'
  import serial, time
  s = serial.Serial("COM3", 115200, timeout=2)
  time.sleep(1.5); s.reset_input_buffer()
  s.write(bytes([0xA5,0x01,0x01,0x00,0xC8,0x9E]))   # CRC sai 1 bit
  print("Chip tra ve:", s.read(4) or b"(khong gi ca - dung nhu ky vong)")
  PY
  ```
- **Kỳ vọng:** không nhận được byte nào
- **📸 Ảnh:** output

---

## Giai đoạn 2 — Checklist ảnh cần chụp

### Nhóm A — Mô phỏng & verification

| # | Ảnh | Lấy từ đâu |
|---|---|---|
| A1 | Regression 8/8 PASS | `bash Simulation/run_regression.sh` |
| A2 | Vector AES khớp chuẩn | phần `tb_aes128` trong output A1 |
| A3 | Full-chip test 9 điểm | phần `secure_asic_top` trong output A1 |
| A4 | **RO-PUF: trước vs sau khi sửa** | hai output cạnh nhau — FAIL/PASS |
| A5 | Waveform GTKWave: khung GET_ID | `gtkwave secure_asic_top_tb.vcd` |
| A6 | Waveform: `uart_rx_i` → `uart_tx_o` một chu kỳ CHALLENGE | cùng file VCD |
| A7 | Waveform: `ro_enable`, `cnt_clr_n`, `ro_cnt[0]` | `gtkwave ro_puf_tb.vcd` — cho thấy counter **giữ** giá trị khi ring dừng |

> **A4 và A7 là hai ảnh có sức thuyết phục cao nhất** với ban giám khảo: chúng
> chứng minh nhóm tự tìm ra một lỗi chức năng thật và sửa được, chứ không chỉ
> chạy tool cho ra kết quả xanh.

### Nhóm B — FPGA (Quartus)

| # | Ảnh |
|---|---|
| B1 | Compilation Report: Successful, 0 Error / 0 Critical Warning |
| B2 | Flow Summary: ALM 16%, 8.441 register, 49 pin |
| B3 | TimeQuest: setup slack +7.271 ns, hold +0.304 ns @ 50 MHz |
| B4 | Chip Planner / Technology Map Viewer: 256 vòng RO còn nguyên vẹn |
| B5 | SignalTap: `puf_valid` lên cao và `puf_id` **khác 0** |

> B5 là bằng chứng trực tiếp cho việc sửa lỗi P0.

### Nhóm C — ASIC (OpenLane / SKY130)

| # | Ảnh |
|---|---|
| C1 | **Scorecard `check_signoff.py`** — ảnh tổng quan tốt nhất, một khung là đủ |
| C2 | Layout GDS mở trong KLayout (toàn cảnh) |
| C3 | Layout phóng to: standard cell + PDN |
| C4 | Magic DRC: 0 |
| C5 | Netgen LVS: 0 error |
| C6 | KLayout DRC: 0 (từ `run_klayout_drc.sh`) |
| C7 | KLayout XOR: 0 |
| C8 | STA signoff 4 góc: `wns 0.00 / tns 0.00` |
| C9 | Bản đồ IR drop |
| C10 | `metrics.csv`: die area, cell count, antenna |

### Nhóm D — Hệ thống & demo

| # | Ảnh |
|---|---|
| D1 | Board FPGA + cáp UART, toàn cảnh bàn demo |
| D2 | TC-01 AUTHENTIC |
| D3 | TC-05 hàng giả bị bắt |
| D4 | TC-06 lockout |
| D5 | Sơ đồ khối hệ thống (vẽ từ README mục 6) |

---

## Giai đoạn 3 — Kịch bản video demo (khoảng 3 phút)

| Thời lượng | Nội dung | Lời thoại gợi ý |
|---|---|---|
| 0:00–0:20 | Toàn cảnh board + máy tính | "Đây là TrueChip — chip xác thực chống hàng giả, giao tiếp UART, lõi AES-128 phần cứng." |
| 0:20–0:50 | TC-01 quét hàng thật | "Máy chủ gửi nonce ngẫu nhiên, chip trả về AES của nonce XOR UID bằng khóa riêng của nó. Máy chủ tính lại độc lập." |
| 0:50–1:20 | TC-05 hàng giả | "Kẻ làm giả đọc được UID vì UID là công khai. Nhưng không có khóa thì không tạo được response — chỉ sai một bit là bị bắt." |
| 1:20–1:50 | TC-03 replay + rate limit | "Chip nhớ 8 nonce gần nhất ngay trong phần cứng, không cần máy chủ." |
| 1:50–2:20 | TC-06 lockout + power-cycle | "Sau 5 lần bị từ chối liên tiếp, chip tự khóa. Không có lệnh phần mềm nào mở được — bắt buộc phải chạm tay vào thiết bị." |
| 2:20–2:50 | Layout SKY130 + scorecard | "Phần lõi số đã được hardening xuống GDS trên SKY130: DRC, LVS, XOR đều sạch, timing đóng ở 50 MHz." |
| 2:50–3:00 | Kết | Nêu hướng NFC/RFID tương lai |

**Lưu ý quay:**

- Quay **một lượt liền mạch**, đừng cắt giữa lúc gõ lệnh — cắt ghép làm giảm
  độ tin cậy.
- Để terminal chữ to (≥ 16pt), nền tối.
- TC-06 quay **cuối cùng**.
- Chuẩn bị sẵn một board thứ hai chưa cấp phát để minh họa "hàng giả" trực
  quan hơn (nếu có).

---

## Giai đoạn 4 — Những điều PHẢI nói thật trong báo cáo

Nói trước những hạn chế này sẽ được đánh giá cao hơn nhiều so với việc bị
giám khảo phát hiện.

1. **`master_key` là hằng số trong ROM** — chỉ hợp lệ cho prototype. Bản
   thương mại cần OTP/eFuse hoặc quy trình cấp phát có root-of-trust.
2. **RO-PUF chưa được đặc trưng hóa.** Testbench chứng minh RTL **đo và giữ
   đúng giá trị counter**. Nó **không** chứng minh entropy, uniqueness hay độ
   ổn định theo nhiệt độ/điện áp — muốn khẳng định phải đo trên nhiều board thật.
3. **Layout ASIC không có RO-PUF.** `secure_asic_top` dùng seed hằng số
   `LAYOUT_DEVICE_SEED`. Phải gọi đúng tên: *"hardening lõi bảo mật số
   AES/UART"*, không phải *"chip PUF hoàn chỉnh"*.
4. **Response chưa có CRC.** Khung request có CRC16-CCITT, khung response thì
   chưa. Đây là hạng mục nâng cấp tương lai đã biết.
5. **Chưa có pad ring**, nên IR-drop dùng vị trí nguồn giả định checkerboard.
6. **Đừng trích cột `wns` trong `metrics.csv`** — đó là STA trước place. Trích
   `logs/signoff/*rcx*sta*.log`.
7. **Mục tiêu giá dưới 1 USD/chip là mục tiêu kinh doanh**, không phải kết quả
   đã chứng minh từ layout hiện tại.
8. Nếu `check_signoff.py` còn warning: **ghi rõ con số và lý do**, đừng giấu.

---

## Phụ lục — Xử lý sự cố nhanh trong buổi demo

| Triệu chứng | Nguyên nhân thường gặp | Xử lý |
|---|---|---|
| `FAKE / Response không khớp` | Chưa cấp phát lại DB sau khi sửa RO-PUF | Chạy lại bước 0.7–0.8 |
| `Timeout while reading ... header` | Sai cổng COM, hoặc chip đang LOCKED | Kiểm tra `--port`; nhấn KEY[0] để reset |
| Chip không trả lời gì | Đã chạy TC-06 trước đó | Power-cycle board |
| `STATUS_RATE_LIMIT` liên tục | Gửi challenge quá nhanh | Chờ ~10 ms giữa hai lần |
| Server trả 503 | Database Render đang ngủ | Gọi `/` một lần để đánh thức, chờ ~30 giây |
| `key_ready` (GPIO[2]) không lên | KDF chưa xong hoặc PUF treo | Kiểm tra `puf_valid` bằng SignalTap |
