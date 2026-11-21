import Foundation

/// Fundamental session modes supported by FocusDNS.
public enum SessionMode: String, Codable, Sendable, CaseIterable {
    case normal = "NORMAL"
    case strict = "STRICT"
    case cycles = "CYCLES"
    case feedOnly = "FEED_ONLY"
}

/// Top-level session machine state.
public enum PrimaryState: String, Codable, Sendable, CaseIterable {
    case inactive = "INACTIVE"
    case activeNormal = "ACTIVE_NORMAL"
    case activeFeed = "ACTIVE_FEED"
    case paused = "PAUSED"
    case strictRunning = "STRICT_RUNNING"
    case cyclesRunning = "CYCLES_RUNNING"
    case completed = "COMPLETED"
}

/// Sub-phases inside Cycles or Focus sessions.
public enum PhaseType: String, Codable, Sendable, CaseIterable {
    case idle = "IDLE"
    case preparationGrace = "PREPARATION_GRACE"
    case focusSession = "FOCUS_SESSION"
    case breakSession = "BREAK_SESSION"
    case breakExpiringGrace = "BREAK_EXPIRING_GRACE"
    case appTerminationSweep = "APP_TERMINATION_SWEEP"
    case cycleAdvance = "CYCLE_ADVANCE"
    case completed = "COMPLETED"
}

/// Mechanism enforcing the block decision.
public enum EnforcerType: String, Codable, Sendable {
    case none = "NONE"
    case dns = "DNS"
    case shield = "SHIELD"
    case feedInspector = "FEED_INSPECTOR"
}

/// Immutable phase interval in an absolute timeline.
public struct PhaseInterval: Codable, Equatable, Sendable {
    public let phaseIndex: Int
    public let phaseType: PhaseType
    public let cycleNumber: Int
    public let startEpochMs: Int64
    public let endEpochMs: Int64
    
    public var durationMs: Int64 {
        return endEpochMs - startEpochMs
    }
    
    public init(
        phaseIndex: Int,
        phaseType: PhaseType,
        cycleNumber: Int,
        startEpochMs: Int64,
        endEpochMs: Int64
    ) {
        self.phaseIndex = phaseIndex
        self.phaseType = phaseType
        self.cycleNumber = cycleNumber
        self.startEpochMs = startEpochMs
        self.endEpochMs = endEpochMs
    }
}

/// Configuration payload defining session parameters.
public struct SessionConfig: Codable, Equatable, Sendable {
    public let mode: SessionMode
    public let strictMinutes: Int
    public let focusMinutes: Int
    public let breakMinutes: Int
    public let totalCycles: Int
    public let autoTerminateOnBreakEnd: Bool
    public let label: String
    
    public init(
        mode: SessionMode = .normal,
        strictMinutes: Int = 25,
        focusMinutes: Int = 25,
        breakMinutes: Int = 5,
        totalCycles: Int = 4,
        autoTerminateOnBreakEnd: Bool = true,
        label: String = "Focus Routine"
    ) {
        self.mode = mode
        self.strictMinutes = strictMinutes
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        self.totalCycles = totalCycles
        self.autoTerminateOnBreakEnd = autoTerminateOnBreakEnd
        self.label = label
    }
    
    public func validate() -> (isValid: Bool, error: String?) {
        switch mode {
        case .strict:
            if strictMinutes < 5 || strictMinutes > 480 {
                return (false, "ERR_OUT_OF_BOUNDS")
            }
            return (true, nil)
        case .cycles:
            if focusMinutes < 5 || focusMinutes > 480 ||
                breakMinutes < 5 || breakMinutes > 30 ||
                totalCycles < 1 || totalCycles > 12 {
                return (false, "ERR_OUT_OF_BOUNDS")
            }
            return (true, nil)
        case .normal, .feedOnly:
            return (true, nil)
        }
    }
}

/// Deterministic policy decision returned by pure function `isBlocked`.
public struct SessionDecision: Codable, Equatable, Sendable {
    public let isBlocked: Bool
    public let reason: String
    public let enforcedBy: EnforcerType
    public let allowFallback: Bool
    
    public init(
        isBlocked: Bool,
        reason: String,
        enforcedBy: EnforcerType,
        allowFallback: Bool = false
    ) {
        self.isBlocked = isBlocked
        self.reason = reason
        self.enforcedBy = enforcedBy
        self.allowFallback = allowFallback
    }
}

/// Target evaluation request.
public struct EvaluationTarget: Equatable, Sendable {
    public let bundleIdentifier: String?
    public let domain: String?
    public let subfeature: String? // "reelsOrShorts", "feed", "explore", "messages", "watch"
    public let category: String?   // "porn", "gambling", "piracy", "social", "gaming"
    
    public init(
        bundleIdentifier: String? = nil,
        domain: String? = nil,
        subfeature: String? = nil,
        category: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.domain = domain
        self.subfeature = subfeature
        self.category = category
    }
}

/// Immutable session snapshot at any instant.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    public let sessionId: String
    public let primaryState: PrimaryState
    public let activePhase: PhaseType
    public let config: SessionConfig
    public let wallStartEpochMs: Int64
    public let monoStartMs: Int64
    public let totalTargetEndEpochMs: Int64
    public let phases: [PhaseInterval]
    public let activePhaseIndex: Int
    public let isVpnDegraded: Bool
    public let pauseEndEpochMs: Int64?
    public let lastMonotonicTickMs: Int64
    public let totalInterventionKills: Int
    
    public var isRunning: Bool {
        return primaryState != .inactive && primaryState != .completed
    }
    
    public var isStrictLockout: Bool {
        return primaryState == .strictRunning || primaryState == .cyclesRunning
    }
    
    public var isFocusActive: Bool {
        return activePhase == .focusSession || primaryState == .strictRunning
    }
    
    public var isBreakActive: Bool {
        return activePhase == .breakSession
    }
    
    public init(
        sessionId: String,
        primaryState: PrimaryState,
        activePhase: PhaseType,
        config: SessionConfig,
        wallStartEpochMs: Int64,
        monoStartMs: Int64,
        totalTargetEndEpochMs: Int64,
        phases: [PhaseInterval],
        activePhaseIndex: Int,
        isVpnDegraded: Bool = false,
        pauseEndEpochMs: Int64? = nil,
        lastMonotonicTickMs: Int64 = 0,
        totalInterventionKills: Int = 0
    ) {
        self.sessionId = sessionId
        self.primaryState = primaryState
        self.activePhase = activePhase
        self.config = config
        self.wallStartEpochMs = wallStartEpochMs
        self.monoStartMs = monoStartMs
        self.totalTargetEndEpochMs = totalTargetEndEpochMs
        self.phases = phases
        self.activePhaseIndex = activePhaseIndex
        self.isVpnDegraded = isVpnDegraded
        self.pauseEndEpochMs = pauseEndEpochMs
        self.lastMonotonicTickMs = lastMonotonicTickMs
        self.totalInterventionKills = totalInterventionKills
    }
}
