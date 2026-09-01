# TrueChip — hai trang web

| File | Chạy ở đâu | Dùng làm gì |
|---|---|---|
| `index.html` | Công khai (GitHub Pages) | Giới thiệu sản phẩm + công cụ quét chip |
| `admin.html` | **Chỉ localhost** | Ghi danh chip, nhập khóa bí mật |

Hai trang này **phải tách nhau**. Trang công khai không bao giờ được đụng tới
secret key; trang admin nhận key dạng rõ nên không được ra Internet.

---

## index.html — trang giới thiệu

Đã dựng lại thành trang sản phẩm hoàn chỉnh, **giữ nguyên 100% phần
JavaScript** đang chạy tốt (đã kiểm chứng khối JS nằm nguyên vẹn từng ký tự,
đủ cả 12 element ID).

Bố cục:

1. **Hero** — thông điệp chính + 4 con số nổi bật
2. **Vấn đề** — vì sao QR / hologram / chip lưu serial đều thất bại
3. **Cách hoạt động** — 4 bước + sơ đồ khung Protocol V2
4. **Bảo mật** — 4 lớp phòng vệ trong phần cứng
5. **Silicon** — bằng chứng signoff SKY130A
6. **Quét thử** — công cụ Web Serial (phần cũ, không đổi)
7. **Footer** — hướng phát triển

M��c Silicon có ghi rõ ba giới hạn: layout ASIC không chứa RO-PUF, còn 29 cảnh
báo antenna biên, và ERC chưa hoàn tất. Nói trước vẫn hơn để giám khảo tự tìm
ra.

Trang dùng Tailwind qua CDN nên chỉ cần mở file là chạy, không cần build.

---

## Đổi UID sang chip khác — không cần sửa web

Đã kiểm chứng: **không có chỗ nào hardcode `2583`** trong `secure_chip_web/`.

| Thành phần | Lấy UID từ đâu |
|---|---|
| `chip_tester.py` | `get_uid()` — gửi GET_ID, đọc chip trả về |
| `index.html` | `bytesToHex(idResponse.payload)` — đọc từ FPGA |
| `mock_server.py` | Nhận UID trong request rồi tra database |
| `admin.html` | Bạn nhập tay UID đọc được |

Nên đổi `chip_rom.v` sang `123123…` là toàn hệ thống tự chạy theo.

### Quy trình khi dùng board khác

1. Sửa UID trong `RTL/chip_rom.v` (32 ký tự hex)
2. Compile lại Quartus, nạp bitstream
3. Chạy `chip_tester.py` xác nhận chip trả đúng UID mới
4. **Đọc `diversified_key` mới bằng SignalTap** — mỗi board có PUF khác nhau
   nên khóa khác nhau, không đoán được
5. Ghi danh cặp (UID mới, khóa mới) qua `admin.html`

Bước 4 dễ quên nhất. UID bạn tự đặt được, khóa thì phải đo.

### Lưu ý về ASIC

`chip_rom.v` cũng nằm trong luồng ASIC đã hardening (`run_5`). Sửa nó thì
`sync_rtl.py` sẽ đồng bộ sang `OpenLane/src/` và bản GDS hiện tại không còn
khớp RTL.

Khuyến nghị cho phần thi: **giữ nguyên `chip_rom.v`**. Nếu bắt buộc đổi thì
phải chạy lại OpenLane (~98 phút) và cập nhật lại số liệu trong
`SIGNOFF_DISCLOSURE_v7.2.md`.

---

## admin.html — trạm ghi danh

Xem `ENROLLMENT_GUI.md` để biết chi tiết nguyên nhân lỗi cũ và cách sửa.

Tóm tắt: biến `$env:` chỉ sống trong đúng cửa sổ PowerShell đã đặt nó, nên
`start_admin_web.bat` mở tiến trình mới là mất. Giờ dán URL một lần trên web,
nó lưu vào `admin_config.json` và tồn tại vĩnh viễn.

```
cd secure_chip_web
python admin_web.py
```
M�� http://127.0.0.1:8765/
