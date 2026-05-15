@echo off
setlocal enabledelayedexpansion
title PC Crash Sentinel - Setup
cd /d "%~dp0"

echo ==========================================
echo   PC Crash Sentinel - Installer
echo ==========================================
echo.
echo This will install scheduled tasks to:
echo   1. Auto-start monitor when you log in
echo   2. Auto-generate crash report on boot
echo.

:: Check admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo Creating scheduled tasks...

set "SCRIPT_DIR=%~dp0"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

:: Remove old tasks if they exist
schtasks /Delete /TN "CrashSentinel_Monitor" /F >nul 2>&1
schtasks /Delete /TN "CrashSentinel_Report" /F >nul 2>&1

:: Task 1: Start monitor on user logon
schtasks /Create /TN "CrashSentinel_Monitor" ^
    /TR "%PS_EXE% -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File \"%SCRIPT_DIR%CrashSentinel.ps1\"" ^
    /SC ONLOGON ^
    /RL HIGHEST ^
    /F

if %errorlevel% equ 0 (
    echo   [OK] Monitor task created
) else (
    echo   [FAIL] Monitor task creation failed
)

:: Task 2: Generate crash report on system startup
schtasks /Create /TN "CrashSentinel_Report" ^
    /TR "%PS_EXE% -NoProfile -ExecutionPolicy Bypass -File \"%SCRIPT_DIR%CrashReport.ps1\"" ^
    /SC ONSTART ^
    /DELAY 0000:30 ^
    /RL HIGHEST ^
    /F

if %errorlevel% equ 0 (
    echo   [OK] Report task created
) else (
    echo   [FAIL] Report task creation failed
)

echo.
echo ==========================================
echo   Installation complete!
echo.
echo   Monitor starts automatically on login.
echo   Crash reports generated after unexpected shutdown.
echo.
echo   To uninstall, run: setup.bat /uninstall
echo ==========================================

pause
exit /b
