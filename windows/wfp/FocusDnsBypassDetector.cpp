//
//  FocusDnsBypassDetector.cpp
//  FocusGuard Windows ETW Network Bypass Detector
//

#include "FocusDnsBypassDetector.h"
#include <psapi.h>
#include <algorithm>

#pragma comment(lib, "Advapi32.lib")

namespace FocusGuard {

FocusDnsBypassDetector::FocusDnsBypassDetector()
    : m_isMonitoring(false),
      m_sessionHandle(0),
      m_traceHandle(0),
      m_sessionName(L"FocusDnsEtwSession"),
      m_totalBypassesDetected(0) {
    // Populate default target bypass executables
    m_monitoredApps.insert(L"chrome.exe");
    m_monitoredApps.insert(L"msedge.exe");
    m_monitoredApps.insert(L"firefox.exe");
    m_monitoredApps.insert(L"Discord.exe");
    m_monitoredApps.insert(L"steam.exe");

    // Populate default rogue DoH / DoT endpoints
    m_blockedIps.insert("1.1.1.1");
    m_blockedIps.insert("1.0.0.1");
    m_blockedIps.insert("8.8.8.8");
    m_blockedIps.insert("8.8.4.4");
    m_blockedIps.insert("9.9.9.9");
}

FocusDnsBypassDetector::~FocusDnsBypassDetector() {
    StopMonitoring();
}

void FocusDnsBypassDetector::AddMonitoredApp(const std::wstring& exeName) {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::wstring lower = exeName;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
    m_monitoredApps.insert(lower);
}

void FocusDnsBypassDetector::AddBlockedEndpoint(const std::string& ipStr, UINT16 port) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_blockedIps.insert(ipStr);
}

bool FocusDnsBypassDetector::StartMonitoring() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isMonitoring) return true;

    m_isMonitoring = true;
    return true;
}

void FocusDnsBypassDetector::StopMonitoring() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_isMonitoring) return;

    if (m_sessionHandle) {
        ControlTraceW(m_sessionHandle, m_sessionName.c_str(), nullptr, EVENT_TRACE_CONTROL_STOP);
        m_sessionHandle = 0;
    }
    m_isMonitoring = false;
}

std::wstring FocusDnsBypassDetector::ResolveProcessName(DWORD pid) {
    if (pid == 0 || pid == 4) return L"System";

    HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!hProc) return L"Unknown";

    wchar_t exePath[MAX_PATH] = { 0 };
    DWORD size = MAX_PATH;
    if (QueryFullProcessImageNameW(hProc, 0, exePath, &size)) {
        CloseHandle(hProc);
        std::wstring fullPath(exePath);
        size_t idx = fullPath.find_last_of(L"\\/");
        if (idx != std::wstring::npos) {
            return fullPath.substr(idx + 1);
        }
        return fullPath;
    }

    CloseHandle(hProc);
    return L"Unknown";
}

void FocusDnsBypassDetector::HandleNetworkEvent(DWORD pid, const std::string& dstIp, UINT16 dstPort, const std::string& proto) {
    std::wstring procName = ResolveProcessName(pid);
    std::wstring lowerProc = procName;
    std::transform(lowerProc.begin(), lowerProc.end(), lowerProc.begin(), ::tolower);

    // Life-safety exemption: System and svchost (Windows Update) are exempt
    if (lowerProc == L"svchost.exe" || lowerProc == L"system") {
        return;
    }

    bool isBypass = false;

    // Check if port is DoT (853) or if IP is a known rogue DoH server (port 443)
    if (dstPort == 853) {
        isBypass = true;
    } else if (dstPort == 443) {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_blockedIps.find(dstIp) != m_blockedIps.end()) {
            isBypass = true;
        }
    }

    if (isBypass) {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_totalBypassesDetected++;

        FILETIME ft;
        GetSystemTimeAsFileTime(&ft);

        BypassEventRecord rec;
        rec.processId = pid;
        rec.processImageName = procName;
        rec.destinationIp = dstIp;
        rec.destinationPort = dstPort;
        rec.protocol = proto;
        rec.timestamp = ft;
        rec.blocked = true;

        m_eventLog.push_back(rec);
        if (m_eventLog.size() > 100) {
            m_eventLog.erase(m_eventLog.begin());
        }
    }
}

std::vector<BypassEventRecord> FocusDnsBypassDetector::GetRecentBypasses(size_t maxCount) {
    std::lock_guard<std::mutex> lock(m_mutex);
    size_t count = (std::min)(maxCount, m_eventLog.size());
    return std::vector<BypassEventRecord>(m_eventLog.end() - count, m_eventLog.end());
}

size_t FocusDnsBypassDetector::GetTotalBypassesDetected() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_totalBypassesDetected;
}

} // namespace FocusGuard
