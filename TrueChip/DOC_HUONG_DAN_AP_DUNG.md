# Bản chốt — hướng dẫn áp dụng và việc còn lại

## Kết quả rà soát lần này

**Số liệu run_5 và run_6 khớp chính xác 100%** với bảng đã viết trong
`SIGNOFF_DISCLOSURE_v7.2.md`. Không phải sửa con số nào.

| | run_5 (250) ← NỘP | run_6 (200) |
|---|---|---|
| Antenna | 29/29, ratio 2,09 | 27/27, ratio 2,93 |
| Diode | 6.654 | 8.786 |
| Max fanout (data) | 604 | 757 |
| Setup slack | +1,50 ns | +1,36 ns |
| Verdict | SUBMITTABLE WITH DISCLOSURE | SUBMITTABLE WITH DISCLOSURE |

Đã chạy lại trong workspace review: regression **8/8 PASS**, Verilator
**0 error 0 warning**, quét toàn cây **không có file hỏng**.

---

## Hai vấn đề phát hiện và đã xử lý

### 1. `uart_rx.v` tách bản — hợp lệ, nhưng thiếu bộ chặn

`sync_rtl.py` đã được sửa để cố ý **không ghi đè** `uart_rx.v`, vì bản FPGA
dùng `altera_attribute` (Quartus hiểu) còn bản ASIC dùng `async_reg` (Yosys
hiểu). Copy chiều nào cũng làm mất marker CDC ở công nghệ kia — **quyết định
này đúng**.

Nhưng nó tạo rủi ro: một thay đổi chức năng thật ở `RTL/uart_rx.v` sẽ **không
bao giờ** tới được bản ASIC — đúng loại lỗi phân kỳ âm thầm đã từng xảy ra với
testbench trùng lặp trước đây.

**Đã kiểm chứng bản hiện tại an toàn:**
- Bỏ hết attribute và comment → logic giống hệt (chỉ khác `reg a; reg b;` với
  `reg a, b;`)
- Tổng hợp Yosys cả hai bản → **300 cell, histogram loại cell giống hệt**
- → `run_5` và `run_6` đã harden đúng logic, **không cần chạy lại**

**Đã vá rủi ro:** `sync_rtl.py` giờ tự so sánh logic của file tách bản sau khi
gỡ attribute/comment/format, và **thoát với mã lỗi** nếu phân kỳ. Đã
mutation-test: đảo một phép gán trong bản FPGA → script chặn đúng.

### 2. `VALIDATION_v7.2.md` ghi sai tên run

Tài liệu ghi `runs/run_1` — **một run không tồn tại trong gói** — nhưng số liệu
bên trong lại là của `run_5`. Đã sửa thành `run_5`, đồng thời:
- Hạ CVC từ BLOCKER xuống WARN kèm lý do (khớp với `check_signoff.py`)
- Sửa mục `results/` — bạn vẫn giữ bản gốc, chỉ bỏ khi gửi lên cho nhẹ
- Bổ sung bảng thang antenna 3 điểm và mục kiểm chứng `uart_rx.v`
- Cập nhật mục "chưa kiểm chứng" cho đúng những gì đã thực sự chạy

---

## Cách áp dụng

Chỉ cần copy 3 file:

```
OpenLane/secure_asic_top/sync_rtl.py     (có bộ chặn phân kỳ)
VALIDATION_v7.2.md                       (sửa run_1 → run_5)
CHANGELOG_v7.2.md                        (sửa khẳng định 8/8 byte-for-byte)
```

Kiểm tra:
```bash
bash Simulation/run_regression.sh                              # 8 passed
python3 OpenLane/secure_asic_top/sync_rtl.py                   # exit 0
python3 OpenLane/secure_asic_top/check_signoff.py runs/run_5   # exit 2
```

---

## Việc còn lại — theo đúng thứ tự

Không còn việc nào đụng tới RTL hay OpenLane nữa.

### Bước 1 — Cấp phát lại database (bắt buộc, làm trước tiên)

Sau khi sửa lỗi P0 RO-PUF, khóa trên board đã đổi. Chưa làm bước này thì mọi
kịch bản demo sẽ trả `FAKE`.

Xem `TEST_PLAN_v7.2.md` Giai đoạn 0, bước 0.7–0.8.

> **Trong suốt buổi test và quay video: cấp nguồn MỘT LẦN, không nhấn
> `KEY[0]`.** Mỗi lần reset là một lần đo PUF mới → khóa khác → server trả
> FAKE. Kịch bản lockout (TC-06) làm **cuối cùng**.

### Bước 2 — Chạy 7 kịch bản test, chụp ảnh

Theo `TEST_PLAN_v7.2.md` Giai đoạn 1 và 2. Hai ảnh có sức thuyết phục nhất:
- **A4** — RO-PUF trước/sau khi sửa, FAIL và PASS cạnh nhau
- **A7** — waveform cho thấy counter **giữ** giá trị khi ring dừng

### Bước 3 — Quay video demo 3 phút

Kịch bản và lời thoại có sẵn trong `TEST_PLAN_v7.2.md` Giai đoạn 3.

### Bước 4 — Viết báo cáo

- Số liệu và câu chữ công bố: `SIGNOFF_DISCLOSURE_v7.2.md`
- Định vị so với 33 đội, kịch bản Q&A, thứ tự slide:
  `COMPETITIVE_POSITIONING.md`

### Bước 5 — Đóng gói nộp bài

**Phải kèm `runs/run_5/results/`** (GDS, netlist cuối, DEF, SPEF). Đây là
hạng mục duy nhất còn lại có thể bị trừ điểm về tính minh bạch.

Có thể bỏ `results/` của `run_6` cho nhẹ — nhưng **giữ `logs/` + `reports/`
của run_6**, vì bảng thang antenna 3 điểm trong báo cáo dựa vào nó.
