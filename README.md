# TrueChip
"Hàng thật, giá trị thật"
# TrueChip - Hướng Dẫn Cài Đặt và Chạy Dự Án

Dự án **TrueChip** là một repo trên GitHub tại địa chỉ: `https://github.com/zarwijr/TrueChip`.

Tài liệu này hướng dẫn chi tiết từng bước để clone, thiết lập môi trường, cài đặt thư viện phụ thuộc và vận hành dự án **TrueChip** trên máy tính cá nhân.

---

## 📋 1. Yêu Cầu Hệ Thống & Tiền Đề

Trước khi bắt đầu, hãy đảm bảo máy tính của bạn đã được cài đặt các công cụ sau:

- **Git**: Dùng để tải mã nguồn về máy. ([Tải Git](https://git-scm.com/))
- **Python**: Phiên bản 3.8 trở lên (khuyến nghị Python 3.10 hoặc 3.11). ([Tải Python](https://www.python.org/))
- **Pip / Virtualenv**: Trình quản lý gói và môi trường ảo của Python.
- **Node.js & NPM** *(Nếu dự án có phần Frontend)*: Phiên bản LTS mới nhất. ([Tải Node.js](https://nodejs.org/))

---

## 🚀 2. Hướng Dẫn Cài Đặt & Chạy Dự Án (Từng Bước)

### Bước 1: Clone Repository về máy
Mở Terminal (Linux/macOS) hoặc PowerShell / Command Prompt (Windows) và chạy lệnh:

```bash
git clone https://github.com/zarwijr/TrueChip.git
cd TrueChip
```

### Bước 2: Tạo và kích hoạt Môi trường ảo Python (Virtual Environment)
Đề xuất sử dụng môi trường ảo để tránh xung đột thư viện với hệ thống:

- **Trên Windows:**
  ```bash
  python -m venv venv
  venv\Scripts\activate
  ```

- **Trên macOS / Linux:**
  ```bash
  python3 -m venv venv
  source venv/bin/activate
  ```

### Bước 3: Cài đặt các thư viện phụ thuộc (Dependencies)
Kiểm tra danh sách các thư viện yêu cầu trong dự án và tiến hành cài đặt:

```bash
# Cài đặt các gói Python
pip install --upgrade pip
pip install -r requirements.txt
```

*(Lưu ý: Nếu dự án có tệp `setup.py` hoặc `pyproject.toml`, bạn có thể cài đặt bằng lệnh `pip install -e .`)*

### Bước 4: Cấu hình biến môi trường (Environment Variables)
Nếu dự án có tệp `.env.example`, hãy tạo một bản sao tên là `.env` và điền các giá trị cấu hình cần thiết:

```bash
# Trên Linux/macOS:
cp .env.example .env

# Trên Windows (PowerShell):
copy .env.example .env
```

Chỉnh sửa tệp `.env` để thêm các API key, đường dẫn cơ sở dữ liệu hoặc thông số cấu hình nếu dự án yêu cầu.

### Bước 5: Chạy ứng dụng

Tùy thuộc vào loại hình ứng dụng của TrueChip:

- **Chạy script Python chính:**
  ```bash
  python main.py
  # hoặc
  python app.py
  ```

- **Chạy ứng dụng Web (Streamlit / Gradio / Flask / FastAPI):**
  ```bash
  # Nếu dùng Streamlit:
  streamlit run app.py

  # Nếu dùng FastAPI / Uvicorn:
  uvicorn main:app --reload
  ```

---

## 📂 3. Cấu Trúc Mã Nguồn Dự Kiến

```text
TrueChip/
├── data/               # Thư mục chứa dữ liệu đầu vào / đầu ra
├── src/                # Mã nguồn chính của dự án
│   ├── __init__.py
│   ├── utils.py        # Các hàm tiện ích
│   └── model.py        # Mã xử lý logic / mô hình
├── main.py             # Điểm chạy chính của ứng dụng
├── requirements.txt    # Danh sách các thư viện Python
├── .env.example        # Mẫu tệp cấu hình biến môi trường
└── README.md           # Tệp hướng dẫn sử dụng
```

---

## 🛠️ 4. Xử Lý Lỗi Thường Gặp (Troubleshooting)

1. **Lỗi `ModuleNotFoundError`**:
   - Nguyên nhân: Chưa cài đặt đủ gói thư viện hoặc chưa kích hoạt môi trường ảo `venv`.
   - Khắc phục: Chạy lại `pip install -r requirements.txt` sau khi đảm bảo `venv` đang hoạt động.

2. **Lỗi phiên bản Python không tương thích**:
   - Kiểm tra phiên bản hiện tại bằng lệnh `python --version`.
   - Nếu dự án yêu cầu phiên bản cụ thể, hãy cân nhắc dùng `pyenv` hoặc Anaconda để quản lý phiên bản Python.

3. **Lỗi thiếu API Key / Config**:
   - Kiểm tra xem tệp `.env` đã được tạo đúng vị trí thư mục gốc và cung cấp đủ thông tin cấu hình chưa.

---

## 📝 5. Đóng Góp & Giấy Phép

- Repository: [zarwijr/TrueChip](https://github.com/zarwijr/TrueChip)
- Giấy phép: MIT License (hoặc theo khai báo trong repo).
