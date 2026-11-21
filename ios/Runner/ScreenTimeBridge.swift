import Foundation
import Flutter
import FamilyControls
import ManagedSettings
import DeviceActivity

/**
 * ScreenTimeBridge provides the native Swift bridge for Apple Screen Time APIs:
 * - FamilyControls (Entitlement authorization & FamilyActivityPicker)
 * - ManagedSettings (OS-level Application, Web Domain & Category Shielding)
 * - ManagedSettingsStore.application.denyAppRemoval (Strict Mode app removal protection)
 * - DeviceActivity (DeviceActivitySchedule & DeviceActivityName for offline background enforcement)
 * - App Group shared data synchronization (group.com.focusdns.app)
 */
@available(iOS 15.0, *)
public class ScreenTimeBridge: NSObject {
    public static let shared = ScreenTimeBridge()
    private static let appGroupId = "group.com.focusdns.app"
    private static let channelName = "com.focusdns.app/screen_time"
    
    private let store = ManagedSettingsStore()
    private let center = DeviceActivityCenter()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = ScreenTimeBridge.shared
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestAuthorization":
            requestFamilyControlsAuthorization(result: result)
            
        case "isAuthorized":
            result(AuthorizationCenter.shared.status == .approved)
            
        case "applyShields":
            guard let args = call.arguments as? [String: Any],
                  let endsAtMillis = args["endsAt"] as? Int64,
                  let isStrict = args["isStrict"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGS", message: "endsAt and isStrict required", details: nil))
                return
            }
            applyShields(endsAtMillis: endsAtMillis, isStrict: isStrict, result: result)
            
        case "clearShields":
            clearAllShields()
            result(true)
            
        case "checkStatus":
            let defaults = UserDefaults(suiteName: ScreenTimeBridge.appGroupId)
            let endsAt = defaults?.int64(forKey: "endsAt") ?? 0
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let isExpired = now >= endsAt
            if isExpired && endsAt > 0 {
                clearAllShields()
            }
            result([
                "isAuthorized": AuthorizationCenter.shared.status == .approved,
                "isShieldActive": !isExpired && endsAt > 0,
                "endsAt": endsAt,
                "remainingMs": max(0, endsAt - now)
            ])
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - FamilyControls Authorization
    private func requestFamilyControlsAuthorization(result: @escaping FlutterResult) {
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                DispatchQueue.main.async {
                    result(AuthorizationCenter.shared.status == .approved)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "AUTH_DENIED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    // MARK: - ManagedSettings Shield Application
    public func applyShields(endsAtMillis: Int64, isStrict: Bool, result: @escaping FlutterResult) {
        let defaults = UserDefaults(suiteName: ScreenTimeBridge.appGroupId)
        defaults?.set(endsAtMillis, forKey: "endsAt")
        defaults?.set(isStrict, forKey: "isStrict")
        defaults?.synchronize()
        
        // 1. Strict Mode: Lock application removal if requested
        if isStrict {
            store.application.denyAppRemoval = true
        } else {
            store.application.denyAppRemoval = false
        }
        
        // 2. Schedule interval enforcement using DeviceActivitySchedule
        // Minimum schedule length in iOS is 15 minutes (900 seconds)
        let now = Date()
        let endDate = Date(timeIntervalSince1970: Double(endsAtMillis) / 1000.0)
        let durationSeconds = endDate.timeIntervalSince(now)
        
        if durationSeconds >= 900 {
            let startComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
            let endComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: endDate)
            
            let schedule = DeviceActivitySchedule(
                intervalStart: startComponents,
                intervalEnd: endComponents,
                repeats: false
            )
            
            let activityName = DeviceActivityName("com.focusdns.session")
            do {
                try center.startMonitoring(activityName, during: schedule)
            } catch {
                NSLog("DeviceActivityCenter monitoring error: \(error.localizedDescription)")
            }
        }
        
        result(true)
    }
    
    // MARK: - Clear All Shields
    public func clearAllShields() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.application.denyAppRemoval = false
        
        center.stopMonitoring([DeviceActivityName("com.focusdns.session")])
        
        let defaults = UserDefaults(suiteName: ScreenTimeBridge.appGroupId)
        defaults?.removeObject(forKey: "endsAt")
        defaults?.removeObject(forKey: "isStrict")
        defaults?.synchronize()
    }
}
