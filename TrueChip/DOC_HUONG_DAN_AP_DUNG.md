# Hướng dẫn áp dụng gói v7.2

## ⚠️ ĐỌC MỤC NÀY TRƯỚC — lỗi ở lần trước

Ở lần vá v7.1 bạn dùng **Cách 2** (chỉ copy file đã sửa). Kết quả: copy file
**vào** thì được, nhưng file cần **xóa** thì vẫn nằm nguyên. Hai file sau đã
quay lại trong gói `run_4`:

- `Simulation/auth_fsm_tb.v` — khai báo trùng module, làm hỏng biên dịch cả thư mục
- `Simulation/secure_soc_top_tb.v` — gửi khung V1 không CRC và in `[PASS]` vô điều kiện

v7.2 đã thêm bộ chặn trong `run_regression.sh` để việc này không thể lặp lại
âm thầm nữa. Nhưng **lần này hãy dùng Cách 1**.

---

## Gói này chứa gì

Toàn bộ mã nguồn, tài liệu, cấu hình — đã lược 3 thư mục nặng và **không hề
thay đổi**:

| Đã lược bỏ | Lý do |
|---|---|
| `OpenLane/secure_asic_top/runs/` | Log/kết quả `run_4`. Bạn sẽ chạy lại tạo `run_5`. |
| `Quartus/db/`, `Quartus/incremental_db/` | Quartus tự sinh lại. |
| `Quartus/output_files/TrueChip.sof` | Sẽ sinh lại khi compile. |

---

## Cách 1 — Khuyến nghị (thay thế nguyên cây)

```bash
unzip TrueChip_v7.2_submission_ready.zip
cd TrueChip_v7.2_submission_ready

# copy phần nặng từ gói run_4 cũ sang
cp -r /duong/dan/TrueChip_v7.1_submission_ready/OpenLane/secure_asic_top/runs  OpenLane/secure_asic_top/
cp -r /duong/dan/TrueChip_v7.1_submission_ready/Quartus/db                     Quartus/
cp -r /duong/dan/TrueChip_v7.1_submission_ready/Quartus/incremental_db         Quartus/
cp    /duong/dan/TrueChip_v7.1_submission_ready/Quartus/output_files/TrueChip.sof Quartus/output_files/
```

Cách này không để sót file cũ.

---

## Cách 2 — Overlay (nếu buộc phải giữ cây hiện tại)

Copy đè:

```
RTL/ro_puf.v                                   <- SỬA LỖI P0
Simulation/ro_puf_tb.v                         <- MỚI
Simulation/run_regression.sh                   <- thêm bộ chặn + test ro_puf
OpenLane/secure_asic_top/config.json
OpenLane/secure_asic_top/constraints.sdc
OpenLane/secure_asic_top/sync_rtl.py           <- KHÔI PHỤC (bản cũ hỏng, toàn byte 0)
OpenLane/secure_asic_top/check_signoff.py      <- MỚI
OpenLane/secure_asic_top/run_klayout_drc.sh    <- MỚI
README.md
CHANGELOG_v7.2.md                              <- MỚI
VALIDATION_v7.2.md                             <- MỚI
TEST_PLAN_v7.2.md                              <- MỚI
```

Và **XÓA** cho bằng được:

```
Simulation/auth_fsm_tb.v
Simulation/secure_soc_top_tb.v
OpenLane/secure_asic_top/runs/run_*/config .json     (nếu còn, tên có dấu cách)
```

Rồi:
```bash
python3 OpenLane/secure_asic_top/sync_rtl.py
chmod +x OpenLane/secure_asic_top/*.sh OpenLane/secure_asic_top/*.py
```

---

## Kiểm tra ngay sau khi áp dụng

```bash
bash Simulation/run_regression.sh
```

Kỳ vọng: `REGRESSION SUMMARY: 8 passed, 0 failed`, exit code 0.

Nếu thấy `[FAIL] stale file must be deleted:` → bộ chặn đang hoạt động đúng,
xóa file nó chỉ ra rồi chạy lại.

---

## Ba việc phải chạy lại trên máy có tool

1. **Quartus** — compile lại. `ro_puf.v` có thay đổi RTL thật (thêm thanh ghi
   `cnt_clr_n` + 2 trạng thái FSM), **bắt buộc** compile lại.
2. **OpenLane `run_5`** — với `config.json` mới, rồi:
   ```bash
   python3 OpenLane/secure_asic_top/check_signoff.py runs/run_5
   ```
   Đây là cổng quyết định. Không còn BLOCKER thì mới đi tiếp.
3. **Cấp phát lại database** — khóa trên board đã đổi sau khi sửa RO-PUF.
   Xem `TEST_PLAN_v7.2.md` Giai đoạn 0, bước 0.7–0.8.

---

## Cảnh báo về ổ đĩa

`sync_rtl.py` trong gói `run_4` là **635 byte toàn số 0** — đúng kích thước,
nội dung rỗng. Đây là dấu hiệu lỗi ghi đĩa hoặc tắt máy đột ngột.

Tôi đã quét toàn gói: chỉ file này hỏng. Nhưng nên kiểm tra sức khỏe ổ đĩa
trên máy build — một file hỏng kiểu này lọt vào GDS hay netlist sẽ khó phát
hiện hơn nhiều.
