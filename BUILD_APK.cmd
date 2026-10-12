@echo off
setlocal
cd /d "%~dp0"
echo ===============================================
echo  Fix MiCTS - build personal Android APK
 echo ===============================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BUILD_APK.ps1"
if errorlevel 1 (
  echo.
  echo BUILD FAILED. Copy the error and send it to ChatGPT.
  pause
  exit /b 1
)
echo.
echo APK ready: %~dp0FixMiCTS.apk
echo Next: INSTALL_TO_VIVO.cmd
pause
