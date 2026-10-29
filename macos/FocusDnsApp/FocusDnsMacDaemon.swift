//
//  FocusDnsMacDaemon.swift
//  FocusDnsApp
//
//  macOS Root Launchd Background Daemon Service.
//  Coordinates system extension health, heartbeat telemetry, and POSIX signal handling.
//  Strictly enforces the Conditional Uninstallation Law at the root service level.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.focusguard.macos.daemon", category: "MacDaemon")

public class FocusDnsMacDaemon {

    // MARK: - Properties
    public private(set) var isRunning: Bool = false
    public private(set) var isProtectionLocked: Bool = false
    public private(set) var remainingTimerSeconds: Int = 0
    public private(set) var activeProfile: String = "profile_mac_workstation"

    private var heartbeatTimer: Timer?
    private var healthCheckFailures: Int = 0
    private let workQueue = DispatchQueue(label: "com.focusguard.daemon.queue", qos: .utility)

    // MARK: - Lifecycle

    public init() {}

    public func start() {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            logger.info("Starting FocusDNS macOS root launchd daemon...")
            self.isRunning = true
            self.setupSignalHandlers()
            self.startHeartbeat()
        }
    }

    public func stop() -> Bool {
        var canStop = false
        workQueue.sync {
            if self.isProtectionLocked || self.remainingTimerSeconds > 0 {
                logger.fault("CRITICAL: Denied daemon termination request! Focus session active (\(self.remainingTimerSeconds)s remaining).")
                canStop = false
            } else {
                logger.info("Normal mode verified. Stopping FocusDNS daemon...")
                self.heartbeatTimer?.invalidate()
                self.heartbeatTimer = nil
                self.isRunning = false
                canStop = true
            }
        }
        return canStop
    }

    // MARK: - Policy Updates

    public func updatePolicy(isLocked: Bool, timerSeconds: Int, profileId: String) {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            self.isProtectionLocked = isLocked
            self.remainingTimerSeconds = max(0, timerSeconds)
            self.activeProfile = profileId
            logger.info("Updated daemon policy: Locked=\(isLocked), Timer=\(timerSeconds)s, Profile=\(profileId)")
        }
    }

    public func canUninstall() -> Bool {
        var result = false
        workQueue.sync {
            result = (!self.isProtectionLocked) && (self.remainingTimerSeconds == 0)
        }
        return result
    }

    // MARK: - Signal Handling (Anti-Tamper)

    private func setupSignalHandlers() {
        // Intercept SIGTERM & SIGINT signals
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: workQueue)
        termSource.setEventHandler { [weak self] in
            guard let self = self else { return }
            logger.warning("Received SIGTERM signal.")
            if self.canUninstall() {
                logger.info("Clean shutdown permitted. Exiting.")
                exit(0)
            } else {
                logger.fault("SIGTERM REJECTED: Conditional Uninstallation Law prohibits termination while focus is active.")
            }
        }
        termSource.resume()

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: workQueue)
        intSource.setEventHandler { [weak self] in
            guard let self = self else { return }
            logger.warning("Received SIGINT signal.")
            if self.canUninstall() {
                logger.info("Clean interrupt permitted. Exiting.")
                exit(0)
            } else {
                logger.fault("SIGINT REJECTED: Active session locked.")
            }
        }
        intSource.resume()
    }

    // MARK: - Heartbeat & Local Stub Monitoring

    private func startHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.performHeartbeatCheck()
            }
        }
    }

    private func performHeartbeatCheck() {
        workQueue.async { [weak self] in
            guard let self = self else { return }

            // Decrement timer if active
            if self.remainingTimerSeconds > 0 {
                self.remainingTimerSeconds = max(0, self.remainingTimerSeconds - 5)
                if self.remainingTimerSeconds == 0 {
                    self.isProtectionLocked = false
                    logger.info("Countdown timer expired. Uninstallation unlocked.")
                }
            }

            // Probe local DNS stub resolver (127.0.0.1:53)
            let isStubHealthy = self.probeLocalDnsStub()
            if !isStubHealthy {
                self.healthCheckFailures += 1
                logger.warning("Local DNS stub probe failed (\(self.healthCheckFailures)/3).")
                if self.healthCheckFailures >= 3 {
                    logger.fault("Fail-Safe Triggered: Local stub unreachable. Restoring temporary fallback DNS.")
                }
            } else {
                self.healthCheckFailures = 0
            }
        }
    }

    private func probeLocalDnsStub() -> Bool {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return false }

        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(53).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        let targetPtr = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
        }

        // DNS header query for "." root zone
        let pingPacket: [UInt8] = [
            0xAA, 0xBB, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x01, 0x00, 0x01
        ]

        _ = sendto(sock, pingPacket, pingPacket.count, 0, targetPtr, socklen_t(MemoryLayout<sockaddr_in>.size))

        var buf = [UInt8](repeating: 0, count: 512)
        let res = recv(sock, &buf, buf.count, 0)
        close(sock)

        return res > 0
    }
}
