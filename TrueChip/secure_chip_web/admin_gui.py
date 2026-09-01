"""Local administrator GUI for TrueChip enrollment.

This is intentionally not a Flask route and must not be deployed publicly.
"""

from __future__ import annotations

import os
import tkinter as tk
from datetime import date
from tkinter import messagebox, ttk

try:
    from .enrollment_service import EnrollmentError, enroll_chip
except ImportError:  # pragma: no cover - direct script execution path
    from enrollment_service import EnrollmentError, enroll_chip


class AdminGui(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("TrueChip - Local Enrollment Console")
        self.resizable(False, False)
        self._build_ui()

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=18)
        root.grid(sticky="nsew")

        ttk.Label(root, text="TRUECHIP ENROLLMENT", font=("Segoe UI", 15, "bold")).grid(
            row=0, column=0, columnspan=2, pady=(0, 4)
        )
        ttk.Label(
            root,
            text="Chi dung tren may quan tri. Khong chia se ung dung cung database URL.",
            foreground="#8a1c1c",
        ).grid(row=1, column=0, columnspan=2, pady=(0, 14))

        self.uid = self._field(root, 2, "UID / PUF ID (32 Hex):")
        self.secret = self._field(root, 3, "Secret key (32 Hex):", masked=True)
        self.product = self._field(root, 4, "Product:", "TrueChip V2")
        self.manufacturer = self._field(root, 5, "Manufacturer:", "Huy Le Corp")
        self.pack_date = self._field(
            root, 6, "Pack date:", date.today().strftime("%d/%m/%Y")
        )

        env_state = "da cau hinh" if os.environ.get("TRUECHIP_DATABASE_URL") else "chua cau hinh"
        ttk.Label(root, text=f"Database URL: {env_state}").grid(
            row=7, column=0, columnspan=2, pady=(10, 8)
        )

        buttons = ttk.Frame(root)
        buttons.grid(row=8, column=0, columnspan=2, pady=(4, 0))
        ttk.Button(buttons, text="Enroll chip", command=self._enroll).grid(
            row=0, column=0, padx=5
        )
        ttk.Button(buttons, text="Clear", command=self._clear).grid(
            row=0, column=1, padx=5
        )

    @staticmethod
    def _field(parent, row, label, default="", masked=False):
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", pady=4)
        entry = ttk.Entry(parent, width=42, show="*" if masked else "")
        entry.grid(row=row, column=1, sticky="ew", pady=4)
        if default:
            entry.insert(0, default)
        return entry

    def _enroll(self) -> None:
        try:
            result = enroll_chip(
                self.uid.get(),
                self.secret.get(),
                self.product.get(),
                self.manufacturer.get(),
                self.pack_date.get(),
            )
        except EnrollmentError as exc:
            messagebox.showerror("Enrollment khong thanh cong", str(exc))
            return

        self.secret.delete(0, tk.END)
        messagebox.showinfo(
            "Enrollment thanh cong",
            f"Da ghi danh chip {result['uid_prefix']}\n"
            f"Product: {result['product']}\n"
            f"Pack date: {result['pack_date']}",
        )

    def _clear(self) -> None:
        self.uid.delete(0, tk.END)
        self.secret.delete(0, tk.END)


if __name__ == "__main__":
    AdminGui().mainloop()
