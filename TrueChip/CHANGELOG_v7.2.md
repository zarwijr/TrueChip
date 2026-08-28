# TrueChip v7.2 change log — 26/08/2026

Bản vá trên nền v7.1, sau khi review `run_4`.

**Thay đổi quan trọng nhất: sửa một lỗi chức năng P0 trong RO-PUF khiến
`puf_id` luôn bằng 0 trên mọi board.** Lỗi này đã sống sót qua Quartus
(0 error), qua timing closure và qua test board thật, vì chip vẫn xác thực
đúng — thứ duy nhất bị mất là toàn bộ luận điểm per-device uniqueness.

---

## 1. P0 — RO-PUF đọc bộ đếm sau khi đã bị xóa

### Lỗi

`RTL/ro_puf.v` dùng **cùng một tín hiệu** `ro_enable` vừa để gate vòng dao
động, vừa làm reset bất đồng bộ cho bộ đếm:

```verilog
always @(posedge ro_out[gi] or negedge ro_enable)
    if (!ro_enable) cnt_r <= 0;        // <-- SAI
    else            cnt_r <= cnt_r + 1;
```

Nhưng bộ điều khiển kết thúc cửa sổ đo bằng:

```verilog
ro_enable <= 1'b0;
state     <= S_FREEZE_WAIT;
```

Cạnh xuống của `ro_enable` **xóa sạch mọi bộ đếm đúng vào lúc giá trị cần
được đóng băng để đọc**. Đến `S_COMPARE` thì mọi `ro_cnt` đều bằng 0:

- `ro_cnt[2k] > ro_cnt[2k+1]` → `0 > 0` → luôn sai
- mọi `vote_cnt` giữ nguyên 0
- mọi `raw_bits[k]` = `(0 > MAJORITY_THRESH)` = 0
- **`puf_id = 128'd0` trên mọi thiết bị**

### Vì sao không ai phát hiện

`diversified_key = AES(master_key, 0)` là một hằng số hợp lệ. Chip vẫn trả
lời challenge đúng, server vẫn xác thực AUTHENTIC, demo vẫn chạy. Quartus
không thể bắt lỗi hành vi này vì RTL hoàn toàn hợp lệ.

### Cách sửa

Tách hẳn hai chức năng:

| Tín hiệu | Vai trò |
|---|---|
| `ro_enable` | **chỉ** gate vòng dao động — tắt = giữ nguyên giá trị đếm |
| `cnt_clr_n` (mới, active-low) | **chỉ** xóa bộ đếm, và chỉ được đảo khi vòng đã dừng |

Thêm 2 trạng thái FSM:

- `S_CLEAR` — giữ `cnt_clr_n` thấp trong `CLEAR_CYCLES` chu kỳ, vòng đang dừng
- `S_ARM` — nhả clear **trước** rồi mới bật vòng ở chu kỳ sau

Cả `S_IDLE` và `S_NEXT_ROUND` đều đi qua `S_CLEAR`.

**An toàn race tốt hơn bản cũ:** `cnt_clr_n` chỉ đổi trạng thái khi
`ro_enable = 0`, tức khi `ro_out[gi]` đứng yên — không tồn tại cạnh clock
nào tại thời điểm reset bất đồng bộ di chuyển. Bản v7.1 không có đảm bảo này.

### Bằng chứng

`Simulation/ro_puf_tb.v` (mới). Chạy **cùng testbench** trên hai phiên bản
RTL (bản cũ chỉ được thêm mô hình delay, logic giữ nguyên):

**RTL v7.1:**
```
[FAIL] puf_id is ALL ZERO - the v7.1 counter-clear bug is back
       0 of 8 entropy bits are 1
=== RO-PUF TESTS FAILED: 2 error(s) ===
```

**RTL v7.2:**
```
[PASS] puf_id is non-zero: 0000000000000000000000000000007b
       6 of 8 entropy bits are 1
[PASS] PUF ID is reproducible across a power cycle
=== RO-PUF TESTS PASSED ===
```

### ⚠️ HÀNH ĐỘNG BẮT BUỘC TRƯỚC KHI DEMO

Sau khi sửa, `puf_id` trên board **sẽ khác 0** → `diversified_key` **đổi**.

1. Nạp lại FPGA với bitstream mới.
2. Đọc `diversified_key` mới trong môi trường lab (dùng `--master-key` +
   `--device-id` đo được, xem `test/test_uart_challenge.py`).
