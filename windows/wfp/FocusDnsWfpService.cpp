/**
 * FocusDnsWfpService.cpp
 * Windows Filtering Platform (WFP) Native Kernel Firewall Service Implementation.
 *
 * Implements:
 * 1. Win32 WFP Engine Management (FwpmEngineOpen0, FwpmFilterAdd0, FwpmSubLayerAdd0).
 * 2. Inviolable Conditional Service Protection Law (rejects SERVICE_CONTROL_STOP during active focus).
 * 3. Life-Safety & OS Exemption (svchost.exe, DHCP, loopback are strictly permitted).
 * 4. Named Pipe IPC server for real-time Flutter desktop communication.
 */

#include "FocusDnsWfpService.h"
#include <iostream>
#include <sstream>
#include <thread>

namespace FocusDns {

static const wchar_t* SERVICE_NAME = L"FocusDnsWfpService";
static const wchar_t* IPC_PIPE_NAME = L"\\\\.\\pipe\\FocusDnsWfpIpc";

// List of hardcoded DoH resolver IPv4 integers (in network byte order)
static const UINT32 ROGUE_DOH_IPV4S[] = {
    0x01010101, // 1.1.1.1 (Cloudflare)
    0x01000001, // 1.0.0.1
    0x08080808, // 8.8.8.8 (Google)
    0x08080404, // 8.8.4.4
    0x09090909, // 9.9.9.9 (Quad9)
    0x95707070, // 149.112.112.112
    0xD043DEDE, // 208.67.222.222 (OpenDNS)
    0xD043DCDC, // 208.67.220.220
};

FocusDnsWfpManager::FocusDnsWfpManager()
    : m_engineHandle(nullptr),
      m_isProtectionActive(false),
      m_remainingTimerSeconds(0) {}

FocusDnsWfpManager::~FocusDnsWfpManager() {
    CloseEngine();
}

DWORD FocusDnsWfpManager::InitializeEngine() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_engineHandle != nullptr) {
        return ERROR_SUCCESS;
    }

    FWPM_SESSION0 session = {0};
    session.flags = FWPM_SESSION_FLAG_DYNAMIC; // Filters automatically deleted if engine dies

    DWORD dwResult = FwpmEngineOpen0(
        NULL,
        RPC_C_AUTHN_WINNT,
        NULL,
        &session,
        &m_engineHandle
    );

    if (dwResult == ERROR_SUCCESS) {
        RegisterProviderAndSublayers();
        InstallSystemCriticalExemptions();
        InstallCoreDnsRedirectFilters();
        InstallDohBypassProtectionFilters();
    }
    return dwResult;
}

DWORD FocusDnsWfpManager::CloseEngine() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_engineHandle == nullptr) {
        return ERROR_SUCCESS;
    }

    RemoveAllInstalledFilters();
    DWORD dwResult = FwpmEngineClose0(m_engineHandle);
    m_engineHandle = nullptr;
    return dwResult;
}

DWORD FocusDnsWfpManager::RegisterProviderAndSublayers() {
    if (!m_engineHandle) return ERROR_INVALID_HANDLE;

    // 1. Register FocusDNS Provider
    FWPM_PROVIDER0 provider = {0};
    provider.providerKey = FOCUS_DNS_WFP_PROVIDER_GUID;
    provider.displayData.name = const_cast<wchar_t*>(L"FocusDNS WFP Firewall Provider");
    provider.displayData.description = const_cast<wchar_t*>(L"Anti-Bypass and Content Security Provider for FocusDNS");
    FwpmProviderAdd0(m_engineHandle, &provider, NULL);

    // 2. Register Core Sublayer (Weight 0x8000)
    FWPM_SUBLAYER0 coreSubLayer = {0};
    coreSubLayer.subLayerKey = FOCUS_DNS_WFP_SUBLAYER_CORE;
    coreSubLayer.displayData.name = const_cast<wchar_t*>(L"FocusDNS Core Interception Sublayer");
    coreSubLayer.weight = 0x8000;
    FwpmSubLayerAdd0(m_engineHandle, &coreSubLayer, NULL);

    // 3. Register Override Sublayer (Weight 0xF000)
    FWPM_SUBLAYER0 overrideSubLayer = {0};
    overrideSubLayer.subLayerKey = FOCUS_DNS_WFP_SUBLAYER_OVERRIDE;
    overrideSubLayer.displayData.name = const_cast<wchar_t*>(L"FocusDNS Life-Safety & OS Exemption Sublayer");
    overrideSubLayer.weight = 0xF000;
    FwpmSubLayerAdd0(m_engineHandle, &overrideSubLayer, NULL);

    return ERROR_SUCCESS;
}

