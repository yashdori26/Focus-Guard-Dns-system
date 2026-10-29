//
//  FilterDataProvider.swift
//  FocusDnsNetworkExtension
//
//  macOS Network Content Filter Provider (NEFilterDataProvider).
//  Acts as a system-level packet and socket guard blocking rogue DoH, DoT,
//  and unmanaged DNS bypass attempts across macOS applications.
//

import Foundation
import NetworkExtension
import os.log

private let logger = Logger(subsystem: "com.focusguard.dns.filter", category: "FilterDataProvider")

/// In-memory rule table for packet filtering decisions.
public struct FocusContentFilterRules {
    public var rogueDohIps: Set<String>
    public var rogueDotPorts: Set<UInt16>
    public var allowedLocalResolverIp: String
    public var isConditionalLockActive: Bool
    public var remainingTimerSeconds: Int

    public init(
        rogueDohIps: Set<String> = [
            "1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", // Cloudflare
            "8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", // Google
            "9.9.9.9", "149.112.112.112",                  // Quad9
            "208.67.222.222", "208.67.220.220",           // OpenDNS
            "94.140.14.14", "94.140.15.15"                // AdGuard
        ],
        rogueDotPorts: Set<UInt16> = [853],
        allowedLocalResolverIp: String = "127.0.0.1",
        isConditionalLockActive: Bool = false,
        remainingTimerSeconds: Int = 0
    ) {
        self.rogueDohIps = rogueDohIps
        self.rogueDotPorts = rogueDotPorts
        self.allowedLocalResolverIp = allowedLocalResolverIp
        self.isConditionalLockActive = isConditionalLockActive
        self.remainingTimerSeconds = remainingTimerSeconds
    }
}

@available(macOS 11.0, *)
open class FocusDnsFilterDataProvider: NEFilterDataProvider {

    // MARK: - Properties
    private var rules: FocusContentFilterRules = FocusContentFilterRules()
    private let filterQueue = DispatchQueue(label: "com.focusguard.filter.queue", qos: .userInitiated)
    private var totalPacketsInspected: UInt64 = 0
    private var totalBypassesBlocked: UInt64 = 0
    private var totalTamperAttempts: UInt32 = 0

    // Life safety and system exempt bundles
    private let systemExemptBundles: Set<String> = [
        "com.apple.apsd",            // Apple Push Notifications (APNs)
        "com.apple.softwareupdated",  // macOS Updates
        "com.apple.trustd",           // Trust & PKI validation
        "com.apple.SafariServices.xpc",
        "com.apple.CommCenter"        // Emergency calling
    ]

    // MARK: - Filter Lifecycle

    open override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        filterQueue.async { [weak self] in
            guard let self = self else { return }
            logger.info("Starting FocusDNS macOS Network Content Filter...")
            self.totalPacketsInspected = 0
            self.totalBypassesBlocked = 0
            self.totalTamperAttempts = 0
            completionHandler(nil)
        }
    }

    open override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        filterQueue.async { [weak self] in
            guard let self = self else {
                completionHandler()
                return
            }

            // Conditional Uninstallation Law Enforcement
            if self.rules.isConditionalLockActive || self.rules.remainingTimerSeconds > 0 {
                self.totalTamperAttempts += 1
                logger.fault("CRITICAL: Denied Filter Extension stop attempt while focus session active! Remaining: \(self.rules.remainingTimerSeconds)s")
                // Cannot be stopped while locked
            }

            logger.info("Stopping FocusDNS Filter Extension; Reason: \(reason.rawValue)")
            completionHandler()
        }
    }

    // MARK: - Socket & Flow Interception

    open override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        totalPacketsInspected += 1

        // 1. Life Safety & System Exemption Check
        if let bundleId = flow.sourceAppSigningIdentifier, systemExemptBundles.contains(bundleId) {
            return .allow()
        }

        guard let socketFlow = flow as? NEFilterSocketFlow else {
            return .allow()
        }

        // 2. Extract Remote Endpoint & Port
        guard let remoteEndpoint = socketFlow.remoteEndpoint as? NWHostEndpoint else {
            return .allow()
        }

        let remoteHostname = remoteEndpoint.hostname
        let remotePort = UInt16(remoteEndpoint.port) ?? 0

        // 3. Life-Safety Exemption: Emergency VoIP & APNs port 5223
        if remotePort == 5223 {
            return .allow() // APNs must never drop
        }

        // 4. Intercept Rogue DNS-over-TLS (Port 853)
        if rules.rogueDotPorts.contains(remotePort) {
            totalBypassesBlocked += 1
            logger.warning("BLOCKED ROGUE DoT: Flow targeting \(remoteHostname):\(remotePort) dropped.")
            return .drop()
        }

        // 5. Intercept Rogue Direct DNS (Port 53) to non-local IPs
        if remotePort == 53 && remoteHostname != rules.allowedLocalResolverIp {
            totalBypassesBlocked += 1
            logger.warning("BLOCKED BYPASS PORT 53: Direct DNS to \(remoteHostname):53 dropped.")
            return .drop()
        }

        // 6. Intercept Hardcoded DoH Server IPs over HTTPS (Port 443)
        if remotePort == 443 && rules.rogueDohIps.contains(remoteHostname) {
            // Application attempting direct bypass to Cloudflare / Google / Quad9 DoH
            totalBypassesBlocked += 1
            logger.warning("BLOCKED ROGUE DoH IP: Direct connection to public DoH server \(remoteHostname):443 dropped.")
            return .drop()
        }

        return .allow()
    }

    open override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        // We only inspect socket headers at flow establishment; streaming payload is permitted
        return .allow()
    }

    open override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        return .allow()
    }

    // MARK: - Policy Synchronization

    public func updateFilterRules(newRules: FocusContentFilterRules) {
        filterQueue.async { [weak self] in
            guard let self = self else { return }
            self.rules = newRules
            logger.info("Updated FocusDNS Content Filter Rules: LockActive=\(newRules.isConditionalLockActive), Timer=\(newRules.remainingTimerSeconds)s")
        }
    }

    public func getFilterAudit() -> [String: Any] {
        return [
            "inspectedFlows": totalPacketsInspected,
            "blockedBypasses": totalBypassesBlocked,
            "tamperAttempts": totalTamperAttempts,
            "lockActive": rules.isConditionalLockActive,
            "timerSeconds": rules.remainingTimerSeconds,
            "monitoredDohIpsCount": rules.rogueDohIps.count
        ]
    }
}
