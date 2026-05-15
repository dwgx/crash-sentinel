@echo off
title PC Crash Sentinel - Monitor
cd /d "%~dp0"

echo ========================================
echo   PC Crash Sentinel
echo   Monitoring CPU + GPU every 5 seconds
echo   Close this window to stop
echo ========================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "CrashSentinel.ps1"

echo.
echo Monitor stopped.
pause
