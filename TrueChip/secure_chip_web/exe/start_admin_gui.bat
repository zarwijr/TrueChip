@echo off
setlocal
cd /d "%~dp0"
python ..\admin_gui.py
if errorlevel 1 pause
