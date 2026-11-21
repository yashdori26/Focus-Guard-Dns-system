import Foundation
import DeviceActivity

/// Schedules background activity monitoring using Apple DeviceActivity framework.
/// Respects the 15-minute iOS minimum schedule constraint.
@available(iOS 16.0, *)
public final class DeviceActivityScheduler: @unchecked Sendable {
    public static let shared = DeviceActivityScheduler()
    private static let activityName = DeviceActivityName("com.focusdns.activity.session")
    
    private let center = DeviceActivityCenter()
    
    public init() {}
    
    /// Schedules a session monitoring interval.
    /// - Parameters:
    ///   - startEpochMs: Wall clock start timestamp in milliseconds.
    ///   - endEpochMs: Wall clock end timestamp in milliseconds.
    /// - Returns: True if registered with DeviceActivityCenter (>= 15 minutes), false if sub-15m interval.
    @discardableResult
    public func scheduleInterval(
        startEpochMs: Int64,
        endEpochMs: Int64
    ) -> (registeredNativeSchedule: Bool, error: String?) {
        let now = Date()
        let startDate = Date(timeIntervalSince1970: Double(startEpochMs) / 1000.0)
        let endDate = Date(timeIntervalSince1970: Double(endEpochMs) / 1000.0)
        
        // Effective start for scheduling
        let effectiveStart = max(now, startDate)
        let durationSeconds = endDate.timeIntervalSince(effectiveStart)
        
        // iOS enforces a 15-minute (900s) minimum schedule interval for DeviceActivity
        if durationSeconds >= 900 {
            let startComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: effectiveStart)
            let endComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: endDate)
            
            let schedule = DeviceActivitySchedule(
                intervalStart: startComponents,
                intervalEnd: endComponents,
                repeats: false
            )
            
            do {
                try center.startMonitoring(Self.activityName, during: schedule)
                return (true, nil)
            } catch {
                return (false, "DeviceActivityCenter error: \(error.localizedDescription)")
            }
        } else {
            // For sub-15 minute intervals (e.g. 5-minute Pomodoro breaks),
            // background enforcement is synchronized via App Group UserDefaults & foreground check.
            return (false, "Sub-15 minute interval (\(Int(durationSeconds))s): handled via App Group synchronization")
        }
    }
    
    /// Stops any ongoing DeviceActivity monitoring.
    public func stopMonitoring() {
        center.stopMonitoring([Self.activityName])
    }
}
