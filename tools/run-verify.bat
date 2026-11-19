@echo off
chcp 65001 >nul
title OPPO Watch Agent Pet - Probe
rem Run verify-watch.ps1 on Windows PowerShell 5.1+ (no pwsh needed)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify-watch.ps1" -WaitSeconds 60
echo.
pause
