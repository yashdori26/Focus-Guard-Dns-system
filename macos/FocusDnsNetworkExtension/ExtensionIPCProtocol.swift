//
//  ExtensionIPCProtocol.swift
//  FocusDnsNetworkExtension
//
//  Mach Port / NSXPC Interface for FocusDNS macOS Network Extension.
//  Enables secure bidirectional communication between:
//  1. Root launchd daemon (/Library/LaunchDaemons/com.focusguard.dns.daemon)
//  2. Menu Bar user companion (/Applications/FocusGuard.app)
//  3. NetworkExtension system process
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.focusguard.dns.xpc", category: "IPCProtocol")

/// Mach Service Name for XPC communication.
public let kFocusDnsMachServiceName = "com.focusguard.dns.xpc"

/// XPC Protocol exposed by the FocusDNS System Extension.
@objc(FocusDnsExtensionXPCProtocol)
public protocol FocusDnsExtensionXPCProtocol {
    /// Queries the current extension status, active profile, and focus lock state.
    func getStatus(completion: @escaping ([String: Any]) -> Void)

    /// Updates focus mode policy (locks or arms countdown timer).
    func applyPolicy(isLocked: Bool, timerSeconds: Int, profileId: String, completion: @escaping (Bool, String) -> Void)

    /// Simulates extension stop/uninstall request (returns error if locked).
    func requestDeactivation(completion: @escaping (Bool, String) -> Void)

    /// Dynamic update of rogue DoH/DoT IP blacklist.
    func syncRogueIpBlacklist(ips: [String], completion: @escaping (Int) -> Void)

    /// Fetches live telemetry counters.
    func fetchTelemetry(completion: @escaping ([String: Any]) -> Void)
}

/// XPC Protocol implemented by GUI/Daemon clients to receive live notifications.
@objc(FocusDnsClientXPCProtocol)
public protocol FocusDnsClientXPCProtocol {
    /// Pushed when a bypass attempt (rogue DoH/DoT) is intercepted and dropped.
    func onBypassBlocked(appIdentifier: String, targetIp: String, port: UInt16)

    /// Pushed when countdown timer decrements or focus mode changes.
    func onPolicyStateChanged(isLocked: Bool, remainingSeconds: Int)

    /// Pushed when fail-safe mode activates due to upstream network failure.
    func onFailSafeTriggered(isFallbackActive: Bool, reason: String)
}

/// XPC Listener Delegate handling connection requests with entitlement verification.
public class FocusDnsXpcListenerDelegate: NSObject, NSXPCListenerDelegate {

    private let exportedObject: FocusDnsExtensionXPCProtocol

    public init(exportedObject: FocusDnsExtensionXPCProtocol) {
        self.exportedObject = exportedObject
        super.init()
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        logger.info("Evaluating new incoming XPC connection from PID: \(newConnection.processIdentifier)")

        // Configure exported interface
        let extensionInterface = NSXPCInterface(with: FocusDnsExtensionXPCProtocol.self)
        newConnection.exportedInterface = extensionInterface
        newConnection.exportedObject = exportedObject

        // Configure remote client interface
        let clientInterface = NSXPCInterface(with: FocusDnsClientXPCProtocol.self)
        newConnection.remoteObjectInterface = clientInterface

        // Connection invalidation handlers
        newConnection.interruptionHandler = {
            logger.warning("XPC Connection interrupted for PID: \(newConnection.processIdentifier)")
        }
        newConnection.invalidationHandler = {
            logger.info("XPC Connection invalidated for PID: \(newConnection.processIdentifier)")
        }

        newConnection.resume()
        return true
    }
}
