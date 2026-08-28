# TrueChip v7.2 validation note — 26/08/2026

Ghi lại **chính xác** những gì đã được chạy thật, để lần review sau không
nhầm giữa kiểm tra tĩnh và kết quả tool thật.

Công cụ có trong workspace review lần này: **Icarus Verilog 12.0**,
**Verilator 5.020**, **Yosys 0.33**, Python 3 + pycryptodome.

---

## 1. Đã CHẠY THẬT

### 1.1 Regression RTL — 8/8 PASS

```
$ bash Simulation/run_regression.sh
REGRESSION SUMMARY: 8 passed, 0 failed        (exit code 0)
```

Gồm: `aes128`, `uart_loopback`, `cmd_parser`, `auth_fsm`, `uart_echo`,
**`ro_puf` (mới)**, `secure_asic_top` (full-chip), và elaboration
`secure_soc_top`.

### 1.2 RO-PUF — chứng minh lỗi P0 và bản sửa

Chạy **cùng một testbench** trên hai phiên bản RTL. Bản cũ chỉ được thêm mô
hình delay để mô phỏng được, **logic giữ nguyên 100%**.

| RTL | Kết quả |
|---|---|
| v7.1 (lỗi) | `[FAIL] puf_id is ALL ZERO` — 0/8 bit entropy — exit non-zero |
| v7.2 (đã sửa) | `[PASS] puf_id is non-zero: ...7b` — 6/8 bit — reproducible |

Đây là mutation test thật, không phải regression tự thỏa mãn.

### 1.3 Bộ chặn file cũ — đã kiểm chứng

Đặt lại `Simulation/auth_fsm_tb.v` vào rồi chạy regression:

```
[FAIL] stale file must be deleted: .../Simulation/auth_fsm_tb.v
```

Script dừng ngay thay vì âm thầm cho kết quả sai.

### 1.4 Phân tích netlist bằng Yosys — giải thích 6 unconstrained endpoint

Tổng hợp `secure_asic_top` và duyệt cone D của toàn bộ 3.556 register:

```
Tong so DFF: 3556
So DFF co cone D KHONG cham toi flop nao khac: 12
    1 x  D <- PI:uart_rx_i     (u_uart_rx.rx_d1, tang dau bo dong bo CDC)
   11 x  D <- CONST            (cac co trang thai "<= 1'b1")
```

Sau technology mapping phần lớn nhóm hằng số có thêm mux hồi tiếp cho enable
nên có path thật; số ít còn lại chính là 6 endpoint mà STA báo. **Benign.**

### 1.5 Tái hiện cảnh báo "output has no driver"

Chạy lại chuỗi pass của OpenLane bằng Yosys 0.33
(`synth → abc → setundef → hilomap → splitnets → opt_clean → insbuf → check`):

- pass `check` **sau `insbuf`** sinh ra cùng lớp cảnh báo "used but has no driver"
- nhưng netlist ghi ra **thực sự có driver**: `.Y(uart_tx_o)`

Kết hợp với `[INFO ODB-0130] Created 9 pins` trong DEF và LVS = 0 error →
**false positive**, đúng như OpenLane issue #1827.

### 1.6 Lint

| Đối tượng | Kết quả |
|---|---|
| Verilator `secure_asic_top` (8 file vào OpenLane) | **0 error, 0 warning** |
| Verilator `secure_soc_top` | 3 `BLKLOOPINIT` + 1 `UNOPTFLAT`, **tất cả trong `ro_puf.v`** |

`BLKLOOPINIT`/`UNOPTFLAT` là giới hạn của Verilator với ring oscillator (vòng
lặp tổ hợp) và gán non-blocking vào mảng trong for-loop. **Không phải lỗi
thiết kế** — Quartus 25.1 biên dịch file này với 0 error.

### 1.7 Kiểm tra tĩnh

- 16 file Python: **0 lỗi cú pháp**
- `config.json`: JSON hợp lệ, 28 key
- `sync_rtl.py`: 8/8 file khớp **byte-for-byte** với `RTL/`
- Quét toàn bộ gói tìm file hỏng: **1 file** — `sync_rtl.py` (635 byte toàn
  số 0), đã khôi phục. Không file nào khác chứa byte null.

---

## 2. Đã ĐỌC LẠI từ log `run_4` (không chạy lại tool)

