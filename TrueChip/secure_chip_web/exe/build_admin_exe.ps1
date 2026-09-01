$ErrorActionPreference = "Stop"
$exeDir = $PSScriptRoot
$webDir = Split-Path -Parent $exeDir
$distDir = Join-Path $exeDir "dist"
$buildDir = Join-Path $exeDir "build"

Set-Location $webDir
python -m pip install pyinstaller
python -m PyInstaller --noconfirm --clean --onefile --windowed `
  --name TrueChipEnrollment `
  --distpath $distDir `
  --workpath $buildDir `
  --specpath $exeDir `
  --hidden-import psycopg2 `
  .\admin_gui.py

Write-Host "Created $distDir\TrueChipEnrollment.exe"