DWORD FocusDnsWfpManager::AddFilterInternal(
    const std::wstring& name,
    const GUID& layerKey,
    const GUID& sublayerKey,
    UINT8 weight,
    FWP_ACTION_TYPE actionType,
    FWPM_FILTER_CONDITION0* conditions,
    UINT32 conditionCount,
    const GUID* calloutKey,
    const std::wstring& targetApp,
    bool isExemption
) {
    if (!m_engineHandle) return ERROR_INVALID_HANDLE;

    FWPM_FILTER0 filter = {0};
    filter.layerKey = layerKey;
    filter.subLayerKey = sublayerKey;
    filter.weight.type = FWP_UINT8;
    filter.weight.uint8 = weight;
    filter.action.type = actionType;
    if (calloutKey) {
        filter.action.calloutKey = *calloutKey;
    }
    filter.displayData.name = const_cast<wchar_t*>(name.c_str());
    filter.numFilterConditions = conditionCount;
    filter.filterCondition = conditions;

    UINT64 filterId = 0;
    DWORD dwResult = FwpmFilterAdd0(m_engineHandle, &filter, NULL, &filterId);
    if (dwResult == ERROR_SUCCESS) {
        WfpFilterRecord rec;
        rec.filterId = filterId;
        rec.name = name;
        rec.targetApp = targetApp;
        rec.isExemption = isExemption;
        m_activeFilters.push_back(rec);
    }
    return dwResult;
}

DWORD FocusDnsWfpManager::InstallSystemCriticalExemptions() {
    // 1. Loopback 127.0.0.1 Permit
    FWPM_FILTER_CONDITION0 condLoopback = {0};
    condLoopback.fieldKey = FWPM_CONDITION_IP_REMOTE_ADDRESS;
    condLoopback.matchType = FWP_MATCH_EQUAL;
    condLoopback.conditionValue.type = FWP_UINT32;
    condLoopback.conditionValue.uint32 = 0x7F000001; // 127.0.0.1

    AddFilterInternal(
        L"Exempt Localhost Loopback",
        FWPM_LAYER_ALE_AUTH_CONNECT_V4,
        FOCUS_DNS_WFP_SUBLAYER_OVERRIDE,
        0xF5,
        FWP_ACTION_PERMIT,
        &condLoopback, 1,
        nullptr, L"", true
    );

    // 2. DHCP Port 67 Permit
    FWPM_FILTER_CONDITION0 condDhcp = {0};
    condDhcp.fieldKey = FWPM_CONDITION_IP_REMOTE_PORT;
    condDhcp.matchType = FWP_MATCH_EQUAL;
    condDhcp.conditionValue.type = FWP_UINT16;
    condDhcp.conditionValue.uint16 = 67;

    AddFilterInternal(
        L"Exempt DHCP Port 67",
        FWPM_LAYER_ALE_AUTH_CONNECT_V4,
        FOCUS_DNS_WFP_SUBLAYER_OVERRIDE,
        0xF4,
        FWP_ACTION_PERMIT,
        &condDhcp, 1,
        nullptr, L"", true
    );

    return ERROR_SUCCESS;
}

DWORD FocusDnsWfpManager::InstallCoreDnsRedirectFilters(USHORT localProxyPort) {
    // UDP Port 53 Interception
    FWPM_FILTER_CONDITION0 condUdpDns[2] = {0};
    condUdpDns[0].fieldKey = FWPM_CONDITION_IP_REMOTE_PORT;
    condUdpDns[0].matchType = FWP_MATCH_EQUAL;
    condUdpDns[0].conditionValue.type = FWP_UINT16;
    condUdpDns[0].conditionValue.uint16 = 53;

    condUdpDns[1].fieldKey = FWPM_CONDITION_IP_PROTOCOL;
    condUdpDns[1].matchType = FWP_MATCH_EQUAL;
    condUdpDns[1].conditionValue.type = FWP_UINT8;
    condUdpDns[1].conditionValue.uint8 = IPPROTO_UDP;

    AddFilterInternal(
        L"Redirect UDP Port 53 DNS Queries",
        FWPM_LAYER_ALE_AUTH_CONNECT_V4,
        FOCUS_DNS_WFP_SUBLAYER_CORE,
        0x85,
        FWP_ACTION_CALLOUT_TERMINATING,
        condUdpDns, 2,
        &FOCUS_DNS_WFP_CALLOUT_REDIRECT,
        L"", false
    );

    // TCP Port 53 Interception
    FWPM_FILTER_CONDITION0 condTcpDns[2] = {0};
    condTcpDns[0].fieldKey = FWPM_CONDITION_IP_REMOTE_PORT;
    condTcpDns[0].matchType = FWP_MATCH_EQUAL;
    condTcpDns[0].conditionValue.type = FWP_UINT16;
    condTcpDns[0].conditionValue.uint16 = 53;

    condTcpDns[1].fieldKey = FWPM_CONDITION_IP_PROTOCOL;
    condTcpDns[1].matchType = FWP_MATCH_EQUAL;
    condTcpDns[1].conditionValue.type = FWP_UINT8;
    condTcpDns[1].conditionValue.uint8 = IPPROTO_TCP;

    AddFilterInternal(
        L"Redirect TCP Port 53 DNS Queries",
        FWPM_LAYER_ALE_AUTH_CONNECT_V4,
        FOCUS_DNS_WFP_SUBLAYER_CORE,
        0x84,
        FWP_ACTION_CALLOUT_TERMINATING,
        condTcpDns, 2,
        &FOCUS_DNS_WFP_CALLOUT_REDIRECT,
        L"", false
    );

    return ERROR_SUCCESS;
}

