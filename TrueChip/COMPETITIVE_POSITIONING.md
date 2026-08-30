# TrueChip — Định vị cạnh tranh và kịch bản Q&A

Tài liệu nội bộ, dùng để viết phần mở đầu báo cáo và chuẩn bị phần hỏi đáp.
Dựa trên danh sách 34 đội dự thi.

---

## 1. Bối cảnh: 34 đội chia thành 6 nhóm xu hướng

| Nhóm | Số đội | Đội tiêu biểu |
|---|---|---|
| Hậu lượng tử (Kyber / Dilithium / ML-KEM) | ~7 | 7, 14, 16, 18, 23, 26, 27 |
| PUF + chống nhân bản phần cứng | 5 (kể cả TrueChip) | 4, 14, 29, 34, **25** |
| SoC tích hợp RISC-V | ~6 | 3, 10, 17, 22, 27, 34 |
| Kháng kênh kề / Hardware Trojan | 2 | 19, 21 |
| IP mật mã thuần, không có hệ thống ứng dụng | ~8 | 8, 12, 24, 28, 30, 32, 33 |
| Ứng dụng ngách độc đáo | 5 | 2 (LiDAR), 5 (chống nghe lén AI), 9 (CNN mã độc), 13 (Shamir), 15 (DMA firewall) |

**Hệ quả:** hậu lượng tử là trào lưu đông nhất — nghĩa là ban giám khảo sẽ
nghe rất nhiều bài về Kyber/ML-KEM. TrueChip **không cạnh tranh ở đó**, và
điều đó là lợi thế: bài của nhóm sẽ không bị so sánh trực tiếp với 7 bài cùng
chủ đề.

---

## 2. ⚠️ Đối thủ gần nhất: Team 4 — MiSilicon

| | TrueChip (đội 25) | MiSilicon (đội 4) |
|---|---|---|
| Đề tài | Chip xác thực chống hàng giả, Challenge-Response trên FPGA | PUF-Based Secure Element control by RISC-V Processor |
| Trường | ĐH Quốc tế, ĐHQG-HCM | ĐH Quốc tế, ĐHQG-HCM |
| GVHD | ThS. Võ Minh Thạnh | ThS. Võ Minh Thạnh |

**Cùng trường, cùng thầy hướng dẫn, cùng mảng PUF.** Ban giám khảo gần như
chắc chắn sẽ đặt hai bài cạnh nhau. Nhóm **phải chủ động** làm rõ khác biệt
trong báo cáo, thay vì để giám khảo tự suy diễn.

### Khác biệt nên nhấn mạnh

| Tiêu chí | TrueChip | Secure Element có RISC-V |
|---|---|---|
| Kiến trúc | Thiết bị chuyên dụng, FSM cứng, **không có CPU** | Có bộ xử lý chạy firmware |
| Bề mặt tấn công | Chỉ 2 lệnh qua UART (`GET_ID`, `CHALLENGE`) | Firmware, bus, bộ nhớ, chuỗi khởi động |
| Cách tấn công phần mềm | **Không tồn tại** — không có phần mềm chạy trên chip | Tràn bộ đệm, sửa firmware, tấn công chuỗi khởi động |
| Diện tích / công suất | Nhỏ hơn nhiều | Lớn hơn |
| Tính linh hoạt | Thấp — sửa giao thức phải làm lại chip | Cao — cập nhật firmware |
| Mục tiêu ứng dụng | Tem chống giả số lượng cực lớn, giá rẻ | Thiết bị đa dụng |

**Câu chốt cho báo cáo:**

> *"TrueChip cố tình không tích hợp bộ xử lý. Với bài toán tem xác thực chống
> hàng giả — nơi chip chỉ cần trả lời đúng hai lệnh và được sản xuất số lượng
> cực lớn với giá thấp — một CPU là chi phí và là bề mặt tấn công không cần
> thiết. Toàn bộ giao thức được cài đặt bằng máy trạng thái phần cứng, nên
> không tồn tại lớp phần mềm nào trên chip để khai thác."*

Đây là **lựa chọn kiến trúc có lý do**, không phải thiếu sót vì làm không kịp.
Trình bày theo hướng này biến điểm yếu tiềm tàng thành luận điểm chủ động.

---

## 3. Ba điểm mạnh nên đưa lên đầu báo cáo

### 3.1 Đã đi tới ASIC signoff thật trên SKY130A — luận điểm mạnh nhất

Phần lớn các đội dừng ở FPGA hoặc mô phỏng RTL. TrueChip có bằng chứng layout
thật:

- Detailed-route DRC: **0**
- Magic DRC: **0**
- KLayout DRC: **0** (công cụ độc lập với Magic)
- Netgen LVS: **0**
- KLayout XOR: **0**
- STA signoff 4 góc: setup **+1,50 ns**, hold **+0,09 ns**

Đây là thứ khó làm giả và khó tranh cãi. **Nên là slide thứ hai của bài
trình bày**, ngay sau slide giới thiệu bài toán.

### 3.2 Hệ thống đầu-cuối hoàn chỉnh, không phải một IP core rời

Chip → giao thức UART có CRC → server xác thực → database → client. Khoảng 8
đội (nhóm "IP mật mã thuần") nhiều khả năng chỉ có core và testbench, không có
ứng dụng minh họa chạy được.

Demo trực tiếp quét một sản phẩm thật và nhận kết quả AUTHENTIC/FAKE có sức
thuyết phục cao hơn nhiều so với một bảng thông số throughput.

### 3.3 Năng lực kỹ thuật thể hiện qua quá trình debug

Đây là điểm nhiều đội không có, và **nên làm hẳn một slide riêng**:

