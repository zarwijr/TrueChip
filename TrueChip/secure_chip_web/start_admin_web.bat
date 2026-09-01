@echo off
setlocal
cd /d "%~dp0"
start "" powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Sleep -Seconds 1; Start-Process 'http://127.0.0.1:8765/'"
python admin_web.py
pause
