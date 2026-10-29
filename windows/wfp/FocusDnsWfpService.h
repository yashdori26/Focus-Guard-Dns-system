/**
 * FocusDnsWfpService.h
 * Windows Filtering Platform (WFP) Native Kernel Firewall Service for FocusDNS.
 *
 * Inviolable Guarantees:
 * 1. Anti-Bypass Redirection:
 *    - All outbound UDP/TCP port 53 traffic intercepted and redirected to 127.0.0.1:5353.
 *    - Direct connections to rogue public DoH IPs (Cloudflare, Google, Quad9) blocked.
 * 2. Conditional Service Protection Law:
 *    - ServiceControlHandler rejects SERVICE_CONTROL_STOP if active focus or timer > 0.
 *    - 100% clean teardown and uninstallation permitted when idle.
 * 3. Life-Safety & OS Exemption:
 *    - svchost.exe (Windows Update), DHCP, loopback, and emergency endpoints are never blocked.
 */

#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsvc.h>
#include <fwpmu.h>
#include <initguid.h>
#include <string>
#include <vector>
#include <memory>
#include <atomic>
#include <mutex>

#pragma comment(lib, "fwpuclnt.lib")
#pragma comment(lib, "advapi32.lib")

namespace FocusDns {

// Provider GUID: {5D3E82A1-6B92-4C3D-8E1A-2F7B9C4D6E01}
DEFINE_GUID(
    FOCUS_DNS_WFP_PROVIDER_GUID,
    0x5d3e82a1, 0x6b92, 0x4c3d, 0x8e, 0x1a, 0x2f, 0x7b, 0x9c, 0x4d, 0x6e, 0x01
);

// Sublayer Core GUID: {B25C6718-47A1-4F2E-8CE3-0D44F2718E01}
DEFINE_GUID(
    FOCUS_DNS_WFP_SUBLAYER_CORE,
    0xb25c6718, 0x47a1, 0x4f2e, 0x8c, 0xe3, 0x0d, 0x44, 0xf2, 0x71, 0x8e, 0x01
);

// Sublayer Override GUID: {C98D7129-58B2-4E3F-9DF4-1E55F3829F02}
DEFINE_GUID(
    FOCUS_DNS_WFP_SUBLAYER_OVERRIDE,
    0xc98d7129, 0x58b2, 0x4e3f, 0x9d, 0xf4, 0x1e, 0x55, 0xf3, 0x82, 0x9f, 0x02
);

// Callout Redirect GUID: {A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
DEFINE_GUID(
    FOCUS_DNS_WFP_CALLOUT_REDIRECT,
    0xa1b2c3d4, 0xe5f6, 0x7890, 0xab, 0xcd, 0xef, 0x12, 0x34, 0x56, 0x78, 0x90
);

struct WfpFilterRecord {
    UINT64 filterId;
    std::wstring name;
    std::wstring targetApp;
    bool isExemption;
};

class FocusDnsWfpManager {
public:
    FocusDnsWfpManager();
    ~FocusDnsWfpManager();

    // Engine Lifecycle
    DWORD InitializeEngine();
    DWORD CloseEngine();
    bool IsEngineOpen() const { return m_engineHandle != nullptr; }

    // Sublayer & Callout Registration
    DWORD RegisterProviderAndSublayers();
    DWORD RegisterRedirectCallout();

    // Filter Compilation & Installation
    DWORD InstallCoreDnsRedirectFilters(USHORT localProxyPort = 5353);
    DWORD InstallDohBypassProtectionFilters();
    DWORD InstallSystemCriticalExemptions();
    DWORD InstallAppBlockadeFilter(const std::wstring& appPath, const std::wstring& appName);

    // Filter Teardown
    DWORD RemoveAllInstalledFilters();

    // State & Conditional Uninstallation Law
    void SetProtectionActive(bool active, int remainingSeconds);
    bool CanUninstall() const;
    int GetRemainingTimerSeconds() const;
    bool IsProtectionActive() const;

    // Filter Statistics
    size_t GetInstalledFilterCount() const;
    std::vector<WfpFilterRecord> GetFilterRecords() const;

private:
    HANDLE m_engineHandle;
    std::atomic<bool> m_isProtectionActive;
    std::atomic<int> m_remainingTimerSeconds;
    mutable std::mutex m_mutex;
    std::vector<WfpFilterRecord> m_activeFilters;

    DWORD AddFilterInternal(
        const std::wstring& name,
        const GUID& layerKey,
        const GUID& sublayerKey,
        UINT8 weight,
        FWP_ACTION_TYPE actionType,
        FWPM_FILTER_CONDITION0* conditions,
        UINT32 conditionCount,
        const GUID* calloutKey = nullptr,
        const std::wstring& targetApp = L"",
        bool isExemption = false
    );
};

class FocusDnsWindowsService {
public:
    static FocusDnsWindowsService& Instance();

    void ServiceMain(DWORD argc, LPWSTR* argv);
    DWORD HandleControl(DWORD control, DWORD eventType, LPVOID eventData);

    DWORD StartServiceLoop();
    void StopService();

    FocusDnsWfpManager& GetWfpManager() { return m_wfpManager; }

private:
    FocusDnsWindowsService();
    ~FocusDnsWindowsService();

    SERVICE_STATUS m_serviceStatus;
    SERVICE_STATUS_HANDLE m_statusHandle;
    HANDLE m_stopEvent;
    FocusDnsWfpManager m_wfpManager;
    std::atomic<bool> m_isRunning;

    void SetServiceStatusState(DWORD state, DWORD exitCode = NO_ERROR, DWORD waitHint = 0);
    void RunIpcPipeServer();
};

} // namespace FocusDns