| Sự việc | Bằng chứng |
|---|---|
| Tự phát hiện lỗi P0 trong RO-PUF (`puf_id` luôn bằng 0 trên mọi board) | Mutation test: cùng một testbench chạy trên RTL cũ → FAIL, RTL mới → PASS |
| Phát hiện testbench cũ in `[PASS]` vô điều kiện mà không kiểm tra gì | Đã xóa, thêm bộ chặn tự động trong `run_regression.sh` |
| Dò thang tham số antenna có phương pháp (90 → 250 → 200) | Bảng 5 chỉ số đo ở cả ba điểm, chọn 250 có căn cứ |
| Phân biệt cảnh báo thật với false positive của công cụ | Tái hiện lại bằng Yosys 0.33 để chứng minh |

**Vì sao điều này quan trọng:** lỗi RO-PUF đã sống sót qua Quartus (0 error),
qua timing closure, và qua test trên board thật — vì chip vẫn xác thực đúng.
Chỉ có kiểm chứng chủ động mới tìm ra. Kể câu chuyện này cho thấy nhóm hiểu
rằng **"tool báo xanh" không đồng nghĩa với "thiết kế đúng"** — đó là tư duy
kỹ sư trưởng thành.

---

## 4. Kịch bản Q&A — các câu khó và cách trả lời

### "Sao không dùng RISC-V như các đội khác?"

> Bài toán của chúng em là tem xác thực số lượng cực lớn, giá thấp. Chip chỉ
> cần trả lời hai lệnh. Thêm CPU sẽ tăng diện tích, công suất, và tạo ra một
> lớp firmware có thể bị tấn công — trong khi không mang lại lợi ích nào cho
> đúng bài toán này. Đây là lựa chọn có chủ đích.

### "Sao không làm hậu lượng tử?"

> Mối đe dọa lượng tử nhắm vào mật mã khóa công khai (RSA, ECC). TrueChip
> dùng AES-128 khóa đối xứng, mà thuật toán Grover chỉ giảm độ an toàn hiệu
> dụng xuống khoảng một nửa số bit — nên hướng nâng cấp tự nhiên là chuyển
> sang AES-256, không phải thay bằng Kyber. Việc phân phối khóa hiện được xử
> lý ở tầng nhà máy chứ không qua trao đổi khóa công khai, nên bề mặt bị
> lượng tử đe dọa rất nhỏ.

### "PUF của các bạn có ổn định không?"

Trả lời trung thực, có số liệu (đây là câu dễ bị bắt bài nếu vòng vo):

> Chưa. Qua 20 lần đo trên cùng một board, intra-device Hamming distance
> trung bình 12,23%. RO-PUF hoạt động và đo được sai biệt vật lý thật, nhưng
> raw response chưa đủ ổn định để dùng trực tiếp làm khóa. Cần bổ sung fuzzy
> extractor hoặc enrollment mask — đây là hạng mục đã xác định rõ nhưng chưa
> triển khai do giới hạn thời gian. Trong một phiên nguồn liên tục thì khóa
> dẫn xuất ổn định, nên demo hoạt động đúng.

### "Layout ASIC có PUF không?"

> Không. `secure_asic_top` dùng seed hằng số, nên đúng tên gọi là *hardening
> lõi bảo mật số AES/UART*, không phải *chip PUF hoàn chỉnh*. RO-PUF nằm ở
> nhánh FPGA. Chúng em ghi rõ điều này thay vì gộp chung.

### "ERC chưa chạy được thì sao?"

Xem `SIGNOFF_DISCLOSURE_v7.2.md` mục 3 — đã có nguyên văn.

### "Khung response không có CRC, có phải lỗ hổng không?"

> Không. Toàn vẹn chống giả mạo đã do chính AES ciphertext đảm bảo — sai lệch
> dù một bit cũng bị phát hiện khi server tính lại và so khớp. CRC không có
> khóa nên không chống được kẻ tấn công chủ động; thứ nó thêm vào chỉ là khả
> năng phân biệt lỗi nhiễu đường truyền với hành vi đáng ngờ. Đó là cải thiện
> độ tin cậy vận hành, không thay đổi mức an toàn.

### "Giá dưới 1 USD/chip đã chứng minh chưa?"

> Chưa. Đó là mục tiêu kinh doanh, chưa phải kết quả suy ra từ layout hiện
> tại. Con số die area và cell count trong báo cáo là dữ liệu thật, còn giá
> thành phụ thuộc sản lượng, đóng gói và test — chúng em chưa có số liệu đó.

---

## 5. Ba điều tuyệt đối tránh khi trình bày

1. **Không tuyên bố "chip PUF hoàn chỉnh"** — layout ASIC không có PUF.
2. **Không trích cột `wns` trong `metrics.csv`** (`-27,02 ns`) — đó là STA
   trước place. Trích log signoff.
3. **Không đưa `diversified_key` lên slide hay video** — giá trị nhạy cảm.

---

## 6. Thứ tự slide đề xuất

| # | Nội dung |
|---|---|
| 1 | Bài toán hàng giả + giải pháp Challenge-Response (30 giây) |
| 2 | **Bằng chứng ASIC signoff SKY130A** — bảng DRC/LVS/XOR/STA |
| 3 | Kiến trúc hệ thống đầu-cuối (chip → UART → server → client) |
| 4 | Demo trực tiếp: hàng thật / hàng giả / replay / lockout |
| 5 | **Câu chuyện debug: lỗi P0 RO-PUF và cách phát hiện** |
| 6 | Giới hạn đã biết + hướng phát triển (fuzzy extractor, NFC/RFID) |

Slide 5 là slide tạo khác biệt. Đa số đội sẽ trình bày kết quả; ít đội trình
bày được **quá trình tìm ra lỗi mà mọi công cụ đều bỏ sót**.
