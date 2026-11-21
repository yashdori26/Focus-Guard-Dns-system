@echo off
title FocusDNS Restore Defaults
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :run_restore
) else (
    echo Requesting Administrator permissions...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~dp0restore_windows.bat\"\"' -Verb RunAs"
    exit /b
)

:run_restore
cls
echo ============================================================
echo         FOCUS-DNS RESTORE DEFAULT WINDOWS SETTINGS          
echo ============================================================
echo.
echo Resetting DNS to automatic (DHCP) on all network adapters...
powershell -NoProfile -Command "Get-NetAdapter | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue }"

echo Removing Browser DNS-over-HTTPS enforcement policies...
powershell -NoProfile -Command "Remove-Item -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -Path 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' -Recurse -Force -ErrorAction SilentlyContinue"

echo Flushing DNS cache...
ipconfig /flushdns >nul

echo.
echo Default Windows DNS and browser settings have been successfully restored.
echo.
echo Press any key to close this window...
pause >nul
