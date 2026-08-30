# Công bố kết quả signoff — TrueChip v7.2

**Run nộp bài chính thức: `run_5`** (`HEURISTIC_ANTENNA_THRESHOLD = 250`).

`run_6` đã được chạy để dò tiếp ngưỡng 200 và **cho kết quả kém hơn** — chi
tiết ở mục 2. `config.json` đã được đặt lại về 250 để cấu hình khớp đúng với
run được nộp.

Mọi con số kiểm chứng lại bằng:

```bash
python3 OpenLane/secure_asic_top/check_signoff.py runs/run_5
```

---

## 1. Bảng kết quả signoff (dán thẳng vào báo cáo)

| Hạng mục | Công cụ | Kết quả |
|---|---|---|
| Detailed-route DRC | TritonRoute | **0 vi phạm** |
| Physical DRC | Magic | **0 vi phạm** |
| Physical DRC (độc lập) | KLayout | **0 vi phạm** |
| LVS | Netgen | **0 lỗi** |
| Layout XOR | KLayout | **0 khác biệt** |
| STA signoff (4 góc) | OpenSTA | setup **+1,50 ns**, hold **+0,09 ns** (worst) |
| Max capacitance | OpenSTA | **0 vi phạm** |
| ERC | CVC | **Không hoàn tất** — xem mục 3 |
| Antenna | OpenROAD ARC | **29 vi phạm** — xem mục 2 |
| Max slew / fanout | OpenSTA | 621 / 726 — xem mục 2 |

> **Lưu ý cho người đọc báo cáo:** cột `wns` trong `reports/metrics.csv`
> ghi `-27.02 ns`. **Đó không phải kết quả signoff** — nó được sao chép từ
> `logs/synthesis/*-sta.log`, tức STA trước bước place, dùng mô hình
> wireload. Số signoff thật nằm ở `logs/signoff/*rcx*sta*.log` và đều dương.

---

## 2. Antenna, slew và fanout — đánh đổi có chủ đích, không phải bỏ sót

**Công bố:**

> Thiết kế còn 29 vi phạm antenna (tỉ lệ Partial/Required cao nhất **2,09**;
> **23/29 nằm dưới 1,5**, tức chỉ vượt ngưỡng rất ít), cùng 621 vi phạm
> max-slew và 726 vi phạm max-fanout (604 trên đường dữ liệu, 122 trên cây
> clock). Đây là **điểm cân bằng được lựa chọn có chủ đích** sau khi dò thang
> ba điểm, không phải hạng mục bị bỏ quên.

**Cơ sở định lượng — đo thật ở cả ba điểm, không phải ước lượng:**

| Ngưỡng | Antenna (ratio xấu nhất) | Số diode | Max slew | Max fanout (data) | Setup slack |
|---|---|---|---|---|---|
| Không chèn heuristic (run_2) | 129 pin / 86 net | 950 | 0 | 0 | — |
| 90 (run_4) | **9 / 9** | **22.826** | **687** | **2.151** (2.026) | +0,46 ns |
| **250 (run_5) ← CHỌN** | **29 / 29** (2,09) | **6.654** | **621** | **726** (604) | **+1,50 ns** |
| 200 (run_6) | 27 / 27 (**2,93**) | 8.786 | 589 | 882 (757) | +1,36 ns |

**Đọc bảng này thế nào:** ngưỡng 200 chỉ giảm được **2** vi phạm antenna
(29→27) nhưng đổi lại **+2.132 diode**, tỉ lệ xấu nhất **tệ đi** (2,09→2,93),
fanout đường dữ liệu **tăng** 604→757, và setup slack **giảm** từ +1,50 xuống
+1,36 ns. Đây là điểm lợi ích cận biên âm rõ ràng, nên nhóm dừng thang dò và
chọn 250.

Việc chạy `run_6` **không lãng phí** — nó là bằng chứng cho thấy điểm vận hành
250 được chọn bằng đo đạc có phương pháp, không phải chọn ngẫu nhiên rồi dừng
ở kết quả đầu tiên chấp nhận được.

**Giải thích cơ chế** (phần này thể hiện hiểu biết kỹ thuật, nên nói rõ trong
Q&A):