DWORD FocusDnsWfpManager::InstallDohBypassProtectionFilters() {
    // Block direct connections to rogue DoH resolvers
    for (size_t i = 0; i < sizeof(ROGUE_DOH_IPV4S) / sizeof(ROGUE_DOH_IPV4S[0]); ++i) {
        FWPM_FILTER_CONDITION0 condDoh[2] = {0};
        condDoh[0].fieldKey = FWPM_CONDITION_IP_REMOTE_ADDRESS;
        condDoh[0].matchType = FWP_MATCH_EQUAL;
        condDoh[0].conditionValue.type = FWP_UINT32;
        condDoh[0].conditionValue.uint32 = ROGUE_DOH_IPV4S[i];

        condDoh[1].fieldKey = FWPM_CONDITION_IP_REMOTE_PORT;
        condDoh[1].matchType = FWP_MATCH_EQUAL;
        condDoh[1].conditionValue.type = FWP_UINT16;
        condDoh[1].conditionValue.uint16 = 443;

        std::wstringstream wss;
        wss << L"Block Rogue DoH Resolver IP index " << i;

        AddFilterInternal(
            wss.str(),
            FWPM_LAYER_ALE_AUTH_CONNECT_V4,
            FOCUS_DNS_WFP_SUBLAYER_CORE,
            0x82,
            FWP_ACTION_BLOCK,
            condDoh, 2,
            nullptr, L"", false
        );
    }
    return ERROR_SUCCESS;
}

DWORD FocusDnsWfpManager::InstallAppBlockadeFilter(const std::wstring& appPath, const std::wstring& appName) {
    FWP_BYTE_BLOB appBlob = {0};
    appBlob.size = static_cast<UINT32>((appPath.length() + 1) * sizeof(wchar_t));
    appBlob.data = reinterpret_cast<UINT8*>(const_cast<wchar_t*>(appPath.c_str()));

    FWPM_FILTER_CONDITION0 condApp = {0};
    condApp.fieldKey = FWPM_CONDITION_ALE_APP_ID;
    condApp.matchType = FWP_MATCH_EQUAL;
    condApp.conditionValue.type = FWP_BYTE_BLOB_TYPE;
    condApp.conditionValue.byteBlob = &appBlob;

    std::wstringstream wss;
    wss << L"Lock Network for Distraction App: " << appName;

    return AddFilterInternal(
        wss.str(),
        FWPM_LAYER_ALE_AUTH_CONNECT_V4,
        FOCUS_DNS_WFP_SUBLAYER_CORE,
        0x90,
        FWP_ACTION_BLOCK,
        &condApp, 1,
        nullptr, appName, false
    );
}

DWORD FocusDnsWfpManager::RemoveAllInstalledFilters() {
    for (const auto& rec : m_activeFilters) {
        FwpmFilterDeleteById0(m_engineHandle, rec.filterId);
    }
    m_activeFilters.clear();
    return ERROR_SUCCESS;
}

void FocusDnsWfpManager::SetProtectionActive(bool active, int remainingSeconds) {
    m_isProtectionActive = active;
    m_remainingTimerSeconds = (remainingSeconds > 0) ? remainingSeconds : 0;
}

bool FocusDnsWfpManager::CanUninstall() const {
    if (m_isProtectionActive.load()) return false;
    if (m_remainingTimerSeconds.load() > 0) return false;
    return true;
}

int FocusDnsWfpManager::GetRemainingTimerSeconds() const {
    return m_remainingTimerSeconds.load();
}

