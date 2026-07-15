# web/ — Secure Chip Web Portal

Cổng web cho hệ thống Secure Chip: tra cứu công khai (không cần đăng nhập) +
dashboard nhà sản xuất (cần đăng nhập). Dùng chung database với
`server/mock_server.py` tại `../data/secure_chip.db`.

## Chạy

```bash
cd secure_chip_web        # thư mục cha, không phải web/
pip install -r requirements.txt
python web/app.py
```
Mặc định: `http://127.0.0.1:5050`. Đổi cổng/host bằng biến môi trường
`SECURE_CHIP_WEB_PORT`, `SECURE_CHIP_WEB_HOST`. Đặt `SECURE_CHIP_WEB_SECRET`
để cố định session secret khi deploy thật.

## Các trang

- `/`, `/lookup` — tra cứu công khai theo UID (không cần đăng nhập). Có nút
  quét QR bằng camera (thư viện jsQR, chạy hoàn toàn trong trình duyệt) và
  nút dán từ clipboard, ngoài việc gõ tay 32 ký tự hex. Cũng nhận
  `GET /lookup?uid=XXXX` — dùng để in QR trỏ thẳng vào link này, quét bằng
  bất kỳ app camera nào trên điện thoại cũng ra kết quả luôn.
- Kết quả tra cứu hợp lệ hiển thị thêm **số lần đã tra cứu hợp lệ trước đó
  + thời điểm lần gần nhất** — không chặn việc quét lại nhiều lần (hàng bán
  lại, kiểm tra định kỳ vẫn hợp lệ), chỉ để người dùng tự đánh giá nếu thấy
  bất thường.
- `/register`, `/login`, `/logout` — tài khoản nhà sản xuất, mật khẩu băm
  bằng `werkzeug.security`.
- `/dashboard`, `/dashboard/chips/new`, `/dashboard/chips/<uid>/edit` — mỗi
  nhà sản xuất chỉ thấy/sửa chip của chính mình.

## Giới hạn cần biết

- Đây là kiểm tra **cơ bản theo UID**, không phải xác thực mật mã đầy đủ.
  Ai biết UID in trên bao bì cũng tra ra "hợp lệ" qua web — không phát hiện
  được việc tháo chip thật gắn sang hàng giả. Xác thực mật mã đầy đủ (chống
  giả UID) cần đầu đọc UART/NFC thật chạy `client/chip_tester.py`.
- `preview_demo.html` là bản demo tĩnh (dữ liệu mẫu, không kết nối server) —
  mở trực tiếp bằng trình duyệt để xem giao diện mà không cần chạy Python.

## Bảo mật khi triển khai thật

- Đặt sau HTTPS (camera QR-scan cũng cần HTTPS ngoài localhost).
- Rate-limit `/lookup` và `/login`.
- Cân nhắc CSRF protection (Flask-WTF) cho các form.
