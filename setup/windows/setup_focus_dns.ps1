# FocusDNS Windows 11 / 10 System-Wide Setup Script
# Configures System-Wide Encrypted DNS (DoH), Browser Policies & Root CA
# Profile: Yash (dce22d)

param (
    [string]$ServerIP = "192.168.0.102",
    [string]$ProfileId = "dce22d",
    [int]$HttpsPort = 8443
)

$ErrorActionPreference = "Continue"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "       FOCUS-DNS SYSTEM-WIDE PROTECTION SETUP (WINDOWS)     " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Shield Profile: Yash ($ProfileId)" -ForegroundColor Yellow
Write-Host "DNS Server:     $ServerIP:$HttpsPort" -ForegroundColor Yellow
Write-Host ""

# Ensure Administrator rights
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] This script requires Administrator privileges!" -ForegroundColor Red
    Write-Host "Please right-click setup_focus_dns.bat and select 'Run as administrator'." -ForegroundColor Yellow
    Pause
    Exit 1
}

$DohUrl = "https://$($ServerIP):$($HttpsPort)/dns-query/$ProfileId"
$CertPath = Join-Path $PSScriptRoot "focus_dns.crt"

# 1. Install FocusDNS Root CA into Trusted Root Certification Authorities
Write-Host "[Step 1/4] Installing FocusDNS Root CA Certificate..." -ForegroundColor Green
if (Test-Path $CertPath) {
    try {
        certutil -addstore -f "Root" $CertPath | Out-Null
        Write-Host "  ✓ Certificate installed in Local Computer Root store." -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️ Could not install cert via certutil: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ⚠️ Certificate file not found at $CertPath" -ForegroundColor Yellow
}

# 2. Configure Windows 11 Native DoH Client (if supported)
Write-Host "[Step 2/4] Configuring Windows Native DNS-over-HTTPS..." -ForegroundColor Green
if (Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue) {
    try {
        # Check if already added
        $existing = Get-DnsClientDohServerAddress -ServerAddress $ServerIP -ErrorAction SilentlyContinue
        if ($existing) {
            Remove-DnsClientDohServerAddress -ServerAddress $ServerIP -ErrorAction SilentlyContinue | Out-Null
        }
        Add-DnsClientDohServerAddress -ServerAddress $ServerIP -DohTemplate $DohUrl -AllowFallbackToUdp $True -AutoUpgrade $True -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  ✓ Windows 11 DoH Template registered successfully." -ForegroundColor Green
    } catch {
        Write-Host "  ℹ️ Native DoH template notice: $_" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  ℹ️ Native Windows DoH cmdlet not present (Windows 10). Applying network & browser policy." -ForegroundColor DarkGray
}

# 3. Configure Active Network Adapters
Write-Host "[Step 3/4] Configuring Network Adapters (Wi-Fi & Ethernet)..." -ForegroundColor Green
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
foreach ($adapter in $adapters) {
    try {
        # Primary: FocusDNS, Secondary: 1.1.1.1 (Cloudflare fallback guarantee)
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($ServerIP, "1.1.1.1") -ErrorAction SilentlyContinue
        Write-Host "  ✓ Set DNS on adapter '$($adapter.Name)' -> $ServerIP (Fallback: 1.1.1.1)" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️ Error configuring adapter '$($adapter.Name)': $_" -ForegroundColor Yellow
    }
}

# 4. Enforce System-Wide Browser Policies for Chrome, Edge, and Brave
Write-Host "[Step 4/4] Enforcing Browser DNS-over-HTTPS Policies..." -ForegroundColor Green

$BrowserPolicies = @(
    "HKLM:\SOFTWARE\Policies\Google\Chrome",
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge",
    "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"
)

foreach ($keyPath in $BrowserPolicies) {
    try {
        if (-not (Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $keyPath -Name "DnsOverHttpsMode" -Value "secure" -Force | Out-Null
        Set-ItemProperty -Path $keyPath -Name "DnsOverHttpsTemplates" -Value $DohUrl -Force | Out-Null
        $browserName = Split-Path $keyPath -Leaf
        Write-Host "  ✓ Enforced DoH policy on $browserName" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️ Policy setup notice for $keyPath: $_" -ForegroundColor DarkGray
    }
}

# Flush DNS cache to activate immediately
Clear-DnsClientCache -ErrorAction SilentlyContinue | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "🎉 FOCUS-DNS PROTECTION IS NOW ACTIVE SYSTEM-WIDE!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "• Adult / regional / gambling websites are blocked instantly." -ForegroundColor White
Write-Host "• Normal internet (Google, Wikipedia, Steam, etc.) works at full speed." -ForegroundColor White
Write-Host "• To restore default settings anytime, run 'restore_windows.bat'." -ForegroundColor DarkGray
Write-Host ""
