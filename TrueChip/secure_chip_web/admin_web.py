"""Local-only HTTP wrapper for the TrueChip enrollment HTML interface."""

from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlsplit

try:
    from .enrollment_service import (
        EnrollmentError,
        database_configured,
        enroll_chip,
        reprovision_chip,
    )
except ImportError:  # pragma: no cover - direct script execution path
    from enrollment_service import EnrollmentError, database_configured, enroll_chip, reprovision_chip


BASE_DIR = Path(__file__).resolve().parent


def _config():
    try:
        return json.loads((BASE_DIR / "admin_config.json").read_text(encoding="utf-8"))
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return {}


class AdminHandler(BaseHTTPRequestHandler):
    def _headers(self, content_type: str) -> None:
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; connect-src 'self'; form-action 'self'",
        )

    def _json(self, status: int, payload: dict) -> None:
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self._headers("application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:  # noqa: N802
        path = urlsplit(self.path).path
        if path in ("/", "/admin.html"):
            raw = (BASE_DIR / "admin.html").read_bytes()
            self.send_response(200)
            self._headers("text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        if path == "/api/status":
            self._json(200, {"database_configured": database_configured()})
            return
        self._json(404, {"message": "Not found"})

    def do_POST(self) -> None:  # noqa: N802
        if urlsplit(self.path).path != "/api/enroll":
            self._json(404, {"message": "Not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 8192:
                raise EnrollmentError("Request không hợp lệ.")
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            enroll_function = (
                reprovision_chip if payload.get("mode") == "reprovision" else enroll_chip
            )
            result = enroll_function(
                payload.get("uid", ""),
                payload.get("secret_key", ""),
                payload.get("product", ""),
                payload.get("manufacturer", ""),
                payload.get("pack_date", ""),
            )
        except (EnrollmentError, ValueError, TypeError, UnicodeDecodeError) as exc:
            self._json(400, {"message": str(exc)})
            return
        action = "cập nhật lại" if payload.get("mode") == "reprovision" else "ghi danh"
        self._json(200, {"message": f"Đã {action} chip {result['uid_prefix']} thành công."})

    def log_message(self, format, *args):  # noqa: A002, D401
        # Do not log request bodies or secrets to the terminal.
        return


def main() -> None:
    config = _config()
    host = str(config.get("listen_host", "127.0.0.1"))
    port = int(config.get("listen_port", 8765))
    if host not in ("127.0.0.1", "localhost"):
        raise RuntimeError("admin_web.py chỉ được phép lắng nghe trên máy cục bộ.")
    server = HTTPServer((host, port), AdminHandler)
    print(f"TrueChip local enrollment: http://127.0.0.1:{port}/")
    print("Nhan Ctrl+C de dung. Database URL khong duoc hien thi.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nDa dung local enrollment server.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