3. **Cấp phát lại bản ghi chip trong database** bằng `factory_tool.py`.

Nếu bỏ qua bước 3, server sẽ trả `FAKE / response không khớp` — và đó sẽ là
lỗi xuất hiện giữa buổi demo.

### Hỗ trợ mô phỏng

Thêm macro **`RO_PUF_SIM`** (chỉ dùng khi mô phỏng, không bao giờ được tổng
hợp). Vòng dao động ở dạng tổng hợp là vòng lặp tổ hợp trễ-0, sẽ treo mọi
simulator tại thời điểm 0. Macro này gán cho mỗi vòng một trễ nhỏ khác nhau
theo `gi`, vừa để vòng chạy được trong thời gian mô phỏng, vừa mô phỏng thô
sự sai lệch quy trình mà PUF thực sự đo. Không có sự khác nhau giữa các vòng
thì mọi bộ đếm sẽ hòa nhau và test sẽ che mất đúng loại lỗi cần bắt.

---

## 2. P0 — CVC/ERC bị fatal

```
Fatal error: could not find subcircuit: XFILLER_0_78_1821(sky130_ef_sc_hd__decap_12)
```

`sky130_ef_sc_hd__decap_12` là cell do efabless sinh ra, **không có
subcircuit trong CDL của PDK**, nên CVC dừng ngay khi link netlist →
`cvc_total_errors = -1`.

**Sửa:** loại cell đó khỏi `DECAP_CELL`, chỉ giữ 4 cell `sky130_fd_sc_hd`
đều có mặt trong CDL:

```json
"DECAP_CELL": "sky130_fd_sc_hd__decap_8 sky130_fd_sc_hd__decap_6 sky130_fd_sc_hd__decap_4 sky130_fd_sc_hd__decap_3"
```

---

## 3. P0 — KLayout DRC chưa từng chạy

```
[WARNING]: ::env(KLAYOUT_DRC_TECH_SCRIPT) is not defined or doesn't exist
           for the current PDK. So, GDSII streaming out using KLayout will be skipped.
```

`klayout_violations = -1`. PDK sky130A có sẵn runset `sky130A_mr.drc` nhưng
không điền biến này, nên bước kiểm tra âm thầm không chạy.

**Bẫy dễ nhầm:** `reports/signoff/drc.rpt` ghi `COUNT: 0` — đó là báo cáo của
**Magic**, không phải KLayout. Và `XOR = 0` **không thay thế được** KLayout
DRC: XOR chỉ chứng minh GDS do Magic ghi và GDS do KLayout ghi mô tả cùng một
tập polygon, nó không nói gì về việc các polygon đó có tuân thủ design rule
hay không.

**Sửa:** hai lớp phòng vệ.

1. `config.json` khai báo `"KLAYOUT_DRC_TECH_SCRIPT": "pdk_dir::libs.tech/klayout/drc/sky130A_mr.drc"`
2. Thêm `OpenLane/secure_asic_top/run_klayout_drc.sh` — chạy KLayout DRC
   trực tiếp trên GDS cuối, không phụ thuộc phiên bản OpenLane. Dùng cái này
   nếu bước trong flow vẫn bị bỏ qua.

---

## 4. P0/P1 — Antenna và cơn bão diode

### Lỗi này là do cấu hình v7.1 của chính tôi

| Run | Cấu hình | Antenna | Diode | Slew | Fanout |
|---|---|---|---|---|---|
| `run_2` | GRT 1 lượt, không heuristic | 129 pin / 86 net | 950 | 0 | 0 |
| `run_4` | threshold 90 + `DIODE_INSERTION_STRATEGY 3` | 9 / 9 | **22.826** | **687** | **2.151** |

`HEURISTIC_ANTENNA_THRESHOLD` mặc định là **90**, nên bước heuristic chèn
**17.226 diode trong một lượt** (`logs/routing/19-diodes.log`). Tôi lại thêm
`DIODE_INSERTION_STRATEGY: 3` — vốn **deprecated** và **trùng chức năng** với
`RUN_HEURISTIC_DIODE_INSERTION`. Tổng 22.826 diode trên 23.276 cell logic ≈
**0,98 diode mỗi cell**.

**Cơ chế gây hại, có số liệu chứng minh:**

- 47% pin vi phạm slew **chính là chân `ANTENNA__*/DIODE`** — diode tự nó là
  thủ phạm
