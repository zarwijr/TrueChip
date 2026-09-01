# Trạm ghi danh chip TrueChip

## Nguyên nhân lỗi trước đây

Biến môi trường đặt bằng `$env:TRUECHIP_DATABASE_URL` **chỉ sống trong đúng
cửa sổ PowerShell đã đặt nó**. `start_admin_web.bat` mở một tiến trình mới
không thừa kế biến đó, nên:

- `factory_tool.py` chạy trong cửa sổ đã đặt biến → **chạy được**
- `admin_web.py` chạy qua file .bat → **không thấy biến** → báo chưa cấu hình

Thêm một điểm nữa: `server/mock_server.py` đọc `DATABASE_URL`, còn
`enrollment_service.py` chỉ đọc `TRUECHIP_DATABASE_URL`. Đặt tên này rồi mong
tên kia hoạt động là không được.

## Đã sửa thế nào

1. **Chấp nhận cả hai tên biến** — `TRUECHIP_DATABASE_URL` và `DATABASE_URL`.
2. **Cấu hình ngay trên web, lưu vào file** — dán URL một lần, nó ghi vào
   `admin_config.json` (đã có trong `.gitignore`) và tồn tại vĩnh viễn, không
   phụ thuộc cửa sổ nào.
3. **Nút "Thử kết nối"** — biết ngay URL đúng hay sai, không phải đoán.
4. **Trạng thái nói rõ nguồn cấu hình** — biến môi trường hay file.

## Cách dùng

```
cd secure_chip_web
python admin_web.py
```
M�� http://127.0.0.1:8765/

Lần đầu: mở mục **Cấu hình Database URL**, dán connection string, bấm **Lưu**.
Xong. Các lần sau không cần làm lại.

## Hai cơ chế ghi danh — đã đủ và đúng

| Nút | Hành vi | Dùng khi |
|---|---|---|
| **Ghi danh chip mới** | `ON CONFLICT DO NOTHING` — UID đã tồn tại thì **từ chối** | Chip mới |
| **Ghi đè khóa chip đã có** | `ON CONFLICT DO UPDATE` — thay khóa | Sau khi nạp lại bitstream, khóa PUF đổi |

Tách hai đường là **đúng thiết kế**: thao tác ghi danh thường ngày không thể
vô tình xóa mất khóa của một chip đang hoạt động. Muốn ghi đè thì phải bấm nút
riêng và xác nhận. Giữ nguyên.

## Về việc đưa lên online

**Không nên.** Trang này nhận `diversified_key` ở dạng rõ. Đưa lên Internet
nghĩa là khóa bí mật của mọi chip đi qua đường truyền và nằm trên một máy chủ
bạn không kiểm soát hoàn toàn.

Thiết kế hiện tại — chỉ nghe ở `127.0.0.1` — **là lựa chọn đúng**, và cũng là
điều một ban giám khảo bảo mật sẽ đánh giá cao. Trong công nghiệp, khâu nạp
khóa (key provisioning) luôn diễn ra tại trạm vật lý có kiểm soát, không qua
web công cộng.

Nếu bắt buộc phải làm từ xa, tối thiểu cần: HTTPS thật, xác thực nhiều yếu tố,
IP allow-list, và không ghi log thân request. Đó là công việc riêng, không nên
làm gấp trong tuần này.

## Bảo vệ khóa trong bản hiện tại

- Câu truy vấn danh sách chip **không hề chọn cột `secret_key`** — không phải
  lọc ở tầng hiển thị, mà là không lấy ra khỏi database. Không lấy thì không
  lộ được qua log hay lỗi hiển thị.
- `log_message` bị vô hiệu hóa nên thân request không vào terminal.
- Ô nhập khóa là `type="password"`, tự xóa sau khi ghi danh thành công.
- Database URL không bao giờ được gửi ngược về trình duyệt — chỉ trả về
  *nguồn* của nó.
- `Content-Security-Policy` chặn mọi kết nối ra ngoài từ trang này.
