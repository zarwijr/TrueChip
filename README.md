# TrueChip

TrueChip là nguyên mẫu xác thực phần cứng dùng FPGA, UART và AES-128. Mục
tiêu của dự án là chứng minh một chip có thể tự nhận dạng, trả lời một thử
thách ngẫu nhiên và để cloud server kiểm tra chip thật hay giả.

## TrueChip hoạt động như thế nào?

1. Máy tính gửi khung Protocol V2 qua UART tới FPGA.
2. FPGA trả về UID 128-bit công khai.
3. Máy tính gửi nonce 128-bit ngẫu nhiên.
4. FPGA tạo phản hồi AES-128 từ khóa bí mật của chip, nonce và UID.
5. Verification server tính lại phản hồi và trả về thông tin chip.

Giao tiếp hiện tại dùng UART 115200 baud, 8N1. NFC/RFID là hướng phát triển
tương lai, chưa phải chức năng của bản hiện tại.

## Các thành phần chính

```text
TrueChip/
├── RTL/                         # AES, UART, Protocol V2, auth FSM, RO-PUF
├── Quartus/                     # Dự án và ràng buộc FPGA Intel
├── Simulation/                  # Testbench và regression RTL
├── OpenLane/secure_asic_top/    # Luồng hardening digital RTL trên SKY130
├── secure_chip_web/
│   ├── index.html               # Web Serial frontend
│   ├── client/chip_tester.py    # Python tester qua COM/UART
│   ├── factory_tool.py          # Cấp phát chip vào PostgreSQL
│   └── server/mock_server.py    # Flask verification server
├── test/                        # Kiểm thử UART trên board thật
└── docs/                        # Tài liệu yêu cầu và kiến trúc
```

## Bắt đầu nhanh

Đọc [hướng dẫn sử dụng](TrueChip/HUONG_DAN_SU_DUNG.md) để cài thư viện,
cấp phát chip, chạy Python tester, chạy web trên GitHub Pages và xử lý lỗi
COM3.

Tài liệu kỹ thuật chi tiết nằm tại [TrueChip/readme.md](TrueChip/readme.md),
bao gồm Protocol V2, phạm vi chứng minh của FPGA, kế hoạch kiểm thử và các
giới hạn của RO-PUF.

## Web online

Frontend có thể chạy tại:

<https://zarwijr.github.io/TrueChip/>

Web Serial chỉ hoạt động trong Chrome hoặc Edge trên HTTPS và chỉ truy cập
được cổng COM trên chính máy đang mở trình duyệt. Server cloud không thể tự
truy cập COM3 từ xa.

Workflow GitHub Pages nằm tại
[`.github/workflows/pages.yml`](.github/workflows/pages.yml). Mỗi lần push lên
nhánh `main`, GitHub Actions sẽ đóng gói `TrueChip/secure_chip_web/index.html`
và triển khai frontend.

## Phạm vi hiện tại

- FPGA authentication prototype dùng AES-128 và UART.
- Verification server Flask/PostgreSQL xác thực UID, response và nonce đã dùng.
- Có kiểm soát replay, rate limit và lockout ở tầng giao thức.
- ASIC flow tập trung vào digital AES/UART core trên SKY130; RO-PUF là phần
  thử nghiệm hướng FPGA.
- Chi phí thương mại dưới 1 USD/chip là mục tiêu dài hạn, chưa phải kết quả
  đã được chứng minh bởi bản RTL hoặc layout hiện tại.

## Bảo mật

Không commit mật khẩu PostgreSQL, secret key, file `.env` hoặc token GitHub vào
repository. Biến môi trường dùng cho database phải được cấu hình trên máy
factory hoặc trong phần Environment của Render. Nếu credential database đã bị
đăng công khai, cần rotate credential trước khi dùng thật.

## License

Xem license và các tài liệu kỹ thuật hiện có trong repository.
