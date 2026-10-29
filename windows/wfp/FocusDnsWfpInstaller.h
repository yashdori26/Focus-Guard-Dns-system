//
//  FocusDnsWfpInstaller.h
//  FocusGuard Windows Filtering Platform Service Installer & Anti-Tamper Engine
//
//  Coordinates Win32 Service Control Manager (SCM) lifecycle and WFP transaction cleanup.
//  Strictly enforces the Conditional Uninstallation Law:
//  - If protection mode is active or timer > 0: returns ERROR_ACCESS_DENIED (5) and halts.
//  - If idle: cleanly removes service, unregisters provider GUID, and commits WFP transaction.
//

#ifndef FOCUS_DNS_WFP_INSTALLER_H
#define FOCUS_DNS_WFP_INSTALLER_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fwpmu.h>
#include <string>
#include <vector>

namespace FocusGuard {

enum class UninstallPosture {
    Allowed = 0,
    LockedActiveFocus = 1,
    LockedCountdownTimer = 2,
    IpcCommunicationFailed = 3
};

struct InstallationResult {
    bool success;
    DWORD win32ErrorCode;
    std::wstring message;
};

class FocusDnsWfpInstaller {
public:
    FocusDnsWfpInstaller();
    ~FocusDnsWfpInstaller();

    // SCM Service Operations
    InstallationResult InstallService(const std::wstring& binaryPath, const std::wstring& displayName);
    InstallationResult UninstallService();

    // WFP Engine Driver Teardown
    InstallationResult RemoveWfpFiltersAndProvider();

    // Conditional Uninstallation Law Check
    UninstallPosture QueryUninstallationPosture(int* outRemainingSeconds = nullptr);

    // Named pipe IPC client
    bool CheckIpcLockState(bool& isLocked, int& remainingSeconds);

private:
    std::wstring m_serviceName;
    HANDLE m_engineHandle;
};

} // namespace FocusGuard

#endif // FOCUS_DNS_WFP_INSTALLER_H
