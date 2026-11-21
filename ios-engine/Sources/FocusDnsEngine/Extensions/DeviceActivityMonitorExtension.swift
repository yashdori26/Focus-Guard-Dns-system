import Foundation
import DeviceActivity
import ManagedSettings

/// Base service logic for iOS DeviceActivityMonitor extension.
/// Handles schedule boundaries when app process is closed or suspended.
@available(iOS 16.0, *)
open class DeviceActivityMonitorService: DeviceActivityMonitor, @unchecked Sendable {
    private let appGroupId = "group.com.focusdns.app"
    private let store = ManagedSettingsStore(named: .init("FocusDnsStore"))
    
    open override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        
        let defaults = UserDefaults(suiteName: appGroupId)
        let isStrict = defaults?.bool(forKey: "isStrict") ?? false
        
        // Ensure shields and anti-removal protection are reinforced
        store.application.denyAppRemoval = isStrict
    }
    
    open override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        
        let defaults = UserDefaults(suiteName: appGroupId)
        let endsAt = defaults?.int64(forKey: "endsAt") ?? 0
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        
        // If session target end reached, lift shields
        if nowMs >= endsAt && endsAt > 0 {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.application.denyAppRemoval = false
            
            defaults?.removeObject(forKey: "endsAt")
            defaults?.removeObject(forKey: "isStrict")
            defaults?.synchronize()
        }
    }
    
    open override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        // Invoked when micro-break or usage threshold is hit
    }
}
