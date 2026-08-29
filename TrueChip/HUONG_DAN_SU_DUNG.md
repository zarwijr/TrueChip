# Hướng dẫn sử dụng TrueChip

Tài liệu này dành cho việc chạy demo với FPGA thật, cổng UART/COM3, web
frontend và verification server.

## 1. Yêu cầu

- Windows 10/11 hoặc Linux.
- Python 3.10 trở lên.
- Chrome hoặc Edge nếu dùng web Serial.
- Board FPGA đã nạp firmware TrueChip và xuất UART.
- Cáp USB-UART và driver đã nhận board, ví dụ `COM3` trên Windows.
- Verification server đang hoạt động tại:
  `https://truechip-server.onrender.com/verify`

Web online không cần Node.js vì frontend là một file HTML tĩnh.

## 2. Cấu trúc thư mục cần dùng

Các lệnh dưới đây chạy từ thư mục `TrueChip` bên trong repository:

```text
C:\GitHub\TrueChip\TrueChip\
├── secure_chip_web\
│   ├── client\chip_tester.py
│   ├── factory_tool.py
│   ├── server\mock_server.py
│   ├── common\secure_chip_common.py
│   ├── requirements.txt
│   └── index.html
├── RTL\
├── Quartus\
├── Simulation\
└── test\
```

Trên Linux/macOS, thay dấu `\` trong lệnh bằng `/`.

## 3. Cài thư viện Python

Mở PowerShell tại `C:\GitHub\TrueChip\TrueChip`:

```powershell
cd C:\GitHub\TrueChip\TrueChip\secure_chip_web
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

Nếu PowerShell chặn activate script, có thể chạy trực tiếp Python trong môi
trường ảo:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

## 4. Cấp phát chip vào cloud database

`factory_tool.py` cần biến môi trường `TRUECHIP_DATABASE_URL`. Không ghi URL
database hoặc mật khẩu trực tiếp vào source code, README hay GitHub.

Ví dụ PowerShell:

```powershell
$env:TRUECHIP_DATABASE_URL = "postgresql://<user>:<password>@<host>/<database>"
python factory_tool.py
```

Sau đó nhập:

- UID 32 ký tự hexadecimal của chip.
- Secret key 32 ký tự hexadecimal.
- Tên sản phẩm.

Tool sẽ tạo bảng `chips` nếu chưa có và ghi thông tin chip vào PostgreSQL.
Secret key phải trùng với khóa mà firmware FPGA sử dụng. Sau khi sửa RO-PUF
hoặc nạp firmware mới làm thay đổi khóa, phải cấp phát lại database trước khi
demo.

## 5. Kiểm tra bằng Python

Đảm bảo không có chương trình nào khác đang giữ COM3, sau đó chạy:

```powershell
cd C:\GitHub\TrueChip\TrueChip\secure_chip_web
python client\chip_tester.py `
  --port COM3 `
  --server-url https://truechip-server.onrender.com/verify
```

Tester sẽ:

1. Mở UART ở 115200 baud, 8N1.
2. Gửi `GET_ID` để đọc UID.
3. Sinh nonce mới cho mỗi lần quét.
4. Gửi `CHALLENGE` tới FPGA.
5. Gửi UID, nonce và AES response lên verification server.
6. In `AUTHENTIC / HÀNG THẬT` hoặc lý do không xác thực.

Có thể quét nhiều lần:

```powershell
python client\chip_tester.py --port COM3 --repeat 3
```

Server URL mặc định đã là Render URL ở trên. Có thể thay bằng biến môi trường:

```powershell
$env:SECURE_CHIP_VERIFY_URL = "https://truechip-server.onrender.com/verify"
python client\chip_tester.py --port COM3
```

## 6. Kiểm tra bằng web online

