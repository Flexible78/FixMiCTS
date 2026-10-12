@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DEVICE_TOOL.ps1" -Mode Diagnose
set "RESULT=%ERRORLEVEL%"
pause
exit /b %RESULT%
