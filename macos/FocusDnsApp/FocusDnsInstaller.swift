//
//  FocusDnsInstaller.swift
//  FocusDnsApp
//
//  macOS Modern System Extension Activation & Deactivation Manager.
//  Uses SystemExtensions.framework (OSSystemExtensionRequest) to safely
//  install, upgrade, and cleanly uninstall FocusDNS Network Extensions.
//
//  Inviolable Conditional Uninstallation Law:
//  - Deactivation requests verify with the local Policy Coordinator.
//  - If protection is active or timer > 0, throws .uninstallationDisallowed
//    and refuses to submit OSSystemExtensionRequest.deactivationRequest.
//

import Foundation
import SystemExtensions
import os.log

private let logger = Logger(subsystem: "com.focusguard.macos.installer", category: "SystemExtensionInstaller")

public enum FocusExtensionInstallError: Error {
    case uninstallationDisallowed(remainingSeconds: Int)
    case authorizationFailed
    case userApprovalRequired
    case extensionNotFound
    case systemPolicyBlocked
    case underlyingError(Error)
}

public protocol FocusExtensionInstallDelegate: AnyObject {
    func extensionNeedsUserApproval()
    func extensionDidActivateSuccessfully()
    func extensionDidDeactivateSuccessfully()
    func extensionDidFail(error: FocusExtensionInstallError)
}

@available(macOS 10.15, *)
public class FocusDnsSystemExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {

    public static let shared = FocusDnsSystemExtensionInstaller()
    public static let extensionBundleId = "com.focusguard.dns.extension"

    public weak var delegate: FocusExtensionInstallDelegate?
    private let queue = DispatchQueue(label: "com.focusguard.sysext.queue", qos: .userInitiated)

    // Current State
    public private(set) var isActivated: Bool = false
    public private(set) var isAwaitingApproval: Bool = false
    private var isFocusLocked: Bool = false
    private var remainingTimerSeconds: Int = 0

    private override init() {
        super.init()
    }

    // MARK: - Policy Lock Synchronization

    public func updatePolicyLock(isLocked: Bool, remainingSeconds: Int) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isFocusLocked = isLocked
            self.remainingTimerSeconds = max(0, remainingSeconds)
            logger.info("Updated installer lock state: Locked=\(isLocked), Timer=\(remainingSeconds)s")
        }
    }

    public func canUninstall() -> Bool {
        var allowed = false
        queue.sync {
            allowed = (!self.isFocusLocked) && (self.remainingTimerSeconds == 0)
        }
        return allowed
    }

    // MARK: - Activation

    public func activateExtension() {
        queue.async { [weak self] in
            guard let self = self else { return }
            logger.info("Submitting OSSystemExtensionRequest activation for \(Self.extensionBundleId)...")

            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: Self.extensionBundleId,
                queue: self.queue
            )
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    // MARK: - Deactivation (Conditional)

    public func deactivateExtension() throws {
        var err: FocusExtensionInstallError?
        queue.sync {
            if self.isFocusLocked || self.remainingTimerSeconds > 0 {
                logger.fault("ACCESS DENIED: Denied System Extension deactivation while focus is locked (\(self.remainingTimerSeconds)s remaining).")
                err = FocusExtensionInstallError.uninstallationDisallowed(remainingSeconds: self.remainingTimerSeconds)
                return
            }

            logger.info("Normal Mode Verified. Submitting OSSystemExtensionRequest deactivation...")
            let request = OSSystemExtensionRequest.deactivationRequest(
                forExtensionWithIdentifier: Self.extensionBundleId,
                queue: self.queue
            )
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }

        if let error = err {
            throw error
        }
    }

    // MARK: - OSSystemExtensionRequestDelegate

    public func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        logger.info("Replacing existing system extension version \(existing.bundleShortVersion) with \(ext.bundleShortVersion)")
        return .replace
    }

    public func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.warning("System Extension activation requires user approval in macOS Privacy & Security Settings.")
        isAwaitingApproval = true
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.extensionNeedsUserApproval()
        }
    }

    public func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        logger.info("System Extension request finished with result: \(result.rawValue)")
        isAwaitingApproval = false

        if result == .completed {
            isActivated = true
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.extensionDidActivateSuccessfully()
            }
        } else if result == .willCompleteAfterReboot {
            logger.notice("System Extension activation will complete after macOS system reboot.")
        }
    }

    public func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        logger.error("System Extension request failed: \(error.localizedDescription)")
        isAwaitingApproval = false
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.extensionDidFail(error: .underlyingError(error))
        }
    }
}
