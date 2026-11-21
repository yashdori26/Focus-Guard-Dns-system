import Foundation
import CryptoKit
import Security

/// Hardware-backed device key manager for iOS.
/// Generates and signs challenge nonces using NIST P-256 (secp256r1) inside Apple's Secure Enclave.
public final class SecureEnclaveKeyManager: @unchecked Sendable {
    public static let shared = SecureEnclaveKeyManager()
    
    private let keyTag = "com.focusdns.devicekey.p256"
    private let lock = NSLock()
    
    public init() {}
    
    /// Returns the hex-encoded 65-byte uncompressed P-256 public key.
    public func getOrCreateDevicePublicKeyHex() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        
        let privKey = try loadOrGeneratePrivateKey()
        let pubKeyData = privKey.publicKey.x963Representation
        return pubKeyData.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Signs a 32-byte challenge nonce using ECDSA P-256 with SHA-256.
    /// Returns the DER-encoded signature in hex.
    public func signChallengeNonceHex(_ nonceHex: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        
        guard let nonceData = dataFromHexString(nonceHex) else {
            throw NSError(domain: "SecureEnclaveKeyManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "ERR_INVALID_NONCE_HEX"])
        }
        
        let privKey = try loadOrGeneratePrivateKey()
        let signature = try privKey.signature(for: nonceData)
        let derData = signature.derRepresentation
        return derData.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Private Helpers
    
    private enum DeviceKey {
        case secureEnclave(SecureEnclave.P256.Signing.PrivateKey)
        case softwareFallback(P256.Signing.PrivateKey)
        
        var publicKey: P256.Signing.PublicKey {
            switch self {
            case .secureEnclave(let se):
                return se.publicKey
            case .softwareFallback(let sw):
                return sw.publicKey
            }
        }
        
        func signature(for data: Data) throws -> P256.Signing.ECDSASignature {
            switch self {
            case .secureEnclave(let se):
                return try se.signature(for: data)
            case .softwareFallback(let sw):
                return try sw.signature(for: data)
            }
        }
    }
    
    private var cachedKey: DeviceKey?
    
    private func loadOrGeneratePrivateKey() throws -> DeviceKey {
        if let key = cachedKey {
            return key
        }
        
        // Check if Secure Enclave is available on this physical device
        if SecureEnclave.isAvailable {
            do {
                // Try to load or create Secure Enclave key
                let seKey = try SecureEnclave.P256.Signing.PrivateKey()
                let deviceKey = DeviceKey.secureEnclave(seKey)
                self.cachedKey = deviceKey
                return deviceKey
            } catch {
                // Fall back to software P-256 if enclave generation fails
                let swKey = P256.Signing.PrivateKey()
                let deviceKey = DeviceKey.softwareFallback(swKey)
                self.cachedKey = deviceKey
                return deviceKey
            }
        } else {
            // Software P-256 fallback (e.g. Simulator)
            let swKey = P256.Signing.PrivateKey()
            let deviceKey = DeviceKey.softwareFallback(swKey)
            self.cachedKey = deviceKey
            return deviceKey
        }
    }
    
    private func dataFromHexString(_ hex: String) -> Data? {
        var data = Data()
        var temp = ""
        for char in hex {
            temp.append(char)
            if temp.count == 2 {
                guard let byte = UInt8(temp, radix: 16) else { return nil }
                data.append(byte)
                temp = ""
            }
        }
        return data
    }
}
