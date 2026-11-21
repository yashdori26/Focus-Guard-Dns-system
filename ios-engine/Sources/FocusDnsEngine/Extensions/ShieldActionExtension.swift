import Foundation
import ManagedSettings

/// Base service logic for iOS ShieldAction extension.
/// Enforces Option B (Absolute Ironclad Lockout): Zero bypass or deferral during active strict sessions.
@available(iOS 16.0, *)
open class ShieldActionService: ShieldActionDelegate, @unchecked Sendable {
    private let appGroupId = "group.com.focusdns.app"
    
    public init() {}
    
    open func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let defaults = UserDefaults(suiteName: appGroupId)
        let isStrict = defaults?.bool(forKey: "isStrict") ?? false
        let endsAt = defaults?.int64(forKey: "endsAt") ?? 0
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        
        let sessionActive = (nowMs < endsAt)
        
        if sessionActive && isStrict {
            // Option B Ironclad Lockout: Strictly close or deny any deferral/bypass attempt
            completionHandler(.close)
        } else if sessionActive {
            // Non-strict session: dismiss shield UI or prompt
            completionHandler(.close)
        } else {
            // Session expired: allow action or unlock
            completionHandler(.defer)
        }
    }
    
    open func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let defaults = UserDefaults(suiteName: appGroupId)
        let isStrict = defaults?.bool(forKey: "isStrict") ?? false
        let endsAt = defaults?.int64(forKey: "endsAt") ?? 0
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        
        let sessionActive = (nowMs < endsAt)
        
        if sessionActive && isStrict {
            completionHandler(.close)
        } else {
            completionHandler(.close)
        }
    }
    
    open func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let defaults = UserDefaults(suiteName: appGroupId)
        let isStrict = defaults?.bool(forKey: "isStrict") ?? false
        
        if isStrict {
            completionHandler(.close)
        } else {
            completionHandler(.close)
        }
    }
}
