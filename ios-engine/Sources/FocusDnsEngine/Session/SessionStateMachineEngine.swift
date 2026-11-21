import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Monotonic clock provider interface for anti-tamper tracking.
public protocol MonotonicClockProvider: Sendable {
    func uptimeMilliseconds() -> Int64
}

/// Continuous monotonic clock based on Darwin mach_continuous_time (keeps ticking during device sleep).
public final class ContinuousMonotonicClock: MonotonicClockProvider, @unchecked Sendable {
    public static let shared = ContinuousMonotonicClock()
    
    #if canImport(Darwin)
    private var timebaseInfo = mach_timebase_info_data_t()
    
    public init() {
        mach_timebase_info(&timebaseInfo)
    }
    
    public func uptimeMilliseconds() -> Int64 {
        let machTime = mach_continuous_time()
        let nanos = (machTime * UInt64(timebaseInfo.numer)) / UInt64(timebaseInfo.denom)
        return Int64(nanos / 1_000_000)
    }
    #else
    public init() {}
    public func uptimeMilliseconds() -> Int64 {
        return Int64(ProcessInfo.processInfo.systemUptime * 1000.0)
    }
    #endif
}

/// Legacy fallback alias
public typealias SystemMonotonicClock = ContinuousMonotonicClock

/// FocusDNS State Machine Engine for iOS 16+.
/// Pure evaluation, monotonic anchoring, catch-up scheduling, and Option B Ironclad Lockout.
public final class SessionStateMachineEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: SessionSnapshot
    private var sequenceNumber: Int64 = 1
    private var appliedEventKeys = Set<String>()
    private var eventListeners: [(SessionEvent) -> Void] = []
    private let monotonicClock: MonotonicClockProvider
    
    public var currentSnapshot: SessionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
    
    /// Indicates whether OS-level anti-removal guard (denyAppRemoval) should be locked.
    public var isAntiRemovalGuardRequired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return snapshot.isStrictLockout
    }
    
    public init(
        initialConfig: SessionConfig = SessionConfig(),
        monotonicClock: MonotonicClockProvider = SystemMonotonicClock.shared
    ) {
        self.monotonicClock = monotonicClock
        self.snapshot = SessionSnapshot(
            sessionId: "ses_init",
            primaryState: .inactive,
            activePhase: .idle,
            config: initialConfig,
            wallStartEpochMs: 0,
            monoStartMs: 0,
            totalTargetEndEpochMs: 0,
            phases: [],
            activePhaseIndex: 0,
            isVpnDegraded: false
        )
    }
    
    public func addEventListener(_ listener: @escaping (SessionEvent) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        eventListeners.append(listener)
    }
    
    private func emitEvent(_ event: SessionEvent, idempotencyKey: String) {
        appliedEventKeys.insert(idempotencyKey)
        for listener in eventListeners {
            listener(event)
        }
    }
    
    // MARK: - Lifecycle Management
    
    public func createSession(
        config: SessionConfig,
        wallNowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0),
        monoNowMs: Int64? = nil,
        idempotencyKey: String? = nil
    ) -> Result<SessionSnapshot, Error> {
        lock.lock()
        defer { lock.unlock() }
        
        let validation = config.validate()
        guard validation.isValid else {
            let err = NSError(
                domain: "FocusDnsEngine",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: validation.error ?? "ERR_OUT_OF_BOUNDS"]
            )
            return .failure(err)
        }
        
        let monoNow = monoNowMs ?? monotonicClock.uptimeMilliseconds()
        let idem = idempotencyKey ?? "idem_create_\(wallNowMs)"
        let sessionId = "ses_\(wallNowMs)_\(Int.random(in: 1000...9999))"
        
        snapshot = SessionSnapshot(
            sessionId: sessionId,
            primaryState: .inactive,
            activePhase: .idle,
            config: config,
            wallStartEpochMs: wallNowMs,
            monoStartMs: monoNow,
            totalTargetEndEpochMs: 0,
            phases: [],
            activePhaseIndex: 0,
            isVpnDegraded: false,
            lastMonotonicTickMs: monoNow
        )
        
        let event = SessionEvent.sessionCreated(
            eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
            sessionId: sessionId,
            sequenceNumber: sequenceNumber,
            timestampEpochMs: wallNowMs,
            monoTimestampMs: monoNow,
            idempotencyKey: idem,
            config: config
        )
        sequenceNumber += 1
        emitEvent(event, idempotencyKey: idem)
        
        return .success(snapshot)
    }
    
    public func startSession(
        config: SessionConfig? = nil,
        wallNowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0),
        monoNowMs: Int64? = nil,
        idempotencyKey: String? = nil
    ) -> Result<SessionSnapshot, Error> {
        lock.lock()
        defer { lock.unlock() }
        
        let activeCfg = config ?? snapshot.config
        let validation = activeCfg.validate()
        guard validation.isValid else {
            let err = NSError(
                domain: "FocusDnsEngine",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: validation.error ?? "ERR_OUT_OF_BOUNDS"]
            )
            return .failure(err)
        }
        
        let monoNow = monoNowMs ?? monotonicClock.uptimeMilliseconds()
        let idem = idempotencyKey ?? "idem_start_\(wallNowMs)"
        let sessionId = snapshot.primaryState == .inactive ? "ses_\(wallNowMs)_\(Int.random(in: 1000...9999))" : snapshot.sessionId
        
        let primaryState: PrimaryState
        let totalEndMs: Int64
        let phases: [PhaseInterval]
        
        switch activeCfg.mode {
        case .normal:
            primaryState = .activeNormal
            totalEndMs = wallNowMs + 86_400_000
            phases = []
        case .feedOnly:
            primaryState = .activeFeed
            totalEndMs = wallNowMs + 86_400_000
            phases = []
        case .strict:
            primaryState = .strictRunning
            totalEndMs = wallNowMs + Int64(activeCfg.strictMinutes * 60 * 1000)
            phases = []
        case .cycles:
            primaryState = .cyclesRunning
            let cycleResult = buildCyclesTimeline(startMs: wallNowMs, cfg: activeCfg)
            totalEndMs = cycleResult.totalEndMs
            phases = cycleResult.phases
        }
        
        let activePhase = phases.first?.phaseType ?? .focusSession
        
        snapshot = SessionSnapshot(
            sessionId: sessionId,
            primaryState: primaryState,
            activePhase: activePhase,
            config: activeCfg,
            wallStartEpochMs: wallNowMs,
            monoStartMs: monoNow,
            totalTargetEndEpochMs: totalEndMs,
            phases: phases,
            activePhaseIndex: 0,
            isVpnDegraded: snapshot.isVpnDegraded,
            pauseEndEpochMs: nil,
            lastMonotonicTickMs: monoNow,
            totalInterventionKills: snapshot.totalInterventionKills
        )
        
        let event = SessionEvent.sessionStarted(
            eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
            sessionId: sessionId,
            sequenceNumber: sequenceNumber,
            timestampEpochMs: wallNowMs,
            monoTimestampMs: monoNow,
            idempotencyKey: idem,
            mode: activeCfg.mode,
            totalTargetEndEpochMs: totalEndMs
        )
        sequenceNumber += 1
        emitEvent(event, idempotencyKey: idem)
        
        return .success(snapshot)
    }
    
    // MARK: - Option B Ironclad Lockout Enforcement (Pause / Resume / Stop)
    
    public func pauseSession(
        pauseMinutes: Int,
        wallNowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0),
        monoNowMs: Int64? = nil,
        idempotencyKey: String? = nil
    ) -> Result<SessionSnapshot, Error> {
        lock.lock()
        defer { lock.unlock() }
        
        // Strict Lockout (Option B): Reject any attempt to pause
        if snapshot.primaryState == .strictRunning || snapshot.primaryState == .cyclesRunning {
            let err = NSError(
                domain: "FocusDnsEngine",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "ERR_PAUSE_NOT_ALLOWED"]
            )
            return .failure(err)
        }
        
        guard pauseMinutes == 5 || pauseMinutes == 15 || pauseMinutes == 30 else {
            let err = NSError(
                domain: "FocusDnsEngine",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "ERR_INVALID_PAUSE_DURATION"]
            )
            return .failure(err)
        }
        
        let monoNow = monoNowMs ?? monotonicClock.uptimeMilliseconds()
        let pauseEndMs = wallNowMs + Int64(pauseMinutes * 60 * 1000)
        let idem = idempotencyKey ?? "idem_pause_\(wallNowMs)"
        
        snapshot = SessionSnapshot(
            sessionId: snapshot.sessionId,
            primaryState: .paused,
            activePhase: snapshot.activePhase,
            config: snapshot.config,
            wallStartEpochMs: snapshot.wallStartEpochMs,
            monoStartMs: snapshot.monoStartMs,
            totalTargetEndEpochMs: snapshot.totalTargetEndEpochMs,
            phases: snapshot.phases,
            activePhaseIndex: snapshot.activePhaseIndex,
            isVpnDegraded: snapshot.isVpnDegraded,
            pauseEndEpochMs: pauseEndMs,
            lastMonotonicTickMs: monoNow,
            totalInterventionKills: snapshot.totalInterventionKills
        )
        
        let event = SessionEvent.sessionPaused(
            eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
            sessionId: snapshot.sessionId,
            sequenceNumber: sequenceNumber,
            timestampEpochMs: wallNowMs,
            monoTimestampMs: monoNow,
            idempotencyKey: idem,
            pauseMinutes: pauseMinutes,
            pauseEndEpochMs: pauseEndMs
        )
        sequenceNumber += 1
        emitEvent(event, idempotencyKey: idem)
        
        return .success(snapshot)
    }
    
    public func resumeSession(
        wallNowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0),
        monoNowMs: Int64? = nil,
        reason: String = "UserResumed",
        idempotencyKey: String? = nil
    ) -> Result<SessionSnapshot, Error> {
        lock.lock()
        defer { lock.unlock() }
        
        guard snapshot.primaryState == .paused else {
            return .success(snapshot)
        }
        
        let monoNow = monoNowMs ?? monotonicClock.uptimeMilliseconds()
        let restoredState: PrimaryState = (snapshot.config.mode == .feedOnly) ? .activeFeed : .activeNormal
        let idem = idempotencyKey ?? "idem_resume_\(wallNowMs)"
        
        snapshot = SessionSnapshot(
            sessionId: snapshot.sessionId,
            primaryState: restoredState,
            activePhase: snapshot.activePhase,
            config: snapshot.config,
            wallStartEpochMs: snapshot.wallStartEpochMs,
            monoStartMs: snapshot.monoStartMs,
            totalTargetEndEpochMs: snapshot.totalTargetEndEpochMs,
            phases: snapshot.phases,
            activePhaseIndex: snapshot.activePhaseIndex,
            isVpnDegraded: snapshot.isVpnDegraded,
            pauseEndEpochMs: nil,
            lastMonotonicTickMs: monoNow,
            totalInterventionKills: snapshot.totalInterventionKills
        )
        
        let event = SessionEvent.sessionResumed(
            eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
            sessionId: snapshot.sessionId,
            sequenceNumber: sequenceNumber,
            timestampEpochMs: wallNowMs,
            monoTimestampMs: monoNow,
            idempotencyKey: idem,
            reason: reason
        )
        sequenceNumber += 1
        emitEvent(event, idempotencyKey: idem)
        
        return .success(snapshot)
    }
    
    public func stopSession(
        wallNowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0),
        monoNowMs: Int64? = nil,
        reason: String = "UserStopped",
        idempotencyKey: String? = nil
    ) -> Result<SessionSnapshot, Error> {
        lock.lock()
        defer { lock.unlock() }
        
        // Strict Lockout (Option B): Reject any attempt to stop / abort
        if snapshot.isStrictLockout {
            let err = NSError(
                domain: "FocusDnsEngine",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "ERR_STRICT_LOCKOUT_ACTIVE"]
            )
            return .failure(err)
        }
        
        let monoNow = monoNowMs ?? monotonicClock.uptimeMilliseconds()
        let idem = idempotencyKey ?? "idem_stop_\(wallNowMs)"
        
        snapshot = SessionSnapshot(
            sessionId: snapshot.sessionId,
            primaryState: .completed,
            activePhase: .idle,
            config: snapshot.config,
            wallStartEpochMs: snapshot.wallStartEpochMs,
            monoStartMs: snapshot.monoStartMs,
            totalTargetEndEpochMs: snapshot.totalTargetEndEpochMs,
            phases: snapshot.phases,
            activePhaseIndex: snapshot.activePhaseIndex,
            isVpnDegraded: snapshot.isVpnDegraded,
            pauseEndEpochMs: nil,
            lastMonotonicTickMs: monoNow,
            totalInterventionKills: snapshot.totalInterventionKills
        )
        
        let event = SessionEvent.sessionAborted(
            eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
            sessionId: snapshot.sessionId,
            sequenceNumber: sequenceNumber,
            timestampEpochMs: wallNowMs,
            monoTimestampMs: monoNow,
            idempotencyKey: idem,
            reason: reason
        )
        sequenceNumber += 1
        emitEvent(event, idempotencyKey: idem)
        
        return .success(snapshot)
    }
    
    // MARK: - Option 3 Emergency Panic Override (15-Second Hold)
    
    /// Allows immediate abort of an active strict lockout if the user confirms a continuous 15-second emergency hold.
    public func requestEmergencyPanicUnlock(
        holdDurationMs: Int64,
        wallNowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0),
        monoNowMs: Int64? = nil,
        idempotencyKey: String? = nil
    ) -> Result<SessionSnapshot, Error> {
        lock.lock()
        defer { lock.unlock() }
        
        guard snapshot.isStrictLockout else {
            return stopSession(wallNowMs: wallNowMs, monoNowMs: monoNowMs, reason: "NormalStopNotLocked", idempotencyKey: idempotencyKey)
        }
        
        // Strictly require at least 15,000 ms (15 seconds) continuous physical hold
        guard holdDurationMs >= 15_000 else {
            let err = NSError(
                domain: "FocusDnsEngine",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "ERR_PANIC_HOLD_TOO_SHORT: Must hold continuously for at least 15 seconds to abort strict focus"]
            )
            return .failure(err)
        }
        
        let monoNow = monoNowMs ?? monotonicClock.uptimeMilliseconds()
        let idem = idempotencyKey ?? "idem_panic_\(wallNowMs)"
        
        snapshot = SessionSnapshot(
            sessionId: snapshot.sessionId,
            primaryState: .completed,
            activePhase: .idle,
            config: snapshot.config,
            wallStartEpochMs: snapshot.wallStartEpochMs,
            monoStartMs: snapshot.monoStartMs,
            totalTargetEndEpochMs: snapshot.totalTargetEndEpochMs,
            phases: snapshot.phases,
            activePhaseIndex: snapshot.activePhaseIndex,
            isVpnDegraded: snapshot.isVpnDegraded,
            pauseEndEpochMs: nil,
            lastMonotonicTickMs: monoNow,
            totalInterventionKills: snapshot.totalInterventionKills
        )
        
        let event = SessionEvent.sessionAborted(
            eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
            sessionId: snapshot.sessionId,
            sequenceNumber: sequenceNumber,
            timestampEpochMs: wallNowMs,
            monoTimestampMs: monoNow,
            idempotencyKey: idem,
            reason: "EmergencyPanicOverride_15sHoldConfirmed"
        )
        sequenceNumber += 1
        emitEvent(event, idempotencyKey: idem)
        
        return .success(snapshot)
    }
    
    // MARK: - Option 5 Reboot Recovery & Time Reconciliation
    
    /// Reconciles monotonic clock resets upon device reboot using verified atomic/network timestamp.
    public func reconcileAfterReboot(
        persistedSnapshot: SessionSnapshot,
        verifiedWallNowMs: Int64,
        currentMonoNowMs: Int64? = nil
    ) -> Result<SessionSnapshot, Error> {
        lock.lock()
        defer { lock.unlock() }
        
        let monoNow = currentMonoNowMs ?? monotonicClock.uptimeMilliseconds()
        
        if persistedSnapshot.primaryState == .inactive || persistedSnapshot.primaryState == .completed {
            self.snapshot = persistedSnapshot
            return .success(self.snapshot)
        }
        
        // Check if target end epoch expired while device was powered off
        if verifiedWallNowMs >= persistedSnapshot.totalTargetEndEpochMs {
            let completedSnap = SessionSnapshot(
                sessionId: persistedSnapshot.sessionId,
                primaryState: .completed,
                activePhase: .completed,
                config: persistedSnapshot.config,
                wallStartEpochMs: persistedSnapshot.wallStartEpochMs,
                monoStartMs: 0,
                totalTargetEndEpochMs: persistedSnapshot.totalTargetEndEpochMs,
                phases: persistedSnapshot.phases,
                activePhaseIndex: persistedSnapshot.phases.count,
                isVpnDegraded: persistedSnapshot.isVpnDegraded,
                lastMonotonicTickMs: monoNow,
                totalInterventionKills: persistedSnapshot.totalInterventionKills
            )
            self.snapshot = completedSnap
            return .success(completedSnap)
        }
        
        // Session is still active. Re-anchor monotonic start to current boot uptime.
        let remainingMs = persistedSnapshot.totalTargetEndEpochMs - verifiedWallNowMs
        let reanchoredWallStart = verifiedWallNowMs
        let reanchoredTargetEnd = verifiedWallNowMs + remainingMs
        
        self.snapshot = SessionSnapshot(
            sessionId: persistedSnapshot.sessionId,
            primaryState: persistedSnapshot.primaryState,
            activePhase: persistedSnapshot.activePhase,
            config: persistedSnapshot.config,
            wallStartEpochMs: reanchoredWallStart,
            monoStartMs: monoNow,
            totalTargetEndEpochMs: reanchoredTargetEnd,
            phases: persistedSnapshot.phases,
            activePhaseIndex: persistedSnapshot.activePhaseIndex,
            isVpnDegraded: persistedSnapshot.isVpnDegraded,
            pauseEndEpochMs: persistedSnapshot.pauseEndEpochMs,
            lastMonotonicTickMs: monoNow,
            totalInterventionKills: persistedSnapshot.totalInterventionKills
        )
        
        return .success(self.snapshot)
    }
    
    public func setVpnDegraded(_ isDegraded: Bool) {
        lock.lock()
        defer { lock.unlock() }
        snapshot = SessionSnapshot(
            sessionId: snapshot.sessionId,
            primaryState: snapshot.primaryState,
            activePhase: snapshot.activePhase,
            config: snapshot.config,
            wallStartEpochMs: snapshot.wallStartEpochMs,
            monoStartMs: snapshot.monoStartMs,
            totalTargetEndEpochMs: snapshot.totalTargetEndEpochMs,
            phases: snapshot.phases,
            activePhaseIndex: snapshot.activePhaseIndex,
            isVpnDegraded: isDegraded,
            pauseEndEpochMs: snapshot.pauseEndEpochMs,
            lastMonotonicTickMs: snapshot.lastMonotonicTickMs,
            totalInterventionKills: snapshot.totalInterventionKills
        )
    }
    
    // MARK: - Catch-Up Evaluation & Clock Tamper Detection
    
    @discardableResult
    public func evaluateCatchUp(
        wallNowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0),
        monoNowMs: Int64? = nil
    ) -> [SessionEvent] {
        lock.lock()
        defer { lock.unlock() }
        
        let monoNow = monoNowMs ?? monotonicClock.uptimeMilliseconds()
        var events: [SessionEvent] = []
        let elapsedMono = monoNow - snapshot.monoStartMs
        let effectiveNow = snapshot.wallStartEpochMs + elapsedMono
        
        // Anti-Tamper Clock Jumps
        if wallNowMs < snapshot.wallStartEpochMs {
            let evt = SessionEvent.tamperDetected(
                eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
                sessionId: snapshot.sessionId,
                sequenceNumber: sequenceNumber,
                timestampEpochMs: wallNowMs,
                monoTimestampMs: monoNow,
                idempotencyKey: "tamper_back_\(wallNowMs)",
                alertType: "BACKWARD_TIME_JUMP_DETECTED",
                details: "Wall clock shifted back by \(snapshot.wallStartEpochMs - wallNowMs)ms"
            )
            sequenceNumber += 1
            events.append(evt)
            emitEvent(evt, idempotencyKey: "tamper_back_\(wallNowMs)")
        } else if (wallNowMs - effectiveNow) > 15_000 {
            let evt = SessionEvent.tamperDetected(
                eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
                sessionId: snapshot.sessionId,
                sequenceNumber: sequenceNumber,
                timestampEpochMs: wallNowMs,
                monoTimestampMs: monoNow,
                idempotencyKey: "tamper_jump_\(wallNowMs)",
                alertType: "CLOCK_MANIPULATION_DETECTED",
                details: "Wall clock jumped forward artificially by \(wallNowMs - effectiveNow)ms"
            )
            sequenceNumber += 1
            events.append(evt)
            emitEvent(evt, idempotencyKey: "tamper_jump_\(wallNowMs)")
        }
        
        // Auto-resume paused session if pause timer expired
        if snapshot.primaryState == .paused, let pauseEnd = snapshot.pauseEndEpochMs {
            if wallNowMs >= pauseEnd {
                let restoredState: PrimaryState = (snapshot.config.mode == .feedOnly) ? .activeFeed : .activeNormal
                snapshot = SessionSnapshot(
                    sessionId: snapshot.sessionId,
                    primaryState: restoredState,
                    activePhase: snapshot.activePhase,
                    config: snapshot.config,
                    wallStartEpochMs: snapshot.wallStartEpochMs,
                    monoStartMs: snapshot.monoStartMs,
                    totalTargetEndEpochMs: snapshot.totalTargetEndEpochMs,
                    phases: snapshot.phases,
                    activePhaseIndex: snapshot.activePhaseIndex,
                    isVpnDegraded: snapshot.isVpnDegraded,
                    pauseEndEpochMs: nil,
                    lastMonotonicTickMs: monoNow,
                    totalInterventionKills: snapshot.totalInterventionKills
                )
                let resEvt = SessionEvent.sessionResumed(
                    eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
                    sessionId: snapshot.sessionId,
                    sequenceNumber: sequenceNumber,
                    timestampEpochMs: wallNowMs,
                    monoTimestampMs: monoNow,
                    idempotencyKey: "idem_resume_auto_\(wallNowMs)",
                    reason: "PauseTimerExpired"
                )
                sequenceNumber += 1
                events.append(resEvt)
                emitEvent(resEvt, idempotencyKey: "idem_resume_auto_\(wallNowMs)")
            }
        }
        
        // Strict mode completion evaluation
        if snapshot.primaryState == .strictRunning {
            if effectiveNow >= snapshot.totalTargetEndEpochMs {
                snapshot = SessionSnapshot(
                    sessionId: snapshot.sessionId,
                    primaryState: .completed,
                    activePhase: .completed,
                    config: snapshot.config,
                    wallStartEpochMs: snapshot.wallStartEpochMs,
                    monoStartMs: snapshot.monoStartMs,
                    totalTargetEndEpochMs: snapshot.totalTargetEndEpochMs,
                    phases: snapshot.phases,
                    activePhaseIndex: snapshot.activePhaseIndex,
                    isVpnDegraded: snapshot.isVpnDegraded,
                    pauseEndEpochMs: nil,
                    lastMonotonicTickMs: monoNow,
                    totalInterventionKills: snapshot.totalInterventionKills
                )
                let compEvt = SessionEvent.sessionCompleted(
                    eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
                    sessionId: snapshot.sessionId,
                    sequenceNumber: sequenceNumber,
                    timestampEpochMs: wallNowMs,
                    monoTimestampMs: monoNow,
                    idempotencyKey: "idem_complete_\(snapshot.sessionId)",
                    totalFocusSeconds: elapsedMono / 1000,
                    totalInterventionKills: snapshot.totalInterventionKills
                )
                sequenceNumber += 1
                events.append(compEvt)
                emitEvent(compEvt, idempotencyKey: "idem_complete_\(snapshot.sessionId)")
            }
            return events
        }
        
        // Cycles mode phase advance evaluation
        if snapshot.primaryState == .cyclesRunning {
            if effectiveNow >= snapshot.totalTargetEndEpochMs {
                snapshot = SessionSnapshot(
                    sessionId: snapshot.sessionId,
                    primaryState: .completed,
                    activePhase: .completed,
                    config: snapshot.config,
                    wallStartEpochMs: snapshot.wallStartEpochMs,
                    monoStartMs: snapshot.monoStartMs,
                    totalTargetEndEpochMs: snapshot.totalTargetEndEpochMs,
                    phases: snapshot.phases,
                    activePhaseIndex: snapshot.activePhaseIndex,
                    isVpnDegraded: snapshot.isVpnDegraded,
                    pauseEndEpochMs: nil,
                    lastMonotonicTickMs: monoNow,
                    totalInterventionKills: snapshot.totalInterventionKills
                )
                let compEvt = SessionEvent.sessionCompleted(
                    eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
                    sessionId: snapshot.sessionId,
                    sequenceNumber: sequenceNumber,
                    timestampEpochMs: wallNowMs,
                    monoTimestampMs: monoNow,
                    idempotencyKey: "idem_complete_\(snapshot.sessionId)",
                    totalFocusSeconds: elapsedMono / 1000,
                    totalInterventionKills: snapshot.totalInterventionKills
                )
                sequenceNumber += 1
                events.append(compEvt)
                emitEvent(compEvt, idempotencyKey: "idem_complete_\(snapshot.sessionId)")
                return events
            }
            
            for p in snapshot.phases {
                if effectiveNow >= p.startEpochMs && effectiveNow < p.endEpochMs {
                    if snapshot.activePhaseIndex != p.phaseIndex {
                        let oldPhase = snapshot.activePhase
                        let newPhase = p.phaseType
                        
                        snapshot = SessionSnapshot(
                            sessionId: snapshot.sessionId,
                            primaryState: snapshot.primaryState,
                            activePhase: newPhase,
                            config: snapshot.config,
                            wallStartEpochMs: snapshot.wallStartEpochMs,
                            monoStartMs: snapshot.monoStartMs,
                            totalTargetEndEpochMs: snapshot.totalTargetEndEpochMs,
                            phases: snapshot.phases,
                            activePhaseIndex: p.phaseIndex,
                            isVpnDegraded: snapshot.isVpnDegraded,
                            pauseEndEpochMs: snapshot.pauseEndEpochMs,
                            lastMonotonicTickMs: monoNow,
                            totalInterventionKills: snapshot.totalInterventionKills
                        )
                        
                        let phaseEvt = SessionEvent.phaseAdvanced(
                            eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
                            sessionId: snapshot.sessionId,
                            sequenceNumber: sequenceNumber,
                            timestampEpochMs: wallNowMs,
                            monoTimestampMs: monoNow,
                            idempotencyKey: "idem_phase_\(p.phaseIndex)_\(snapshot.sessionId)",
                            oldPhase: oldPhase,
                            newPhase: newPhase,
                            cycleNumber: p.cycleNumber
                        )
                        sequenceNumber += 1
                        events.append(phaseEvt)
                        emitEvent(phaseEvt, idempotencyKey: "idem_phase_\(p.phaseIndex)_\(snapshot.sessionId)")
                        
                        if oldPhase == .breakExpiringGrace && newPhase == .focusSession {
                            let killEvt = SessionEvent.appTerminationSweepTriggered(
                                eventId: "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))",
                                sessionId: snapshot.sessionId,
                                sequenceNumber: sequenceNumber,
                                timestampEpochMs: wallNowMs,
                                monoTimestampMs: monoNow,
                                idempotencyKey: "idem_sweep_\(p.phaseIndex)_\(snapshot.sessionId)",
                                cycleNumber: p.cycleNumber
                            )
                            sequenceNumber += 1
                            events.append(killEvt)
                            emitEvent(killEvt, idempotencyKey: "idem_sweep_\(p.phaseIndex)_\(snapshot.sessionId)")
                        }
                    }
                    break
                }
            }
        }
        
        return events
    }
    
    // MARK: - Pure Policy Evaluation Function
    
    public func isBlocked(
        target: EvaluationTarget,
        wallNowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0),
        monoNowMs: Int64? = nil
    ) -> SessionDecision {
        evaluateCatchUp(wallNowMs: wallNowMs, monoNowMs: monoNowMs)
        
        lock.lock()
        let snap = self.snapshot
        lock.unlock()
        
        let st = snap.primaryState
        if st == .inactive || st == .completed {
            return SessionDecision(isBlocked: false, reason: "Session inactive", enforcedBy: .none)
        }
        if st == .paused {
            return SessionDecision(isBlocked: false, reason: "Session is paused", enforcedBy: .none)
        }
        
        let subfeature = target.subfeature
        let category = target.category
        let bundleId = target.bundleIdentifier
        let domain = target.domain
        
        // Clean domain bypass in normal/unrestricted state
        let cleanDomains: Set<String> = ["wikipedia.org", "google.com", "apple.com", "github.com"]
        if let d = domain, cleanDomains.contains(d), bundleId == nil, category == nil {
            return SessionDecision(isBlocked: false, reason: "Allowed clean domain", enforcedBy: .none)
        }
        
        // Category checks (e.g. Adult, Gambling, Piracy)
        if let cat = category, ["porn", "gambling", "piracy"].contains(cat) {
            let catName: String
            switch cat {
            case "porn": catName = "Adult & Pornography"
            case "gambling": catName = "Gambling"
            default: catName = "Piracy"
            }
            return SessionDecision(
                isBlocked: true,
                reason: "Blocked category: \(catName)",
                enforcedBy: .dns
            )
        }
        
        // Feed-Only mode surgical decisions
        if st == .activeFeed {
            if let sf = subfeature, ["reelsOrShorts", "feed", "explore"].contains(sf) {
                return SessionDecision(
                    isBlocked: true,
                    reason: "Feed-Only restriction: \(sf)",
                    enforcedBy: .feedInspector
                )
            } else if let sf = subfeature, ["watch", "messages", "search"].contains(sf) {
                let subReason = (sf == "watch")
                    ? "Educational watch subfeature permitted in Feed-Only mode"
                    : "Direct messaging permitted in Feed-Only mode"
                return SessionDecision(isBlocked: false, reason: subReason, enforcedBy: .none)
            }
        }
        
        // Cycles Break allowance
        if st == .cyclesRunning && snap.activePhase == .breakSession {
            return SessionDecision(isBlocked: false, reason: "Micro-Break allowance active", enforcedBy: .none)
        }
        
        // Strict / Cycles Focus / Normal Block active
        let reason: String
        switch st {
        case .strictRunning:
            reason = "Strict Lockout active (monotonic anchor enforced)"
        case .cyclesRunning:
            reason = "Cycle Focus Session active"
        default:
            reason = snap.isVpnDegraded
                ? "App blocked in session (degraded DNS fallback to shield)"
                : "App or domain blocked in active session"
        }
        
        let enforcer: EnforcerType
        if snap.isVpnDegraded || (bundleId != nil && !bundleId!.isEmpty) {
            enforcer = .shield
        } else {
            enforcer = .dns
        }
        
        return SessionDecision(
            isBlocked: true,
            reason: reason,
            enforcedBy: enforcer,
            allowFallback: snap.isVpnDegraded
        )
    }
    
    // MARK: - Cycles Timeline Precomputation
    
    private func buildCyclesTimeline(startMs: Int64, cfg: SessionConfig) -> (totalEndMs: Int64, phases: [PhaseInterval]) {
        let fMs = Int64(cfg.focusMinutes * 60 * 1000)
        let bMs = Int64(cfg.breakMinutes * 60 * 1000)
        let cycles = cfg.totalCycles
        let prepGraceMs: Int64 = 10 * 1000
        let breakGraceMs: Int64 = 30 * 1000
        
        var phases: [PhaseInterval] = []
        var curr = startMs
        var idx = 0
        
        // Initial Prep Grace
        phases.append(PhaseInterval(phaseIndex: idx, phaseType: .preparationGrace, cycleNumber: 1, startEpochMs: curr, endEpochMs: curr + prepGraceMs))
        idx += 1
        curr += prepGraceMs
        
        for c in 1...cycles {
            // Focus
            phases.append(PhaseInterval(phaseIndex: idx, phaseType: .focusSession, cycleNumber: c, startEpochMs: curr, endEpochMs: curr + fMs))
            idx += 1
            curr += fMs
            
            // Break
            let mainBreakMs = max(0, bMs - breakGraceMs)
            phases.append(PhaseInterval(phaseIndex: idx, phaseType: .breakSession, cycleNumber: c, startEpochMs: curr, endEpochMs: curr + mainBreakMs))
            idx += 1
            curr += mainBreakMs
            
            // Break Grace
            phases.append(PhaseInterval(phaseIndex: idx, phaseType: .breakExpiringGrace, cycleNumber: c, startEpochMs: curr, endEpochMs: curr + breakGraceMs))
            idx += 1
            curr += breakGraceMs
        }
        
        phases.append(PhaseInterval(phaseIndex: idx, phaseType: .completed, cycleNumber: cycles, startEpochMs: curr, endEpochMs: curr))
        return (totalEndMs: curr, phases: phases)
    }
}