Mở [TrueChip Authenticator](https://zarwijr.github.io/TrueChip/) bằng Chrome
hoặc Edge.

1. Đóng Python tester và chờ khoảng 1-2 giây để Windows nhả COM3.
2. Nhấn **Kết Nối Cổng COM**.
3. Chọn đúng thiết bị UART, ví dụ `COM3`, rồi cấp quyền.
4. Nhấn **Quét Xác Thực Chip**.
5. Kiểm tra UID, sản phẩm, nhà sản xuất và kết quả xác thực.

Web đã có cơ chế thử kết nối lại khi COM vừa được Python nhả ra. Nếu lần đầu
không mở được cổng, chờ vài giây rồi thử lại. Mục **Debug kỹ thuật** trong
trang web giữ lại lỗi chi tiết để kiểm tra khi cần.

## 7. Quy tắc khi chuyển giữa Python và web

Một cổng COM chỉ nên được mở bởi một chương trình tại một thời điểm.

Khi chuyển từ Python sang web:

1. Đợi Python kết thúc hoàn toàn và trả lại dấu nhắc PowerShell.
2. Nếu cần, rút/cắm lại USB hoặc chờ driver ổn định.
3. Mở trang web và kết nối lại cổng.

Khi chuyển từ web sang Python:

1. Nhấn **Ngắt** trên web.
2. Chờ thông báo thiết bị đã ngắt.
3. Chạy lại lệnh Python.

Lỗi `Cannot read properties of null (reading 'open')` thường là phiên bản web
cũ hoặc chưa chọn/cấp quyền cho cổng. Lỗi `Failed to open serial port` thường
là COM3 vẫn đang bị Python, Serial Monitor hoặc cửa sổ trình duyệt khác giữ.

## 8. Chạy verification server cục bộ (tùy chọn)

Nếu muốn chạy Flask server trên máy local:

```powershell
cd C:\GitHub\TrueChip\TrueChip\secure_chip_web
$env:DATABASE_URL = "postgresql://<user>:<password>@<host>/<database>"
python server\mock_server.py
```

Server chạy tại `http://127.0.0.1:5000`. Tester local dùng:

```powershell
python client\chip_tester.py `
  --port COM3 `
  --server-url http://127.0.0.1:5000/verify
```

Để deploy server trên Render, thư mục làm việc phải là
`TrueChip/secure_chip_web`, cài đặt từ `requirements.txt`, start command có
thể dùng:

```text
gunicorn server.mock_server:app
```

Thiết lập `DATABASE_URL` trong Render Environment, không đưa credential vào
repository.

## 9. Deploy web lên GitHub Pages

Source web chuẩn là:

```text
TrueChip/secure_chip_web/index.html
```

Workflow nằm ở:

```text
.github/workflows/pages.yml
```

Sau khi commit và push lên nhánh `main`, vào tab **Actions** của repository và
chờ workflow **Deploy TrueChip web to GitHub Pages** hoàn tất. Mở:

```text
https://zarwijr.github.io/TrueChip/
```

Nếu vẫn thấy giao diện cũ, nhấn `Ctrl+F5` hoặc mở cửa sổ InPrivate/Incognito.
Trong Settings -> Pages, source nên là **GitHub Actions**.

## 10. Kiểm thử RTL

Từ `C:\GitHub\TrueChip\TrueChip` trong Git Bash hoặc Linux:

```bash
bash Simulation/run_regression.sh
```

Chỉ coi regression là đạt khi script kết thúc với toàn bộ test pass. OpenLane
signoff phải được kiểm tra bằng `check_signoff.py` trên đúng thư mục run có log
và kết quả tương ứng. Các file `runs/`, VCD và kết quả build có thể được lược
bỏ khỏi gói nhẹ, nhưng khi báo cáo kết quả phải lưu lại log của đúng run đã
được kiểm tra.

## 11. Xử lý lỗi nhanh

| Hiện tượng | Cách xử lý |
|---|---|
| Không thấy COM3 | Kiểm tra Device Manager, cáp USB và driver; thử rút/cắm lại board. |
| `Failed to open serial port` | Đóng Python, Serial Monitor và tab web khác đang dùng board; chờ 1-2 giây. |
| Server timeout | Render có thể đang khởi động; thử lại sau vài giây và kiểm tra log service. |
| UID toàn số 0 | Kiểm tra firmware/RO-PUF và nạp lại đúng bitstream; không cấp phát UID 0 cho demo thật. |
| UID có nhưng bị `FAKE` | Kiểm tra UID, secret key trong database và firmware có cùng một phiên bản. |
| Web hiển thị bản cũ | Push đúng file, chờ Actions xanh, rồi `Ctrl+F5`. |

## 12. Lưu ý an toàn

Đây là prototype kỹ thuật. Không dùng secret key production, mật khẩu database
hoặc token GitHub trong file commit. Nếu một credential đã từng được gửi lên
chat, issue hoặc commit công khai, hãy đổi credential đó trước khi triển khai
chính thức.
