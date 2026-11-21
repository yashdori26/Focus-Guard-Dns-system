@echo off
title FocusDNS Setup Launcher
:: Auto-detect and request Administrator Privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :run_setup
) else (
    echo Requesting Administrator permissions...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~dp0setup_focus_dns.bat\"\"' -Verb RunAs"
    exit /b
)

:run_setup
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_focus_dns.ps1"
echo.
echo Press any key to close this window...
pause >nul
