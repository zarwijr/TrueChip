# TrueChip

TrueChip là nguyên mẫu xác thực phần cứng dùng FPGA, UART và AES-128. Dự án
chứng minh một thiết bị có thể tự nhận dạng, trả lời thử thách ngẫu nhiên và
được verification server kiểm tra là thiết bị hợp lệ hay không.

> **Trạng thái:** prototype phục vụ nghiên cứu và cuộc thi. RO-PUF hiện là
> proof-of-concept; chưa nên được xem là cơ chế tạo khóa thương mại hoàn chỉnh.

## 1. TrueChip hoạt động như thế nào?

```text
PC ── GET_ID ───────────────► FPGA
PC ◄──────── UID công khai ── FPGA
PC ── nonce + CHALLENGE ───► FPGA
PC ◄──────── AES response ─── FPGA
PC ── UID/nonce/response ───► Verification server
PC ◄──────── AUTHENTIC/FAKE ─ Server
```

Luồng xác thực hiện tại:

1. Máy tính gửi khung Protocol V2 qua UART.
2. FPGA trả về UID 128-bit công khai.
3. Máy tính tạo nonce 128-bit mới cho mỗi phiên.
4. FPGA tạo AES response từ nonce, UID và khóa nội bộ.
5. Server tính lại response và trả về kết quả cùng metadata của chip.

Công thức prototype:

```text
diversified_key = AES-128(master_key, puf_id)
response        = AES-128(diversified_key, nonce XOR UID)
```

Giao tiếp dùng UART `115200 baud, 8N1`. NFC/RFID là hướng phát triển tương
lai, chưa phải chức năng của phiên bản hiện tại.

## 2. Các thành phần chính

```text
TrueChip/
├── RTL/                         # AES, UART, Protocol V2, auth FSM, RO-PUF
├── Quartus/                     # Project và ràng buộc FPGA Intel
├── Simulation/                  # Testbench và RTL regression
├── OpenLane/secure_asic_top/    # Digital hardening flow trên SKY130
├── secure_chip_web/
│   ├── index.html               # Web Serial kiểm tra UART online
│   ├── client/chip_tester.py    # Python tester qua COM/UART
│   ├── common/                  # Protocol và AES helper dùng chung
│   ├── server/mock_server.py    # Flask/PostgreSQL verification server
│   ├── enrollment_service.py   # Logic ghi danh dùng chung
│   ├── admin_gui.py             # GUI ghi danh local
│   ├── factory_tool.py          # CLI ghi danh/re-provision dự phòng
│   └── exe/                     # Script build TrueChipEnrollment.exe
├── test/                        # Kiểm thử UART trên board thật
├── evidence/                    # Ảnh, log và report chọn lọc để nộp
└── docs/                        # Tài liệu kỹ thuật
```

## 3. Bắt đầu nhanh

Đọc [Hướng dẫn sử dụng](TrueChip/HUONG_DAN_SU_DUNG.md) để biết cách:

- clone và cài thư viện;
- nạp firmware FPGA bằng Quartus Programmer;
- mở SignalTap và đọc `diversified_key`;
- chạy website UART hoặc Python tester;
- ghi danh chip bằng GUI/EXE;
- kiểm tra RTL và OpenLane;
- xử lý lỗi COM/UART.

Tài liệu kỹ thuật chi tiết: [TrueChip/readme.md](TrueChip/readme.md).

## 4. Web online kiểm tra UART

Mở bằng Chrome hoặc Edge:

<https://zarwijr.github.io/TrueChip/>

Website sử dụng Web Serial API để truy cập cổng COM trên chính máy đang mở
trình duyệt. Server cloud không thể tự truy cập COM3 từ xa.

Các bước cơ bản:

1. Đóng Python tester và các Serial Monitor khác.
2. Kết nối đúng TX, RX và GND của USB-UART.
3. Nhấn **Kết Nối Cổng COM**.
4. Chọn đúng cổng, ví dụ `COM3`.
5. Nhấn **Quét Xác Thực Chip**.
6. Kiểm tra UID, nonce, AES response và kết quả `AUTHENTIC`.

Website không cần `admin_config.json` và không có quyền ghi database.

## 5. Ghi danh chip bằng GUI hoặc factory tool

GUI desktop là giao diện khuyến nghị cho máy quản trị:

```text
secure_chip_web/exe/dist/TrueChipEnrollment.exe
```

Nếu chưa build EXE, chạy source:

```powershell
python .\secure_chip_web\admin_gui.py
```

GUI dùng chung `enrollment_service.py` với `factory_tool.py`:

- **Enroll chip mới:** chỉ tạo UID chưa tồn tại.
- **Cập nhật key chip cũ:** re-provision có xác nhận, dùng khi FPGA đã đổi key.

Database lưu UID và diversified key thực tế mà FPGA dùng. Trong database,
diversified key nằm ở cột `secret_key`.

Không tạo bản ghi mới mỗi lần nhấn `KEY[0]`. Nếu UID giữ nguyên nhưng
diversified key thay đổi, phải re-provision đúng UID.

## 6. UID, puf_id và chip ROM prototype

Phiên bản prototype hiện tại dùng giá trị gán cứng trong `RTL/chip_rom.v`:

```verilog
chip_uid   = 128'h2583_2583_2583_2583_2583_2583_2583_2583;
master_key = 128'h1234_1234_1234_1234_1234_1234_1234_1234;
```

- `chip_uid`: UID công khai dùng để nhận dạng chip.
- `master_key`: khóa gốc prototype dùng trong KDF.
- `puf_id`: giá trị RO-PUF nội bộ.
- `diversified_key`: khóa được tạo từ `master_key` và `puf_id`, sau đó dùng để
  tạo AES response.

Nếu sửa UID, `master_key` hoặc logic PUF:

1. Compile lại Quartus.
2. Nạp `.sof` mới.
3. Dùng SignalTap đọc lại diversified key.
4. Enroll hoặc re-provision database.
5. Chạy lại website để kiểm tra `AUTHENTIC`.

Không sửa key trong database một cách độc lập rồi kỳ vọng FPGA vẫn xác thực.

## 7. ASIC/OpenLane và bằng chứng nộp bài

Không cần đưa toàn bộ `OpenLane/**/runs/**/tmp` hoặc các kết quả trung gian lên
GitHub. Nên giữ:

- RTL, constraints và OpenLane configuration;
- report DRC, LVS, KLayout DRC, STA, antenna và CVC;
- ảnh layout toàn chip và ảnh detail;
- GDS final/signoff của đúng baseline;
- manifest SHA-256 và commit ID tương ứng.

Các file sinh tự động như `tmp/`, log rác, `__pycache__/`, `build/` và `dist/`
được loại bằng `.gitignore`. Nếu GDS quá lớn, dùng GitHub Release hoặc Git LFS.

Khi báo cáo OpenLane, phải ghi đúng run đã chọn. Nếu chọn `run_5`, mọi ảnh,
report và slide phải thống nhất là `run_5`. CVC/ERC gặp lỗi model/PDK phải được
ghi trung thực là lỗi công cụ/model-resolution, không ghi là CVC/ERC đã pass.

## 8. Phạm vi và giới hạn bảo mật

- FPGA authentication prototype dùng AES-128 và UART.
- Server xác thực UID, response và nonce đã sử dụng; nonce lặp bị từ chối.
- Không nên tuyên bố rate-limit/lockout đã hoàn thiện nếu chưa có kiểm thử và
  bằng chứng tương ứng trong phiên bản code đang nộp.
- RO-PUF hiện có biến thiên đo được; kết quả khoảng 12,23% bit thay đổi cần
  được trình bày trung thực.
- Trước khi dùng PUF làm khóa sản phẩm cần enrollment, ECC/fuzzy extractor và
  đánh giá ổn định theo nhiệt độ/điện áp.
- Chi phí thương mại dưới 1 USD/chip là mục tiêu dài hạn, chưa phải kết quả đã
  được chứng minh bởi RTL hoặc layout hiện tại.

## 9. Bảo mật repository

Không commit hoặc public:

```text
admin_config.json
.env
database URL
database password
secret key
GitHub token
```

`admin_config.json` chỉ dùng trên máy quản trị và phải được bỏ qua bởi
`.gitignore`. Nếu credential từng xuất hiện trong commit, issue hoặc chat công
khai, cần rotate credential trước khi dùng thật.

## 10. License

Xem license và các tài liệu kỹ thuật trong repository.
