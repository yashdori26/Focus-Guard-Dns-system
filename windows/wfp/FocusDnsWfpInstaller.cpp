//
//  FocusDnsWfpInstaller.cpp
//  FocusGuard Windows Filtering Platform Service Installer & Anti-Tamper Engine
//

#include "FocusDnsWfpInstaller.h"
#include <iostream>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Fwpuclnt.lib")

namespace FocusGuard {

// Provider GUID: {5D3E82A1-6B92-4C3D-8E1A-2F7B9C4D6E01}
static const GUID FOCUS_GUARD_PROVIDER_KEY = 
    { 0x5d3e82a1, 0x6b92, 0x4c3d, { 0x8e, 0x1a, 0x2f, 0x7b, 0x9c, 0x4d, 0x6e, 0x01 } };

FocusDnsWfpInstaller::FocusDnsWfpInstaller() 
    : m_serviceName(L"FocusDnsWfpService"), m_engineHandle(nullptr) {
}

FocusDnsWfpInstaller::~FocusDnsWfpInstaller() {
    if (m_engineHandle) {
        FwpmEngineClose0(m_engineHandle);
        m_engineHandle = nullptr;
    }
}

UninstallPosture FocusDnsWfpInstaller::QueryUninstallationPosture(int* outRemainingSeconds) {
    bool isLocked = false;
    int remainingSec = 0;

    if (!CheckIpcLockState(isLocked, remainingSec)) {
        // Fallback: If IPC is unreachable, check registry fallback state
        HKEY hKey = nullptr;
        if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\FocusGuard\\Policy", 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
            DWORD dwLocked = 0;
            DWORD dwSize = sizeof(dwLocked);
            if (RegQueryValueExW(hKey, L"IsLocked", nullptr, nullptr, (LPBYTE)&dwLocked, &dwSize) == ERROR_SUCCESS) {
                isLocked = (dwLocked != 0);
            }
            DWORD dwRemaining = 0;
            dwSize = sizeof(dwRemaining);
            if (RegQueryValueExW(hKey, L"RemainingSeconds", nullptr, nullptr, (LPBYTE)&dwRemaining, &dwSize) == ERROR_SUCCESS) {
                remainingSec = static_cast<int>(dwRemaining);
            }
            RegCloseKey(hKey);
        }
    }

    if (outRemainingSeconds) {
        *outRemainingSeconds = remainingSec;
    }

    if (isLocked) {
        return UninstallPosture::LockedActiveFocus;
    }
    if (remainingSec > 0) {
        return UninstallPosture::LockedCountdownTimer;
    }

    return UninstallPosture::Allowed;
}

bool FocusDnsWfpInstaller::CheckIpcLockState(bool& isLocked, int& remainingSeconds) {
    HANDLE hPipe = CreateFileW(
        L"\\\\.\\pipe\\FocusDnsWfpIpc",
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr
    );

    if (hPipe == INVALID_HANDLE_VALUE) {
        return false;
    }

    const char queryCmd[] = "GET_STATUS\n";
    DWORD bytesWritten = 0;
    if (!WriteFile(hPipe, queryCmd, static_cast<DWORD>(strlen(queryCmd)), &bytesWritten, nullptr)) {
        CloseHandle(hPipe);
        return false;
    }

    char buffer[512] = { 0 };
    DWORD bytesRead = 0;
    if (ReadFile(hPipe, buffer, sizeof(buffer) - 1, &bytesRead, nullptr) && bytesRead > 0) {
        std::string response(buffer);
        // Simple JSON parse for "is_locked": true/false and "remaining_timer_seconds": N
        if (response.find("\"is_locked\": true") != std::string::npos ||
            response.find("\"is_locked\":true") != std::string::npos) {
            isLocked = true;
        } else {
            isLocked = false;
        }

        size_t timerPos = response.find("\"remaining_timer_seconds\":");
        if (timerPos != std::string::npos) {
            size_t start = timerPos + strlen("\"remaining_timer_seconds\":");
            while (start < response.length() && (response[start] == ' ' || response[start] == ':')) start++;
            remainingSeconds = atoi(&response[start]);
        }
    }

    CloseHandle(hPipe);
    return true;
}

