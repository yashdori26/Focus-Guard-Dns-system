import Foundation
import ManagedSettings

/// Manages OS-level shield policies using Apple ManagedSettings framework.
@available(iOS 16.0, *)
public final class ManagedSettingsEngine: @unchecked Sendable {
    public static let shared = ManagedSettingsEngine()
    
    // Named store or default shared store
    private let store: ManagedSettingsStore
    
    public init(storeName: ManagedSettingsStore.Name = .init("FocusDnsStore")) {
        self.store = ManagedSettingsStore(named: storeName)
    }
    
    /// Applies application shields and anti-removal protection if strict mode is active.
    public func applyApplicationShields(
        applications: Set<ApplicationToken>?,
        categories: ShieldSettings.ActivityCategoryPolicy<Application>? = nil,
        webDomains: Set<WebDomainToken>? = nil,
        isStrict: Bool = false
    ) {
        if let apps = applications {
            store.shield.applications = apps
        }
        if let cats = categories {
            store.shield.applicationCategories = cats
        }
        if let domains = webDomains {
            store.shield.webDomains = domains
        }
        
        // Strict Mode: Deny app deletion while locked
        store.application.denyAppRemoval = isStrict
    }
    
    /// Toggles the OS-level anti-uninstall guard.
    public func setAntiRemovalGuard(_ enabled: Bool) {
        store.application.denyAppRemoval = enabled
    }
    
    /// Clears all active shields and unlocks app removal.
    public func clearAllShields() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.application.denyAppRemoval = false
    }
}
