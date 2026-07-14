---

# Hướng dẫn Chạy Mô phỏng & Nạp FPGA: Secure SoC

### 1. Cấu trúc thư mục

* **`/rtl`**: Chứa toàn bộ mã nguồn thiết kế (Verilog).
* **`/sim`**: Chứa file Testbench.
* **`compile.do`**: Kịch bản chạy mô phỏng tự động cho ModelSim.

### 2. Hướng dẫn chạy mô phỏng (ModelSim/QuestaSim)

1. **Mở ModelSim** và trỏ đường dẫn (**File -> Change Directory...**) về thư mục gốc chứa file `compile.do`.
2. Tại cửa sổ **Transcript**, gõ lệnh: `do compile.do`.
3. **Mô phỏng thủ công**: Sau khi chạy lệnh trên, các tín hiệu sẽ tự động được thêm vào cửa sổ **Wave**. Bạn có thể chọn module bất kỳ trong tab **"sim"**, nhấn **Restart**, và bấm **Run -all** để mô phỏng theo cách thông thường.

### 3. Hướng dẫn nạp lên FPGA (Quartus Prime)

Nếu bạn muốn nạp thiết kế này lên bo mạch FPGA thực tế bằng **Intel Quartus Prime**, hãy thực hiện các bước sau:

1. **Tạo Project mới**: Mở Quartus, chọn *File -> New Project Wizard* và đặt tên project và đặt folder ở địa chỉ bạn mong muốn.
2. **Thêm mã nguồn**:
* Trong cửa sổ *Add Files*, chọn tất cả các file có đuôi `.v` nằm trong thư mục **`/rtl`**.
* **Lưu ý**: Không thêm các file Testbench (`_tb.v`) vào project Quartus vì chúng chỉ dùng để mô phỏng, không dùng để nạp phần cứng.


3. **Thiết lập Top-Level**: Đảm bảo file `secure_soc_top.v` được thiết lập là *Top-Level Entity* của project.
4. **Pin Assignment**: Gán chân (Pin Planner) cho các tín hiệu `clk`, `rst_n`, `rx`, `tx` và `led_state` cho đúng với sơ đồ chân trên bo mạch của bạn.
5. **Compile & Program**: Nhấn *Start Compilation* và nạp file `.sof` vào FPGA.

### 4. Lưu ý

* Các file tạm (`work`, `*.vcd`, `*.wlf`, `modelsim.ini`) đã được xóa để tối ưu dung lượng.
* Nếu gặp lỗi *Cannot open file*, hãy kiểm tra lại đường dẫn (Directory) ở bước 2 phần mô phỏng.

---
