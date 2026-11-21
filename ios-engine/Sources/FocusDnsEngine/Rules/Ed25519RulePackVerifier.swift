import Foundation
import CryptoKit

/// Validates Ed25519 cryptographic signatures on dynamic rule packs and applies deltas with Anti-Rollback enforcement.
public final class Ed25519RulePackVerifier: @unchecked Sendable {
    public static let shared = Ed25519RulePackVerifier()
    
    // Cloud API FocusDNS Ed25519 Public Key
    public static let defaultPublicKeyHex = "3a2d7f4b8c9e0123456789abcdef0123456789abcdef0123456789abcdef0123"
    
    private let lock = NSLock()
    public private(set) var activeVersion: Int = 0
    
    public struct RulePackDelta: Codable, Sendable {
        public let packId: String
        public let version: Int
        public let timestampEpochMs: Int64
        public let killSwitch: Bool
        public let exactBlockedDomains: [String]
        public let wildcardSuffixes: [String]
        
        enum CodingKeys: String, CodingKey {
            case packId = "pack_id"
            case version
            case timestampEpochMs = "timestamp_epoch_ms"
            case killSwitch = "kill_switch"
            case exactBlockedDomains = "exact_blocked_domains"
            case wildcardSuffixes = "wildcard_suffixes"
        }
    }
    
    public func verifyAndParse(
        payloadData: Data,
        signatureHex: String,
        publicKeyHex: String = defaultPublicKeyHex,
        enforceAntiRollback: Bool = true
    ) -> Result<RulePackDelta, Error> {
        // Convert hex signature to Data
        guard let signatureData = dataFromHexString(signatureHex), signatureData.count == 64 else {
            let err = NSError(
                domain: "Ed25519Verifier",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "ERR_INVALID_SIGNATURE_FORMAT"]
            )
            return .failure(err)
        }
        
        // Convert hex public key to Data
        guard let pubKeyData = dataFromHexString(publicKeyHex), pubKeyData.count == 32 else {
            let err = NSError(
                domain: "Ed25519Verifier",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "ERR_INVALID_PUBLIC_KEY"]
            )
            return .failure(err)
        }
        
        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
            let signature = try Curve25519.Signing.Signature(rawRepresentation: signatureData)
            
            // Cryptographic signature verification
            guard publicKey.isValidSignature(signature, for: payloadData) else {
                let err = NSError(
                    domain: "Ed25519Verifier",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "ERR_SIGNATURE_MISMATCH"]
                )
                return .failure(err)
            }
            
            // Parse verified payload
            let decoder = JSONDecoder()
            let delta = try decoder.decode(RulePackDelta.self, from: payloadData)
            
            lock.lock()
            defer { lock.unlock() }
            
            // Anti-Rollback Sequence Verification
            if enforceAntiRollback && delta.version < activeVersion {
                let err = NSError(
                    domain: "Ed25519Verifier",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "ERR_RULE_PACK_ROLLBACK_ATTEMPT_DETECTED: incoming version \(delta.version) < active \(activeVersion)"]
                )
                return .failure(err)
            }
            
            activeVersion = delta.version
            return .success(delta)
        } catch {
            return .failure(error)
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