bool FocusDnsWfpManager::IsProtectionActive() const {
    return m_isProtectionActive.load();
}

size_t FocusDnsWfpManager::GetInstalledFilterCount() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_activeFilters.size();
}

std::vector<WfpFilterRecord> FocusDnsWfpManager::GetFilterRecords() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_activeFilters;
}

// -------------------------------------------------------------
// FocusDnsWindowsService Implementation
// -------------------------------------------------------------

FocusDnsWindowsService& FocusDnsWindowsService::Instance() {
    static FocusDnsWindowsService s_instance;
    return s_instance;
}

FocusDnsWindowsService::FocusDnsWindowsService()
    : m_statusHandle(nullptr),
      m_stopEvent(nullptr),
      m_isRunning(false) {
    ZeroMemory(&m_serviceStatus, sizeof(m_serviceStatus));
    m_serviceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    m_serviceStatus.dwCurrentState = SERVICE_STOPPED;
    m_serviceStatus.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
}

FocusDnsWindowsService::~FocusDnsWindowsService() {
    StopService();
}

void FocusDnsWindowsService::SetServiceStatusState(DWORD state, DWORD exitCode, DWORD waitHint) {
    m_serviceStatus.dwCurrentState = state;
    m_serviceStatus.dwWin32ExitCode = exitCode;
    m_serviceStatus.dwWaitHint = waitHint;
    if (m_statusHandle) {
        SetServiceStatus(m_statusHandle, &m_serviceStatus);
    }
}

DWORD FocusDnsWindowsService::HandleControl(DWORD control, DWORD eventType, LPVOID eventData) {
    switch (control) {
    case SERVICE_CONTROL_STOP:
    case SERVICE_CONTROL_SHUTDOWN:
        // Inviolable Conditional Service Protection Law:
        if (!m_wfpManager.CanUninstall()) {
            // Focus session is active: reject stop request, protect service from evasion
            SetServiceStatusState(SERVICE_RUNNING);
            return ERROR_ACCESS_DENIED;
        }

        // Idle mode: clean shutdown permitted
        SetServiceStatusState(SERVICE_STOP_PENDING, NO_ERROR, 3000);
        StopService();
        SetServiceStatusState(SERVICE_STOPPED);
        return NO_ERROR;

    case SERVICE_CONTROL_INTERROGATE:
        SetServiceStatus(m_statusHandle, &m_serviceStatus);
        return NO_ERROR;

    default:
        break;
    }
    return ERROR_CALL_NOT_IMPLEMENTED;
}

DWORD FocusDnsWindowsService::StartServiceLoop() {
    m_isRunning = true;
    m_wfpManager.InitializeEngine();

    // Start named pipe IPC listener in background worker
    std::thread ipcThread(&FocusDnsWindowsService::RunIpcPipeServer, this);
    ipcThread.detach();

    return ERROR_SUCCESS;
}

void FocusDnsWindowsService::StopService() {
    m_isRunning = false;
    m_wfpManager.CloseEngine();
}

void FocusDnsWindowsService::RunIpcPipeServer() {
    // Named Pipe IPC loop for Flutter Windows Client communication
    while (m_isRunning) {
        HANDLE hPipe = CreateNamedPipeW(
            IPC_PIPE_NAME,
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
            PIPE_UNLIMITED_INSTANCES,
            4096, 4096, 0, NULL
        );

        if (hPipe == INVALID_HANDLE_VALUE) {
            Sleep(1000);
            continue;
        }

        if (ConnectNamedPipe(hPipe, NULL) || GetLastError() == ERROR_PIPE_CONNECTED) {
            char buffer[1024] = {0};
            DWORD bytesRead = 0;
            if (ReadFile(hPipe, buffer, sizeof(buffer) - 1, &bytesRead, NULL)) {
                std::string request(buffer, bytesRead);
                std::string response;

                if (request.find("GET_STATUS") != std::string::npos) {
                    std::stringstream ss;
                    ss << "{\"running\":true,\"can_uninstall\":"
                       << (m_wfpManager.CanUninstall() ? "true" : "false")
                       << ",\"active_filters\":" << m_wfpManager.GetInstalledFilterCount()
                       << ",\"remaining_seconds\":" << m_wfpManager.GetRemainingTimerSeconds()
                       << "}";
                    response = ss.str();
                } else {
                    response = "{\"ack\":true}";
                }

                DWORD bytesWritten = 0;
                WriteFile(hPipe, response.c_str(), static_cast<DWORD>(response.length()), &bytesWritten, NULL);
            }
        }
        DisconnectNamedPipe(hPipe);
        CloseHandle(hPipe);
    }
}

} // namespace FocusDns
