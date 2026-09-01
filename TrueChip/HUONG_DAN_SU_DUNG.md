# Hướng dẫn sử dụng TrueChip

Tài liệu này hướng dẫn clone project, chạy demo với FPGA thật, xác thực qua
UART và ghi danh chip bằng công cụ quản trị desktop.

## 1. Phạm vi hiện tại

TrueChip là prototype xác thực phần cứng gồm FPGA, UART, AES-128 và
verification server.

Luồng xác thực:

```text
PC gửi GET_ID → FPGA trả UID
PC tạo nonce mới → gửi CHALLENGE
FPGA trả AES response
PC gửi UID + nonce + response lên server
Server tính lại response → AUTHENTIC hoặc FAKE
```

Website online chỉ dùng để kết nối UART và kiểm tra chip. Công cụ ghi danh
chip là GUI desktop hoặc `factory_tool.py`, không phải website public.

## 2. Yêu cầu

- Windows 10/11 hoặc Linux.
- Python 3.10 trở lên.
- Chrome hoặc Edge nếu dùng Web Serial.
- FPGA đã nạp đúng firmware TrueChip.
- USB-UART đã nhận driver; ví dụ `COM3` trên Windows.
- UART: `115200 baud, 8N1`.
- Verification server đang hoạt động tại:
  `https://truechip-server.onrender.com/verify`

Web online là một file HTML tĩnh, không cần Node.js.

## 3. Cấu trúc thư mục

Các lệnh dưới đây chạy từ thư mục project bên trong repository:

```text
C:\GitHub\TrueChip\TrueChip\
├── RTL\
├── Quartus\
├── Simulation\
├── OpenLane\secure_asic_top\
├── test\
└── secure_chip_web\
    ├── index.html                    # UART online, giữ nguyên file này
    ├── client\chip_tester.py        # Python UART tester
    ├── common\secure_chip_common.py
    ├── server\mock_server.py        # server local tùy chọn
    ├── admin_gui.py                  # GUI ghi danh local
    ├── enrollment_service.py         # logic dùng chung GUI/factory
    ├── factory_tool.py               # CLI ghi danh local
    ├── exe\                         # script build TrueChipEnrollment.exe
    └── requirements.txt
```

## 4. Cài thư viện Python

Trên Windows:

```powershell
cd C:\GitHub\TrueChip\TrueChip\secure_chip_web
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

Nếu PowerShell chặn activate script, chạy trực tiếp:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Trên Linux/macOS, thay `python` bằng `python3` và dùng `.venv/bin/python`.

## 5. Ý nghĩa các giá trị của chip

Database cần lưu:

| Giá trị | Ý nghĩa | Có nhập vào database không? |
|---|---|---:|
| UID / `chip_uid` | Mã nhận dạng công khai 128-bit, ví dụ `2583...` | Có |
| `puf_id` | Giá trị RO-PUF nội bộ dùng trong KDF | Không nhập trực tiếp |
| `master_key` | Khóa gốc prototype trong FPGA | Không nhập trực tiếp |
| `diversified_key` | Khóa thực tế FPGA dùng tạo AES response | Có, lưu ở cột `secret_key` |
| Nonce | Challenge mới cho từng phiên xác thực | Không ghi danh như thuộc tính chip |

Với kiến trúc hiện tại:

```text
diversified_key = AES-128(master_key, puf_id)
response        = AES-128(diversified_key, nonce XOR UID)
```

Vì vậy, nếu FPGA đổi `diversified_key` nhưng database chưa cập nhật, server sẽ
trả `Response không khớp`. Không tạo bản ghi mới cho mỗi lần nhấn `KEY[0]`.

## 6. Ghi danh chip bằng GUI desktop

GUI là cách khuyến nghị cho máy quản trị.

Chạy từ source:

```powershell
cd C:\GitHub\TrueChip\TrueChip
python .\secure_chip_web\admin_gui.py
```

Trong GUI:

1. Nhấn **Cấu hình URL** và nhập External PostgreSQL URL được cấp riêng.
2. Nhấn **Thử kết nối**.
3. Nhập UID công khai của FPGA.
4. Nhập `Diversified key` hiện tại của FPGA.
5. Nhập Product, Manufacturer và Pack date.
6. Chọn **Enroll chip mới** nếu UID chưa tồn tại.
7. Nếu UID đã tồn tại, chọn **Cập nhật key chip cũ** và xác nhận ghi đè.

GUI không hiển thị secret key trong danh sách chip. `admin_config.json` được
lưu cục bộ để lần sau không phải nhập lại URL.

## 7. Tạo và chạy file EXE

Build trên Windows:

```powershell
cd C:\GitHub\TrueChip\TrueChip\secure_chip_web\exe
powershell -ExecutionPolicy Bypass -File .\build_admin_exe.ps1
```

File tạo ra:

```text
C:\GitHub\TrueChip\TrueChip\secure_chip_web\exe\dist\TrueChipEnrollment.exe
```

Sau đó nhấp đúp `TrueChipEnrollment.exe` để mở GUI.

EXE chỉ là giao diện desktop thuận tiện hơn; nó vẫn cần Internet nếu database
nằm trên Render. EXE không thay thế website UART và không tự tạo database mới.

## 8. Ghi danh bằng factory_tool.py

Chỉ dùng khi cần CLI hoặc kiểm thử máy quản trị:

```powershell
cd C:\GitHub\TrueChip\TrueChip\secure_chip_web
$env:TRUECHIP_DATABASE_URL = "postgresql://<user>:<password>@<host>/<database>"
python .\factory_tool.py
```

Chọn:

- `1`: Enroll chip mới, không ghi đè UID đã có.
- `2`: Re-provision, cập nhật key cho UID đã tồn tại.

Không ghi URL thật vào source code, README, ZIP public hoặc GitHub.

## 9. Kiểm tra bằng Python tester

Đóng mọi chương trình khác đang dùng COM3:

```powershell
cd C:\GitHub\TrueChip\TrueChip\secure_chip_web
python .\client\chip_tester.py `
  --port COM3 `
  --server-url https://truechip-server.onrender.com/verify
