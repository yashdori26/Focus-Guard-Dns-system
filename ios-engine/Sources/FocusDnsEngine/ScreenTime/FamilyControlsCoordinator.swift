import Foundation
import FamilyControls

/// Coordinates Apple FamilyControls authorization and entitlement capabilities.
@available(iOS 16.0, *)
public final class FamilyControlsCoordinator: @unchecked Sendable {
    public static let shared = FamilyControlsCoordinator()
    
    public enum AuthStatus: String, Sendable {
        case approved = "APPROVED"
        case denied = "DENIED"
        case notDetermined = "NOT_DETERMINED"
    }
    
    public var status: AuthStatus {
        switch AuthorizationCenter.shared.status {
        case .approved:
            return .approved
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
    
    public var isAuthorized: Bool {
        return status == .approved
    }
    
    /// Requests FamilyControls authorization for individual user protection.
    public func requestAuthorization() async throws -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            return AuthorizationCenter.shared.status == .approved
        } catch {
            throw error
        }
    }
    
    /// Revocation check callback.
    public func verifyEntitlement() -> Bool {
        return AuthorizationCenter.shared.status == .approved
    }
}
