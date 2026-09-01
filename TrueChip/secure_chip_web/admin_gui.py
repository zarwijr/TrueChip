"""Local desktop enrollment console for TrueChip.

This is the only enrollment interface shipped in this package. It uses the
same enrollment_service as factory_tool.py and never exposes an HTTP route.
"""

from __future__ import annotations

import tkinter as tk
from datetime import date
from tkinter import messagebox, simpledialog, ttk

try:
    from .enrollment_service import (
        EnrollmentError,
        database_configured,
        database_source,
        enroll_chip,
        list_chips,
        reprovision_chip,
        save_database_url,
        test_connection,
    )
except ImportError:  # direct script/EXE execution
    from enrollment_service import (
        EnrollmentError,
        database_configured,
        database_source,
        enroll_chip,
        list_chips,
        reprovision_chip,
        save_database_url,
        test_connection,
    )


class AdminGui(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("TrueChip - Trạm ghi danh chip")
        self.geometry("760x650")
        self.minsize(700, 570)
        self._build_ui()
        self._refresh_status()
        self._load_chips()

    def _build_ui(self) -> None:
        outer = ttk.Frame(self, padding=22)
        outer.pack(fill="both", expand=True)

        ttk.Label(outer, text="TRUECHIP ENROLLMENT", font=("Segoe UI", 18, "bold")).pack(anchor="w")
        ttk.Label(
            outer,
            text="Desktop admin console · dùng chung logic với factory_tool.py",
            foreground="#637083",
        ).pack(anchor="w", pady=(2, 14))

        notice = ttk.Label(
            outer,
            text="Chỉ dùng trên máy quản trị. Không chia sẻ Secret Key hoặc database URL.",
            foreground="#8a1c1c",
        )
        notice.pack(anchor="w", pady=(0, 10))

        status_row = ttk.Frame(outer)
        status_row.pack(fill="x", pady=(0, 10))
        self.status = ttk.Label(status_row, text="Đang kiểm tra cấu hình...")
        self.status.pack(side="left", fill="x", expand=True)
        ttk.Button(status_row, text="Cấu hình URL", command=self._configure_url).pack(side="right", padx=4)
        ttk.Button(status_row, text="Thử kết nối", command=self._test_db).pack(side="right")

        form = ttk.LabelFrame(outer, text="Thông tin chip", padding=16)
        form.pack(fill="x")
        form.columnconfigure(1, weight=1)

        self.uid = self._field(form, 0, "UID / PUF ID (32 Hex):")
        self.secret = self._field(form, 1, "Diversified key (32 Hex):", masked=True)
        self.product = self._field(form, 2, "Product:", "TrueChip V2.1.9.01")
        self.manufacturer = self._field(form, 3, "Manufacturer:", "Huy Le Corp")
        self.pack_date = self._field(form, 4, "Pack date:", date.today().strftime("%d/%m/%Y"))

        actions = ttk.Frame(form)
        actions.grid(row=5, column=0, columnspan=2, sticky="e", pady=(16, 0))
        self.enroll_button = ttk.Button(actions, text="Enroll chip mới", command=self._enroll)
        self.enroll_button.pack(side="left", padx=4)
        self.reprovision_button = ttk.Button(actions, text="Cập nhật key chip cũ", command=self._reprovision)
        self.reprovision_button.pack(side="left", padx=4)
        ttk.Button(actions, text="Xóa form", command=self._clear).pack(side="left", padx=4)

        list_frame = ttk.LabelFrame(outer, text="Chip đã ghi danh (không hiển thị Secret Key)", padding=10)
        list_frame.pack(fill="both", expand=True, pady=(16, 0))
        list_frame.rowconfigure(0, weight=1)
        list_frame.columnconfigure(0, weight=1)
        columns = ("uid", "product", "manufacturer", "pack_date")
        self.table = ttk.Treeview(list_frame, columns=columns, show="headings", height=8)
        headings = {"uid": "UID", "product": "Product", "manufacturer": "Manufacturer", "pack_date": "Pack date"}
        widths = {"uid": 250, "product": 160, "manufacturer": 150, "pack_date": 100}
        for column in columns:
            self.table.heading(column, text=headings[column])
            self.table.column(column, width=widths[column], anchor="w")
        scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=self.table.yview)
        self.table.configure(yscrollcommand=scrollbar.set)
        self.table.grid(row=0, column=0, sticky="nsew")
        scrollbar.grid(row=0, column=1, sticky="ns")
        ttk.Button(list_frame, text="Tải lại danh sách", command=self._load_chips).grid(row=1, column=0, sticky="e", pady=(8, 0))

    @staticmethod
    def _field(parent, row, label, default="", masked=False):
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", padx=(0, 14), pady=6)
        entry = ttk.Entry(parent, width=54, show="*" if masked else "")
        entry.grid(row=row, column=1, sticky="ew", pady=6)
        if default:
            entry.insert(0, default)
        return entry

    def _refresh_status(self) -> None:
        if database_configured():
            self.status.configure(text=f"Database URL: đã cấu hình ({database_source()})", foreground="#14723e")
        else:
            self.status.configure(text="Database URL: chưa cấu hình", foreground="#af2525")

    def _configure_url(self) -> None:
        url = simpledialog.askstring(
            "Cấu hình database",
            "Dán External PostgreSQL URL mới (không lưu vào mã nguồn):",
            show="*",
            parent=self,
        )
        if not url:
            return
        try:
            source = save_database_url(url)
            info = test_connection()
            self._refresh_status()
            self._load_chips()
            messagebox.showinfo("Kết nối thành công", f"Đã lưu vào {source}.\nCó {info['chips']} chip trong database.")
        except EnrollmentError as exc:
            messagebox.showerror("Không thể cấu hình", str(exc))

    def _test_db(self) -> None:
        try:
            info = test_connection()
            self._refresh_status()
            messagebox.showinfo("Database OK", f"Kết nối thành công. Có {info['chips']} chip.")
            self._load_chips()
        except EnrollmentError as exc:
            messagebox.showerror("Database lỗi", str(exc))

    def _payload(self):
        return (
            self.uid.get(), self.secret.get(), self.product.get(),
            self.manufacturer.get(), self.pack_date.get()
        )

    def _enroll(self) -> None:
        try:
            result = enroll_chip(*self._payload())
            self.secret.delete(0, tk.END)
            self._load_chips()
            messagebox.showinfo("Thành công", f"Đã ghi danh chip {result['uid_prefix']}.")
        except EnrollmentError as exc:
            # A repeated UID is expected when the same FPGA is tested again.
            # Keep the safe default (no silent overwrite), but offer the
            # explicit factory-style re-provision action from this GUI.
            if "đã tồn tại" in str(exc):
                if messagebox.askyesno(
                    "UID đã tồn tại",
                    "UID này đã có trong database.\n\n"
                    "Bạn có muốn GHI ĐÈ key bằng key hiện tại của FPGA không?",
                    parent=self,
                ):
                    self._reprovision(confirm=False)
                return
            messagebox.showerror("Ghi danh không thành công", str(exc))

    def _reprovision(self, confirm=True) -> None:
        if confirm and not messagebox.askyesno(
            "Xác nhận cập nhật key",
            "Thao tác này sẽ GHI ĐÈ key hiện tại của UID.\n\nTiếp tục?",
            parent=self,
        ):
            return
        try:
            result = reprovision_chip(*self._payload())
            self.secret.delete(0, tk.END)
            self._load_chips()
            messagebox.showinfo("Cập nhật thành công", f"Đã cập nhật key cho chip {result['uid_prefix']}.")
        except EnrollmentError as exc:
            messagebox.showerror("Cập nhật không thành công", str(exc))

    def _load_chips(self) -> None:
        for item in self.table.get_children():
            self.table.delete(item)
        try:
            for chip in list_chips():
                self.table.insert("", "end", values=(
                    chip["uid"], chip["product"], chip["manufacturer"], chip["pack_date"]
                ))
        except EnrollmentError:
            pass

    def _clear(self) -> None:
        self.uid.delete(0, tk.END)
        self.secret.delete(0, tk.END)


if __name__ == "__main__":
    AdminGui().mainloop()
