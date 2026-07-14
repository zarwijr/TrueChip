# secure_chip_web — cấu trúc đã dọn lại

Đây là phần phần mềm (Python/web) của project `SecureSoC` — nằm cùng cấp với
`quartus/`, `rtl/`, `sim/` (phần FPGA/HDL, không đổi gì ở đó). Bên trong,
mọi thứ được tách theo **vai trò**, dùng chung 1 bản `secure_chip_common.py`
duy nhất trong `common/` để tránh lệch code khi sửa.

```
secure_chip_web/
├── common/
│   └── secure_chip_common.py   <- helper mật mã/protocol dùng chung, CHỈ 1 bản duy nhất
│
├── server/                     <- server xác thực mật mã gốc (nói chuyện qua UART với FPGA)
│   └── mock_server.py
│
├── client/                     <- công cụ PC/tester, nói chuyện UART trực tiếp với FPGA
│   ├── chip_tester.py
│   └── demo_scenarios.py
│
├── tools/                      <- script debug/lab, KHÔNG dùng lúc vận hành thật
│   └── verify_aes.py
│
├── web/                        <- cổng web: tra cứu công khai + dashboard nhà sản xuất
│   ├── app.py
│   ├── preview_demo.html       <- bản demo tĩnh, mở trực tiếp bằng trình duyệt, không cần chạy server
│   ├── README_WEB.md
│   └── templates/
│       ├── base.html
│       ├── home.html
│       ├── lookup.html
│       ├── login.html
│       ├── register.html
│       ├── dashboard.html
│       └── chip_form.html
│
├── data/                       <- nơi chứa secure_chip.db lúc chạy (không commit lên git)
│
├── requirements.txt             <- cài 1 lần, dùng chung cho cả server/client/tools/web
├── .gitignore
└── README.md                    <- file này
```

## Cài đặt (làm 1 lần)

```bash
cd secure_chip_web
pip install -r requirements.txt
```

## Chạy server xác thực mật mã gốc (nói chuyện UART với FPGA thật)

```bash
cd secure_chip_web
python server/mock_server.py init-db
python server/mock_server.py register-chip --uid <UID_HEX> --key <KEY_HEX> --product "..." --manufacturer "..." --pack-date "..."
python server/mock_server.py serve --host 127.0.0.1 --port 5000
```

## Chạy PC tester / demo (cần FPGA thật cắm qua UART)

```bash
cd secure_chip_web
python client/chip_tester.py --port COM3 --server-url http://127.0.0.1:5000/verify
python client/demo_scenarios.py --port COM3 --server-url http://127.0.0.1:5000/verify
```

## Chạy web portal (tra cứu công khai + dashboard NSX, không cần FPGA)

```bash
cd secure_chip_web
python web/app.py
```
Mặc định: `http://127.0.0.1:5050`. Xem chi tiết trong `web/README_WEB.md`.

## Cross-check AES lúc debug FPGA

```bash
cd secure_chip_web
python tools/verify_aes.py --uid <UID_HEX> --nonce <NONCE_HEX> --key <KEY_HEX> --response <RESPONSE_HEX>
```

## Vì sao mỗi script vẫn chạy được dù nằm ở thư mục con khác nhau?

Mỗi file (`mock_server.py`, `chip_tester.py`, `demo_scenarios.py`, `verify_aes.py`,
`app.py`) đều có đoạn code tự thêm `common/` vào đường tìm module lúc khởi động:

```python
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "common"))
```

Nhờ vậy chỉ cần sửa `common/secure_chip_common.py` **một lần duy nhất**, mọi
script dùng nó đều tự động cập nhật — không phải sửa nhiều bản trùng lặp.
`mock_server.py` và `web/app.py` cũng tự tính đường dẫn `data/secure_chip.db`
theo kiểu tương tự, nên chạy từ đâu cũng ra đúng 1 database duy nhất
(trừ khi bạn tự đặt biến môi trường `SECURE_CHIP_DB` để trỏ chỗ khác).

**Quan trọng**: `server/` và `web/` mặc định dùng chung `data/secure_chip.db`.
Chip đăng ký qua `mock_server.py register-chip` sẽ không có `manufacturer_id`
(vì được đăng ký ngoài dashboard) nên sẽ không hiện trong dashboard nhà sản
xuất — nhưng vẫn tra cứu được bình thường ở trang `/lookup` công khai.