Mỗi diode chống antenna thêm một chân vào net mà nó bảo vệ. Chèn diode diện
rộng (ngưỡng 90) làm **gấp đôi số chân trên hầu hết net** — fanout nhảy từ
≤10 lên ~20 — và vì diode được chèn **sau khi bộ resizer đã chạy xong**,
không có bước nào sửa lại thiệt hại đó. Kết quả: antenna giảm còn 9 nhưng đổi
lại 22.826 diode và 2.838 vi phạm design-rule.

Hai chỉ số này **kéo ngược chiều nhau**, nên không tồn tại một giá trị ngưỡng
nào đưa cả hai về 0. Nhóm đã dò thang ba điểm (90 → 250 → 200), đo đầy đủ 5
chỉ số ở mỗi điểm, và chọn 250 vì đó là điểm cân bằng tốt nhất — không phải
điểm đầu tiên gặp được.

**Mức độ rủi ro thực tế:** vi phạm antenna là rủi ro về **năng suất chế tạo**
(hư hỏng oxide cổng do tích điện trong lúc etch plasma), không phải lỗi chức
năng. Với 23/29 vi phạm dưới tỉ lệ 1,5 và toàn bộ nằm trên lớp met1, mức rủi
ro thấp. Trong một lần tapeout thật, bước tiếp theo là sửa **đúng 29 net này**
bằng jumper lên lớp cao hơn hoặc chèn diode có chọn lọc, thay vì tăng diode
toàn thiết kế.

**Về 122 vi phạm fanout trên cây clock:** đây là hiện tượng **kỳ vọng**, không
phải lỗi. CTS dựng cây clock theo `CTS_MAX_CAP` và `CTS_SINK_CLUSTERING_SIZE`
(25 sink mỗi buffer lá), **không** theo luật fanout của đường dữ liệu. Nên đọc
con số 604 (data) chứ không phải 726 (tổng).

---

## 3. CVC/ERC không hoàn tất — lỗi công cụ, không phải lỗi thiết kế

**Công bố:**

> Kiểm tra ERC bằng CVC không hoàn tất. Công cụ dừng ở giai đoạn liên kết
> device với model, với thông báo:
>
> ```
> CVC: Setting models ...
> unexpected error: Resistance error: missing parameter: l in l/w*48
> ```
>
> **CVC chưa từng chạy tới giai đoạn kiểm tra**, nên đây **không phải là một
> vi phạm ERC đã được xác nhận**. Đây là lỗi phân giải tham số giữa netlist
> trích xuất và file model của PDK.

Lỗi này xuất hiện giống hệt ở cả `run_5` và `run_6`, tức không phụ thuộc vào
cấu hình antenna.

**Bằng chứng CVC đã đọc được netlist bình thường** (tức netlist không hỏng):

```
CVC: 106167 instances, 139835 nets, 362924 devices.
```

**Những khả năng đã loại trừ** (nên nói ra để chứng minh nhóm đã điều tra
nghiêm túc, không chỉ bỏ qua):

| Nghi phạm | Kết luận |
|---|---|
| `sky130_ef_sc_hd__decap_12` | Là nguyên nhân ở `run_4` (*"could not find subcircuit"*). Đã sửa bằng cách ghi đè `DECAP_CELL` sang 4 cell `sky130_fd_sc_hd`. **Không phải nguyên nhân run_5/run_6** — các run này đi xa hơn hẳn. |
| `sky130_ef_sc_hd__fakediode_2` | **Đã loại trừ.** `FAKEDIODE_CELL` chỉ được dùng khi `DIODE_INSERTION_STRATEGY = 2`, mà biến này cố ý không được đặt. Cell này không hề có trong netlist. |
| Netlist hỏng | Đã loại trừ — CVC parse đủ 362.924 device trước khi dừng. |

**Vì sao vẫn đủ cơ sở để nộp:**

Ba công cụ signoff **độc lập với nhau** đều báo sạch: Magic DRC (0), KLayout
DRC (0), Netgen LVS (0). ERC kiểm tra các lớp lỗi khác (floating gate, bias
violation, over-voltage) mà DRC/LVS không phủ tới — nên nhóm **không tuyên bố
thiết kế đã sạch ERC**. Nhóm tuyên bố: kiểm tra này chưa thực hiện được do lỗi
công cụ, và đây là giới hạn đã biết, đã ghi rõ.

