@echo off
setlocal
if "%~1"=="" (
  echo Usage: RUN_SMOKE_WINDOWS.bat "C:\path\to\Godot_v4.7.x-stable_win64.exe"
  exit /b 2
)
set "GODOT=%~1"
if not exist "%GODOT%" (
  echo Godot not found: %GODOT%
  exit /b 3
)
cd /d "%~dp0"
if not exist ".venv-experiments\Scripts\python.exe" (
  where py >nul 2>nul
  if not errorlevel 1 (
    py -3 -m venv .venv-experiments
  ) else (
    python -m venv .venv-experiments
  )
)
if errorlevel 1 exit /b %errorlevel%
call .venv-experiments\Scripts\activate.bat
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python tools\run_full_replication.py --repo . --godot "%GODOT%" --smoke-only