InstallationResult FocusDnsWfpInstaller::InstallService(const std::wstring& binaryPath, const std::wstring& displayName) {
    SC_HANDLE schSCManager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CREATE_SERVICE);
    if (!schSCManager) {
        return { false, GetLastError(), L"Failed to open Service Control Manager with create rights." };
    }

    SC_HANDLE schService = CreateServiceW(
        schSCManager,
        m_serviceName.c_str(),
        displayName.c_str(),
        SERVICE_ALL_ACCESS,
        SERVICE_WIN32_OWN_PROCESS,
        SERVICE_AUTO_START,
        SERVICE_ERROR_NORMAL,
        binaryPath.c_str(),
        nullptr,
        nullptr,
        L"Tcpip\0\0", // Depend on TCPIP driver stack
        nullptr,
        nullptr
    );

    if (!schService) {
        DWORD err = GetLastError();
        CloseServiceHandle(schSCManager);
        return { false, err, L"CreateServiceW failed to register " + m_serviceName };
    }

    // Set service failure actions to auto-restart on crash
    SERVICE_FAILURE_ACTIONSW sfa = { 0 };
    SC_ACTION actions[3];
    actions[0].Type = SC_ACTION_RESTART;
    actions[0].Delay = 5000; // 5s
    actions[1].Type = SC_ACTION_RESTART;
    actions[1].Delay = 10000;
    actions[2].Type = SC_ACTION_RESTART;
    actions[2].Delay = 30000;

    sfa.dwResetPeriod = 86400; // 24h
    sfa.cActions = 3;
    sfa.lpsaActions = actions;
    ChangeServiceConfig2W(schService, SERVICE_CONFIG_FAILURE_ACTIONS, &sfa);

    CloseServiceHandle(schService);
    CloseServiceHandle(schSCManager);

    return { true, ERROR_SUCCESS, L"FocusDNS service successfully installed and configured for auto-recovery." };
}

InstallationResult FocusDnsWfpInstaller::UninstallService() {
    // 1. INVIOLABLE CONDITIONAL UNINSTALLATION LAW CHECK
    int remainingSeconds = 0;
    UninstallPosture posture = QueryUninstallationPosture(&remainingSeconds);

    if (posture == UninstallPosture::LockedActiveFocus || posture == UninstallPosture::LockedCountdownTimer) {
        return {
            false,
            ERROR_ACCESS_DENIED,
            L"ERROR_ACCESS_DENIED: Uninstallation is strictly locked during an active Focus Session (" +
            std::to_wstring(remainingSeconds) + L"s remaining)."
        };
    }

    // 2. Open SCM to stop and remove service
    SC_HANDLE schSCManager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ALL_ACCESS);
    if (!schSCManager) {
        return { false, GetLastError(), L"Failed to open SCM for service removal." };
    }

    SC_HANDLE schService = OpenServiceW(schSCManager, m_serviceName.c_str(), SERVICE_STOP | DELETE);
    if (!schService) {
        DWORD err = GetLastError();
        CloseServiceHandle(schSCManager);
        if (err == ERROR_SERVICE_DOES_NOT_EXIST) {
            return { true, ERROR_SUCCESS, L"Service does not exist; proceeding with WFP cleanup." };
        }
        return { false, err, L"Failed to open service for deletion." };
    }

    SERVICE_STATUS status;
    ControlService(schService, SERVICE_CONTROL_STOP, &status);
    Sleep(500);

    if (!DeleteService(schService)) {
        DWORD err = GetLastError();
        CloseServiceHandle(schService);
        CloseServiceHandle(schSCManager);
        return { false, err, L"DeleteService failed." };
    }

    CloseServiceHandle(schService);
    CloseServiceHandle(schSCManager);

    // 3. Clean up WFP kernel filters and provider
    return RemoveWfpFiltersAndProvider();
}

InstallationResult FocusDnsWfpInstaller::RemoveWfpFiltersAndProvider() {
    DWORD dwResult = FwpmEngineOpen0(nullptr, RPC_C_AUTHN_WINNT, nullptr, nullptr, &m_engineHandle);
    if (dwResult != ERROR_SUCCESS) {
        return { false, dwResult, L"FwpmEngineOpen0 failed during teardown." };
    }

    dwResult = FwpmTransactionBegin0(m_engineHandle, 0);
    if (dwResult != ERROR_SUCCESS) {
        return { false, dwResult, L"FwpmTransactionBegin0 failed." };
    }

    // Deleting the Provider automatically cascades and removes associated sublayers & filters
    dwResult = FwpmProviderDeleteByKey0(m_engineHandle, &FOCUS_GUARD_PROVIDER_KEY);
    if (dwResult != ERROR_SUCCESS && dwResult != FWP_E_PROVIDER_NOT_FOUND) {
        FwpmTransactionAbort0(m_engineHandle);
        return { false, dwResult, L"FwpmProviderDeleteByKey0 failed." };
    }

    dwResult = FwpmTransactionCommit0(m_engineHandle);
    if (dwResult != ERROR_SUCCESS) {
        return { false, dwResult, L"FwpmTransactionCommit0 failed." };
    }

    return { true, ERROR_SUCCESS, L"WFP kernel filters and provider cleanly dismantled." };
}

} // namespace FocusGuard
