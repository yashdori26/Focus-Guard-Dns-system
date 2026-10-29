//
//  FocusDnsBypassDetector.h
//  FocusGuard Windows ETW Network Bypass Detector
//
//  Monitors real-time Microsoft-Windows-Kernel-Network ETW trace events
//  for unauthorized socket connections targeting third-party DoH / DoT resolvers.
//

#ifndef FOCUS_DNS_BYPASS_DETECTOR_H
#define FOCUS_DNS_BYPASS_DETECTOR_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <evntrace.h>
#include <evntcons.h>
#include <string>
#include <vector>
#include <unordered_set>
#include <mutex>

namespace FocusGuard {

struct BypassEventRecord {
    DWORD processId;
    std::wstring processImageName;
    std::string destinationIp;
    UINT16 destinationPort;
    std::string protocol;
    FILETIME timestamp;
    bool blocked;
};

class FocusDnsBypassDetector {
public:
    FocusDnsBypassDetector();
    ~FocusDnsBypassDetector();

    bool StartMonitoring();
    void StopMonitoring();

    void AddMonitoredApp(const std::wstring& exeName);
    void AddBlockedEndpoint(const std::string& ipStr, UINT16 port);

    std::vector<BypassEventRecord> GetRecentBypasses(size_t maxCount = 50);
    size_t GetTotalBypassesDetected() const;

    // ETW callback entrypoint
    void HandleNetworkEvent(DWORD pid, const std::string& dstIp, UINT16 dstPort, const std::string& proto);

private:
    bool m_isMonitoring;
    TRACEHANDLE m_sessionHandle;
    TRACEHANDLE m_traceHandle;
    std::wstring m_sessionName;

    mutable std::mutex m_mutex;
    std::unordered_set<std::wstring> m_monitoredApps;
    std::unordered_set<std::string> m_blockedIps;
    std::vector<BypassEventRecord> m_eventLog;
    size_t m_totalBypassesDetected;

    std::wstring ResolveProcessName(DWORD pid);
};

} // namespace FocusGuard

#endif // FOCUS_DNS_BYPASS_DETECTOR_H
