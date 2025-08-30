@echo off
setlocal
rem === One-click wrapper for Start-MiniWeb.ps1 ===
set "PORT=8080"
set "ROOT=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-MiniWeb.ps1" -Port %PORT% -Root "%ROOT%"
