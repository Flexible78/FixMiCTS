@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BATTERY_AUDIT.ps1" %*
set "RESULT=%ERRORLEVEL%"
echo.
echo Exit %RESULT%: 0=collected, 2=collected with gaps, 1=failed.
pause
exit /b %RESULT%