- fanout nhảy từ ≤10 lên đúng ~20 — **gấp đôi**, vì mỗi diode thêm một chân
  vào net
- diode được chèn **sau khi resizer đã chạy xong**, nên không bước nào sửa lại được

**Sửa:**

```json
"GRT_REPAIR_ANTENNAS": 1,
"GRT_MAX_DIODE_INS_ITERS": 5,
"RUN_HEURISTIC_DIODE_INSERTION": 1,
"HEURISTIC_ANTENNA_THRESHOLD": 250
```

và **bỏ hẳn** `DIODE_INSERTION_STRATEGY`.

Giữ lại sửa antenna lặp có mục tiêu của OpenROAD, nâng ngưỡng heuristic để
diode chỉ đặt trên net thực sự dài. Đây là thang tinh chỉnh — dùng
`check_signoff.py` sau mỗi run: nếu còn antenna thì hạ 250 → 200 → 150; nếu
slew/fanout xuất hiện trở lại thì nâng lên.

---

## 5. Công cụ mới: `check_signoff.py`

`run_4` báo `flow completed`, DRC/LVS/XOR sạch, timing đóng — mà vẫn còn
9 antenna, 687 slew, 2.151 fanout, CVC abort và KLayout DRC không chạy.
Phát hiện được điều đó phải đọc tay 6 file khác nhau.

```bash
cd OpenLane/secure_asic_top
python3 check_signoff.py runs/run_5
```

In ra một bảng chấm điểm và một verdict. Mã thoát: `0` = sạch, `1` = có
blocker, `2` = chỉ còn warning cần công bố trong báo cáo.

Nó tự làm những việc dễ sai khi làm tay:

- **tách fanout clock-tree khỏi fanout data** — clock tree được CTS dựng theo
  `CTS_MAX_CAP` và `CTS_SINK_CLUSTERING_SIZE` (25 sink/leaf), không theo luật
  fanout data, nên 125 mục `clkbuf_*` là bình thường; 2.026 mục còn lại mới là
  vấn đề thật
- **cảnh báo bẫy `wns = -27.02`** trong `metrics.csv` (đó là STA trước place)
- đọc slack signoff thật từ `logs/signoff/*rcx*sta*.log`
- tính tỉ lệ diode/cell để phát hiện chèn diode tràn lan
- giải thích các cảnh báo benign để giám khảo không hiểu nhầm

Kết quả chạy trên `run_4`: `VERDICT: NOT READY - 2 blocker(s), 5 warning(s)`.

---

## 6. Hai file cũ đã quay lại — và bộ chặn

`Simulation/auth_fsm_tb.v` và `Simulation/secure_soc_top_tb.v` (đã xóa ở
v7.1) **có mặt trở lại trong gói `run_4`**. Nguyên nhân: overlay bản vá lên
cây thư mục cũ thì copy file vào được, nhưng **không xóa file đi**.

Hậu quả nếu để nguyên:

- `auth_fsm_tb.v` khai báo trùng module → biên dịch cả thư mục là hỏng
- `secure_soc_top_tb.v` gửi khung V1 không CRC và in `[PASS]` vô điều kiện

**Sửa:** xóa lại, **và** thêm bộ chặn ở đầu `run_regression.sh` — nếu một
trong hai file tồn tại, script dừng ngay với thông báo rõ ràng thay vì âm
thầm cho kết quả sai.

Đã kiểm chứng: đặt lại file vào rồi chạy → script chặn đúng.

---

## 7. File `sync_rtl.py` bị hỏng hoàn toàn

Phát hiện ngoài dự kiến: `OpenLane/secure_asic_top/sync_rtl.py` trong gói
`run_4` là **635 byte toàn số 0**. Đúng kích thước, nội dung rỗng — dấu hiệu
điển hình của lỗi ghi đĩa hoặc tắt máy đột ngột.

```
$ python3 sync_rtl.py
SyntaxError: source code cannot contain null bytes
```

Đã khôi phục từ bản v7.1 và chạy lại: 8/8 file khớp byte-for-byte.

Tôi đã quét toàn bộ gói — **chỉ file này bị hỏng**, không có file nào khác
chứa byte null.

**Khuyến nghị:** kiểm tra sức khỏe ổ đĩa trên máy build. Một file hỏng kiểu
này lọt vào GDS hoặc netlist sẽ khó phát hiện hơn nhiều.

---

## 8. Những mục KHÔNG phải lỗi (đã xác minh, ghi rõ để báo cáo)