### 2.1 Đạt

| Hạng mục | Kết quả |
|---|---|
| Flow status | `flow completed`, 38m54s |
| Detailed-route DRC | 0 |
| Magic DRC | 0 |
| LVS (netgen) | 0 error |
| KLayout XOR | 0 |
| STA signoff 4 góc | `wns 0.00 / tns 0.00`, worst setup **+0,46** → **+10,46 ns**, worst hold **+0,09 ns** |
| IR drop | worst 21,7 mV / 1,8 V = **1,2%** |

### 2.2 Chưa đạt (đã sửa cấu hình trong v7.2, cần chạy lại)

| Hạng mục | `run_4` | Nguyên nhân |
|---|---|---|
| CVC/ERC | `-1` (fatal) | `sky130_ef_sc_hd__decap_12` không có subcircuit trong CDL |
| KLayout DRC | `-1` (chưa chạy) | `KLAYOUT_DRC_TECH_SCRIPT` không được PDK khai báo |
| Antenna | 9 pin / 9 net | ratio cao nhất 2,54, tất cả trên met1 |
| Max slew | 687 | **47% là chân `ANTENNA__*/DIODE`** |
| Max fanout | 2.151 | 2.026 data + 125 clock-tree; fanout gấp đôi do diode |
| Diode | 22.826 / 23.276 cell | `HEURISTIC_ANTENNA_THRESHOLD = 90` chèn 17.226 diode một lượt |

### 2.3 Bẫy trong `metrics.csv`

Cột `wns = -27.02` / `tns = -86022.05` lấy từ `logs/synthesis/2-sta.log` —
**STA trước place, dùng wireload model**. Số signoff thật ở mục 2.1.
`check_signoff.py` tự cảnh báo điều này.

---

## 3. CHƯA được kiểm chứng

Workspace review không có Quartus, OpenROAD, OpenLane, KLayout, Magic hay
phần cứng. Do đó **KHÔNG** khẳng định:

- Quartus 25.1 biên dịch lại thành công **sau khi sửa `ro_puf.v`** — đây là
  thay đổi RTL thật (thêm 1 thanh ghi `cnt_clr_n` và 2 trạng thái FSM), **bắt
  buộc phải compile lại**;
- OpenLane chạy lại thành công với `config.json` / `constraints.sdc` mới;
- số antenna sau khi nâng `HEURISTIC_ANTENNA_THRESHOLD` lên 250;
- slew/fanout sau khi giảm số diode;
- CVC/ERC có hoàn tất sau khi bỏ `decap_12` khỏi `DECAP_CELL`;
- KLayout DRC có chạy được với `KLAYOUT_DRC_TECH_SCRIPT` (biến này khác nhau
  giữa các phiên bản OpenLane — đó là lý do có `run_klayout_drc.sh`);
- giá trị `puf_id` thật trên silicon, entropy, uniqueness, độ ổn định theo
  nhiệt độ/điện áp;
- kết quả test UART trên board thật;
- tính đúng của GDS cuối (ZIP không chứa `results/`).

**Giới hạn xác minh còn lại:** không có `runs/run_4/results/`, nên không thể
checksum netlist/GDS thực tế với RTL. Lần gửi sau **phải kèm `results/`**.

---

## 4. Việc cần làm tiếp — theo thứ tự

1. `bash Simulation/run_regression.sh` → phải 8/8.
2. Compile lại Quartus, xác nhận 0 Error và Warning về `KEY[1]` đã hết.
3. Chạy OpenLane `run_5`.
4. `python3 OpenLane/secure_asic_top/check_signoff.py runs/run_5` — **đây là
   cổng quyết định**. Không còn BLOCKER thì mới đi tiếp.
5. Nếu KLayout DRC vẫn NOT RUN: `./run_klayout_drc.sh runs/run_5`.
6. Nếu còn antenna: hạ `HEURISTIC_ANTENNA_THRESHOLD` 250 → 200 → 150, chạy
   lại, chấm điểm lại. Nếu slew/fanout quay lại thì nâng lên.
7. Nạp bitstream mới, đọc `puf_id` bằng SignalTap, **cấp phát lại database**.
8. Chạy bộ test trong `TEST_PLAN_v7.2.md`.
9. Đóng gói **toàn bộ `runs/run_5/results/`** trong ZIP nộp.