**Nếu giám khảo hỏi "vậy làm sao biết không có lỗi ERC?"** — trả lời trung
thực: *"Chúng em không biết chắc. Đó là lý do chúng em ghi rõ mục này chưa
hoàn tất thay vì bỏ trống. Với thiết kế thuần số dùng standard cell của PDK,
rủi ro ERC thấp vì không có mạch analog tự thiết kế, nhưng đó là lập luận về
xác suất chứ không phải bằng chứng."*

Kịch bản chẩn đoán kèm theo dự án:
`OpenLane/secure_asic_top/diagnose_cvc.py`

---

## 4. Các cảnh báo lành tính — nói trước để giám khảo không hiểu nhầm

| Cảnh báo | Bản chất |
|---|---|
| `ABC: Error: The network is combinational` trong `1-synthesis.errors` | Script ABC chạy `retime` rồi `scleanup`; `scleanup` là lệnh **sequential** còn yosys đưa vào mạng combinational nên ABC từ chối, flow đi tiếp bình thường. Xuất hiện ở mọi run OpenLane có synth strategy retime. |
| Yosys: 4 output *"used but has no driver"* | False positive của pass `check` chạy ngay sau `insbuf` (OpenLane issue #1827). DEF tạo đủ 9 pin, LVS pass. Đã tái hiện được bằng Yosys 0.33: netlist ghi ra **thực sự có driver**. |
| STA: *"There are 6 unconstrained endpoints"* | Là chân D của register mà nguồn duy nhất là hằng số, cộng flop đầu của bộ đồng bộ CDC được `constraints.sdc` **cố ý** false-path. Xác nhận bằng phân tích netlist: đúng 12 register có cone D không chạm register nào khác. Endpoint không có register phát thì không tồn tại setup check để thực hiện. |

---

## 5. Giới hạn khác cần ghi trong báo cáo

1. **`master_key` là hằng số trong ROM** — chỉ hợp lệ cho prototype. Bản
   thương mại cần OTP/eFuse.
2. **RO-PUF chưa được đặc trưng hóa.** Qua 20 lần đo trên cùng một board,
   intra-device Hamming distance trung bình **12,23%**. RO-PUF hoạt động
   nhưng raw response **chưa đủ ổn định để dùng trực tiếp làm khóa mật mã**;
   cần bổ sung fuzzy extractor hoặc enrollment mask. Trong phiên hoạt động
   liên tục (không reset), khóa dẫn xuất ổn định.
3. **Layout ASIC không chứa RO-PUF.** `secure_asic_top` dùng seed hằng số.
   Gọi đúng tên: *"hardening lõi bảo mật số AES/UART"*, không phải *"chip PUF
   hoàn chỉnh"*.
4. **Khung response chưa có CRC.** Toàn vẹn chống giả mạo đã được đảm bảo bởi
   chính AES ciphertext — sai lệch dù 1 bit cũng bị phát hiện khi server so
   khớp. CRC ở response chỉ giúp phân biệt lỗi nhiễu đường truyền với tấn
   công chủ động, **không thay đổi mức an toàn**. Đây là cải thiện độ tin cậy
   vận hành, không phải lỗ hổng bảo mật.
5. **Chưa có pad ring**, nên IR-drop dùng vị trí nguồn giả định. Worst IR drop
   đo được 21,7 mV trên 1,8 V = **1,2%**, thấp hơn nhiều ngân sách 5% thông
   thường.
6. **Không đưa `diversified_key` lên video hoặc báo cáo công khai** — đây là
   giá trị nhạy cảm.

---

## 6. Nguyên tắc chung khi trình bày

Nói trước các giới hạn này sẽ được đánh giá cao hơn nhiều so với để giám khảo
tự phát hiện. Điểm mạnh thật sự của dự án — **đã đi tới ASIC signoff thật trên
SKY130A với DRC/LVS/XOR sạch và timing đóng** — không hề bị suy giảm bởi việc
thừa nhận hai hạng mục chưa khép kín.