### 8.1 "6 unconstrained endpoints" — bình thường

Phân tích netlist bằng yosys cho thấy đúng **12 register có cone D không
chạm tới register nào khác**:

- **1** flop lấy dữ liệu từ cổng `uart_rx_i` — chính là `u_uart_rx.rx_d1`,
  tầng đầu của bộ đồng bộ CDC, mà `constraints.sdc` **cố ý** false-path
- **11** flop có D là hằng số (các cờ trạng thái `<= 1'b1`: `key_ready`,
  `kdf_start`, `aes_start`, `tx_start`, `hist_valid[k]`, `going_to_lockout`,
  `fifo_overflow`, …)

Sau technology mapping, phần lớn nhóm hằng số có thêm mux hồi tiếp cho enable
nên có path thật; số ít còn lại chính là 6 endpoint STA báo.

Endpoint không có register phát thì **không tồn tại setup check để thực
hiện** — không có gì để constraint. **Tuyệt đối không "sửa" bằng cách xóa
false path của `uart_rx_i`**: làm vậy là bắt timing một đầu vào bất đồng bộ
như dữ liệu đồng bộ, tệ hơn nhiều so với cảnh báo.

### 8.2 "4 output không driver" — false positive

Bản review trước khẳng định *"STA cuối lại có path thật từ flip-flop tới cả
bốn output"* — **điều này không có căn cứ trong log**: bốn tên đó xuất hiện
**0 lần** trong `33-rcx_sta.log`. (Lý do vô hại: `report_checks` chỉ in top-N
đường xấu nhất, mà đường reg→output có slack rất dương.)

Kết luận vẫn là false positive, nhưng bằng chứng đúng phải là:

- cảnh báo phát ra ở pass `check` **ngay sau `insbuf`** (OpenLane issue #1827)
- DEF tạo đủ pin: `[INFO ODB-0130] Created 9 pins` (7 tín hiệu + VPWR/VGND)
- LVS = 0 error
- Tôi tái hiện lại bằng yosys 0.33: cùng lớp cảnh báo xuất hiện, nhưng trong
  netlist ghi ra thì port **thực sự có driver** (`.Y(uart_tx_o)`)

Xác nhận trên máy bạn bằng một lệnh:
```bash
grep -c 'uart_tx_o' runs/run_5/results/routing/secure_asic_top.nl.v
```

### 8.3 `ABC: Error: The network is combinational` — benign

Script của ABC chạy `retime -D ... -M 5` rồi `scleanup`. `scleanup` là lệnh
**sequential**, còn yosys đưa vào mạng combinational (flop do yosys xử lý
riêng), nên ABC từ chối và flow đi tiếp. Xuất hiện ở mọi run OpenLane có
synth strategy retime. Không cần sửa, nhưng **nên ghi trong báo cáo** để
giám khảo đọc file `.errors` không hiểu nhầm.

### 8.4 IR-drop — chấp nhận được, hạ mức ưu tiên

Worst IR drop **21,7 mV trên 1,8 V = 1,2%**, thấp hơn nhiều so với ngân sách
5% thông thường. Cảnh báo `VSRC location file not specified` là đúng, nhưng
thiết kế này **chưa có pad ring**, nên chưa tồn tại vị trí bump thật để khai
báo. Ghi chú trong báo cáo là đủ; chỉ cần làm thật khi tích hợp pad.

### 8.5 BLKSEQ trong AES — false positive

Nằm trong `function` thuần tổ hợp. Dùng `<=` trong function là **bất hợp
lệ**, nên blocking là bắt buộc. Verilator chỉ cảnh báo vì function được
**gọi** từ khối `always @(posedge ...)`.

---

## 9. Trạng thái kiểm chứng

```
REGRESSION SUMMARY: 8 passed, 0 failed        (exit code 0)
```

- Verilator `secure_asic_top` (8 file vào OpenLane): **0 error, 0 warning**
- Verilator `secure_soc_top`: còn 3 `BLKLOOPINIT` + 1 `UNOPTFLAT`, tất cả
  trong `ro_puf.v` — giới hạn của Verilator với ring oscillator, không phải
  lỗi thiết kế; Quartus 25.1 biên dịch file này với 0 error
- 16 file Python: 0 lỗi cú pháp
- `config.json`: JSON hợp lệ
- `sync_rtl.py`: 8/8 file khớp byte-for-byte