```

Tester sẽ mở UART, gửi `GET_ID`, tạo nonce, gửi `CHALLENGE`, nhận AES response
và gửi kết quả lên verification server.

Quét nhiều lần:

```powershell
python .\client\chip_tester.py --port COM3 --repeat 3
```

Không chạy Python tester và website trên cùng một COM cùng lúc.

## 10. Kiểm tra bằng website online

Mở bằng Chrome hoặc Edge:

```text
https://zarwijr.github.io/TrueChip/
```

1. Đóng Python tester.
2. Chờ 1–2 giây để Windows nhả COM.
3. Nhấn **Kết Nối Cổng COM**.
4. Chọn đúng cổng, ví dụ `COM3`.
5. Nhấn **Quét Xác Thực Chip**.
6. Kiểm tra UID, nonce, AES response và kết quả `AUTHENTIC`.

Website không cần `admin_config.json`. Website chỉ gửi request verify; nó
không có quyền ghi database.

## 11. Chuyển giữa Python tester và website

Một cổng COM chỉ được mở bởi một chương trình.

Từ Python sang website:

1. Đợi Python kết thúc và trả dấu nhắc PowerShell.
2. Đóng cửa sổ Python nếu cần.
3. Chờ 1–2 giây.
4. Mở website và kết nối lại COM.

Từ website sang Python:

1. Nhấn **Ngắt** trên website.
2. Chờ thông báo đã ngắt.
3. Chạy lại Python tester.

## 12. Server local tùy chọn

Không cần chạy server local khi dùng endpoint Render. Chỉ chạy local để kiểm
thử riêng:

```powershell
cd C:\GitHub\TrueChip\TrueChip\secure_chip_web
$env:DATABASE_URL = "postgresql://<user>:<password>@<host>/<database>"
python .\server\mock_server.py
```

Tester local:

```powershell
python .\client\chip_tester.py `
  --port COM3 `
  --server-url http://127.0.0.1:5000/verify
```

## 13. RTL và ASIC/OpenLane

RTL regression:

```bash
cd TrueChip
bash Simulation/run_regression.sh
```

Kiểm tra signoff của baseline đã chọn:

```bash
cd OpenLane/secure_asic_top
python3 check_signoff.py runs/run_5
```

Nếu chọn `run_5`, mọi report, ảnh layout và slide phải ghi rõ `run_5`. CVC/ERC
gặp lỗi model như `missing parameter: l in l/w*48` phải được ghi là lỗi
tool/PDK model-resolution; không ghi CVC/ERC đã pass.

## 14. Quy tắc commit results và tmp

Không commit toàn bộ `OpenLane/**/runs/**/tmp/`, log trung gian, `__pycache__`,
PyInstaller `build/` hoặc `dist/`.

Nên giữ:

- RTL, constraints và OpenLane config.
- Report DRC, LVS, KLayout DRC, STA, antenna và CVC log.
- Ảnh layout toàn chip và ảnh detail.
- GDS final/signoff của đúng baseline.
- `SIGNOFF_SUMMARY_run_5.md` và manifest SHA-256.

Nếu GDS quá lớn, đưa vào GitHub Release hoặc Git LFS thay vì commit trực tiếp.

## 15. Xử lý lỗi nhanh

| Hiện tượng | Cách xử lý |
|---|---|
| Không thấy COM3 | Kiểm tra Device Manager, cáp, driver và rút/cắm lại board. |
| `Failed to open serial port` | Đóng tester, Serial Monitor và tab web khác; chờ 1–2 giây. |
| Timeout GET_ID | Kiểm tra TX/RX có bị nối ngược, GND chung và bitstream đúng. |
| UID có nhưng `FAKE` | Kiểm tra database đang lưu đúng diversified key của FPGA hiện tại. |
| UID trùng khi enroll | Dùng `Cập nhật key chip cũ` hoặc factory mode `2`; không enroll lặp. |
| Server timeout | Kiểm tra Render có đang khởi động và endpoint có hoạt động. |
| Web hiển thị bản cũ | Chờ GitHub Actions hoàn tất rồi nhấn `Ctrl+F5`. |
| UID toàn số 0 | Kiểm tra firmware/RO-PUF và không ghi danh UID 0 cho demo. |

## 16. An toàn và giới hạn

- Không commit `admin_config.json`, `.env`, database URL, mật khẩu, secret key
  hoặc GitHub token.
- Chỉ cấp database URL cho máy quản trị được tin cậy.
- Người dùng demo chỉ cần website hoặc Python tester, không cần quyền ghi DB.
- Database URL đã từng xuất hiện trong quá trình làm việc; cần rotate credential
  trước khi dùng thật.
- RO-PUF hiện là proof-of-concept. Với khoảng 12,23% bit thay đổi, chưa nên
  dùng trực tiếp làm khóa nếu chưa có enrollment, ECC hoặc fuzzy extractor.
- Chi phí thương mại và mức độ chống nhân bản tuyệt đối chưa được chứng minh
  bởi prototype hiện tại.
