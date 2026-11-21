import Foundation

/// Thread-safe persistence coordinating main application and background extension processes
/// via Apple App Groups (`group.com.focusdns.app`).
public final class AppGroupSessionStore: @unchecked Sendable {
    public static let shared = AppGroupSessionStore()
    public static let defaultAppGroupId = "group.com.focusdns.app"
    
    private let appGroupId: String
    private let defaults: UserDefaults?
    private let lock = NSLock()
    private let fileManager = FileManager.default
    
    public init(appGroupId: String = defaultAppGroupId) {
        self.appGroupId = appGroupId
        self.defaults = UserDefaults(suiteName: appGroupId)
    }
    
    private var containerURL: URL? {
        return fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }
    
    private var snapshotFileURL: URL? {
        return containerURL?.appendingPathComponent("session_snapshot.json")
    }
    
    private var journalFileURL: URL? {
        return containerURL?.appendingPathComponent("session_events.journal")
    }
    
    // MARK: - Snapshot Management
    
    public func saveSnapshot(_ snapshot: SessionSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        
        // 1. Fast primitive cache for low-latency extension lookups
        defaults?.set(snapshot.totalTargetEndEpochMs, forKey: "endsAt")
        defaults?.set(snapshot.isStrictLockout, forKey: "isStrict")
        defaults?.set(snapshot.primaryState.rawValue, forKey: "primaryState")
        defaults?.set(snapshot.activePhase.rawValue, forKey: "activePhase")
        defaults?.synchronize()
        
        // 2. Full JSON model persistence
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(snapshot)
        
        if let fileURL = snapshotFileURL {
            try data.write(to: fileURL, options: .atomic)
        }
    }
    
    public func loadSnapshot() -> SessionSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let fileURL = snapshotFileURL,
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(SessionSnapshot.self, from: data)
    }
    
    // MARK: - Event Journal
    
    public func appendEvent(_ event: SessionEvent) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        
        guard let fileURL = journalFileURL else { return }
        
        if !fileManager.fileExists(atPath: fileURL.path) {
            try data.write(to: fileURL, options: .atomic)
        } else {
            let handle = try FileHandle(forWritingTo: fileURL)
            handle.seekToEndOfFile()
            handle.write(data)
            if let newline = "\n".data(using: .utf8) {
                handle.write(newline)
            }
            try handle.close()
        }
    }
    
    // MARK: - Clear / Reset
    
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        defaults?.removeObject(forKey: "endsAt")
        defaults?.removeObject(forKey: "isStrict")
        defaults?.removeObject(forKey: "primaryState")
        defaults?.removeObject(forKey: "activePhase")
        defaults?.synchronize()
        
        if let fileURL = snapshotFileURL {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
