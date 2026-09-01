# Hướng dẫn chạy Questa và chụp waveform

## 1. Chép đúng thư mục

Chép đè thư mục `Simulation` trong gói này vào:

```text
C:\GitHub\TrueChip\TrueChip\Simulation
```

Không chép thư mục `RTL` từ gói này vì gói chỉ chứa testbench và script.

## 2. Mở Questa

Mở **Questa FPGA Starter Edition**, sau đó trong cửa sổ Transcript chạy:

```tcl
cd C:/GitHub/TrueChip/TrueChip/Simulation/questa
vsim -gui
```

Nếu Questa đã mở sẵn design cũ, chạy trước:

```tcl
quit -sim
```

## 3. Chạy từng test có waveform

Mỗi lệnh dưới đây sẽ tự biên dịch, mở waveform, chạy test và dừng lại để
chụp ảnh:

```tcl
do run_one.do ro_puf_tb
```

Chụp xong mới chạy lệnh tiếp theo:

```tcl
do run_one.do tb_aes128
do run_one.do uart_tb
do run_one.do uart_echo_tb
do run_one.do cmd_parser_tb
do run_one.do auth_fsm_tb
do run_one.do secure_soc_top_tb
do run_one.do secure_asic_top_tb
```

`secure_asic_top_tb` có thể chạy vài phút vì có thời gian chờ chống gửi lại.

## 4. Ảnh nên chụp

Mỗi ảnh nên gồm cả **Wave window** và phần **Transcript** có dòng `[PASS]`.

| Test | Nội dung cần nhìn thấy | Tên ảnh gợi ý |
|---|---|---|
| `ro_puf_tb` | `ro_enable`, `cnt_clr_n`, counter giữ giá trị, `puf_valid`, `puf_id` khác 0 | `01_ro_puf_wave.png` |
| `tb_aes128` | `start`, `round_num`, `done`, ciphertext | `02_aes128_wave.png` |
| `uart_tb` | TX serial, RX serial, `rx_valid`, `rx_byte` | `03_uart_wave.png` |
| `cmd_parser_tb` | state parser, CRC, command hợp lệ/lỗi | `04_cmd_parser_wave.png` |
| `auth_fsm_tb` | challenge, AES handshake, replay status `03` | `05_auth_fsm_wave.png` |
| `secure_soc_top_tb` | PUF → KDF → UART trên FPGA top | `06_secure_soc_top_wave.png` |
| `secure_asic_top_tb` | UART challenge/response, `key_ready`, lockout | `07_secure_asic_top_wave.png` |

## 5. Zoom waveform

Sau khi script dừng, có thể dùng:

```tcl
wave zoom full
```

Đối với RO-PUF, để nhìn rõ thời điểm dừng đo:

```tcl
wave zoom range 2us 4us
```

Nếu chưa thấy cửa sổ waveform:

```tcl
view wave
wave zoom full
```

## 6. Vì sao bản này sửa được lỗi waveform trống

Các đường dẫn như `gen_cnt[0]` là mảng Verilog. Nếu không đặt trong dấu
ngoặc nhọn, Tcl hiểu `[0]` là lệnh cần thực thi và bỏ qua lệnh `add wave`.
Các script mới dùng dạng:

```tcl
add wave -radix unsigned {/ro_puf_tb/dut/gen_cnt[0]/cnt_r}
```

Ngoài ra mọi script đều dùng:

```text
-voptargs=+acc
-onfinish stop
```

để giữ lại tín hiệu nội bộ và giữ waveform sau khi testbench kết thúc.

## 7. Kiểm tra script trước khi chạy

Từ thư mục gốc project:

```powershell
python Simulation\questa\check_do_syntax.py
python Simulation\check_tb_portability.py Simulation\*.v Simulation\*.sv
```

Hai lệnh phải không báo `WOULD FAIL IN QUESTA`.
