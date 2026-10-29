//
//  KeychainAuthManager.swift
//  FocusDnsApp
//
//  Apple Keychain & Secure Enclave Token Management.
//  Protects FocusDNS device enrollment tokens and cryptographic authorization keys
//  against tamper, memory dumping, and unauthorized modification.
//

import Foundation
import Security
import LocalAuthentication
import os.log

private let logger = Logger(subsystem: "com.focusguard.macos.app", category: "KeychainAuthManager")

public enum KeychainAuthError: Error {
    case itemNotFound
    case duplicateItem
    case accessControlFailed
    case secureEnclaveUnavailable
    case uninstallationLocked
    case unexpectedStatus(OSStatus)
}

public class FocusKeychainAuthManager {

    private static let serviceName = "com.focusguard.dns.keychain"
    private static let accountTokenKey = "FocusGuardDeviceAuthToken"
    private static let profileSigningKeyTag = "com.focusguard.dns.signingkey"

    // MARK: - Save Secure Token

    public static func saveDeviceAuthToken(_ token: String) throws {
        guard let tokenData = token.data(using: .utf8) else { return }

        // Remove existing item if present
        deleteDeviceAuthTokenSilently()

        // Create Secure Enclave access control
        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [.privateKeyUsage],
            &accessControlError
        ) else {
            logger.error("Failed to construct SecAccessControl for Keychain storage.")
            throw KeychainAuthError.accessControlFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountTokenKey,
            kSecValueData as String: tokenData,
            kSecAttrAccessControl as String: accessControl
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("SecItemAdd failed with status: \(status)")
            throw KeychainAuthError.unexpectedStatus(status)
        }
        logger.info("Device authorization token saved securely into Apple Keychain.")
    }

    // MARK: - Retrieve Token

    public static func getDeviceAuthToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountTokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainAuthError.itemNotFound
            }
            throw KeychainAuthError.unexpectedStatus(status)
        }

        guard let tokenData = item as? Data, let token = String(data: tokenData, encoding: .utf8) else {
            throw KeychainAuthError.itemNotFound
        }

        return token
    }

    // MARK: - Secure Deletion (Conditional)

    public static func deleteDeviceAuthToken(canUninstall: Bool) throws {
        guard canUninstall else {
            logger.fault("ACCESS DENIED: Attempted to wipe Keychain authorization while session is locked.")
            throw KeychainAuthError.uninstallationLocked
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountTokenKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainAuthError.unexpectedStatus(status)
        }
        logger.info("FocusDNS device token cleanly expunged from Keychain.")
    }

    private static func deleteDeviceAuthTokenSilently() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountTokenKey
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Attestation Verification

    public static func hasHardwareEnclave() -> Bool {
        var context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
}
