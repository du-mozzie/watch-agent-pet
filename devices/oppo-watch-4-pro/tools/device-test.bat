@echo off
chcp 65001 >nul
title Watch Agent Pet - OPPO Device Test
rem Run device-test.ps1 on Windows PowerShell 5.1+ (no pwsh needed)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0device-test.ps1"
echo.
pause
