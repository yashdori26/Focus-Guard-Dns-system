import Foundation

/// Append-only immutable session event hierarchy.
public enum SessionEvent: Codable, Equatable, Sendable {
    case sessionCreated(
        eventId: String,
        sessionId: String,
        sequenceNumber: Int64,
        timestampEpochMs: Int64,
        monoTimestampMs: Int64,
        idempotencyKey: String,
        config: SessionConfig
    )
    case sessionStarted(
        eventId: String,
        sessionId: String,
        sequenceNumber: Int64,
        timestampEpochMs: Int64,
        monoTimestampMs: Int64,
        idempotencyKey: String,
        mode: SessionMode,
        totalTargetEndEpochMs: Int64
    )
    case sessionPaused(
        eventId: String,
        sessionId: String,
        sequenceNumber: Int64,
        timestampEpochMs: Int64,
        monoTimestampMs: Int64,
        idempotencyKey: String,
        pauseMinutes: Int,
        pauseEndEpochMs: Int64
    )
    case sessionResumed(
        eventId: String,
        sessionId: String,
        sequenceNumber: Int64,
        timestampEpochMs: Int64,
        monoTimestampMs: Int64,
        idempotencyKey: String,
        reason: String
    )
    case phaseAdvanced(
        eventId: String,
        sessionId: String,
        sequenceNumber: Int64,
        timestampEpochMs: Int64,
        monoTimestampMs: Int64,
        idempotencyKey: String,
        oldPhase: PhaseType,
        newPhase: PhaseType,
        cycleNumber: Int
    )
    case appTerminationSweepTriggered(
        eventId: String,
        sessionId: String,
        sequenceNumber: Int64,
        timestampEpochMs: Int64,
        monoTimestampMs: Int64,
        idempotencyKey: String,
        cycleNumber: Int
    )
    case sessionCompleted(
        eventId: String,
        sessionId: String,
        sequenceNumber: Int64,
        timestampEpochMs: Int64,
        monoTimestampMs: Int64,
        idempotencyKey: String,
        totalFocusSeconds: Int64,
        totalInterventionKills: Int
    )
    case sessionAborted(
        eventId: String,
        sessionId: String,
        sequenceNumber: Int64,
        timestampEpochMs: Int64,
        monoTimestampMs: Int64,
        idempotencyKey: String,
        reason: String
    )
    case tamperDetected(
        eventId: String,
        sessionId: String,
        sequenceNumber: Int64,
        timestampEpochMs: Int64,
        monoTimestampMs: Int64,
        idempotencyKey: String,
        alertType: String,
        details: String
    )
    
    public var sessionId: String {
        switch self {
        case .sessionCreated(_, let s, _, _, _, _, _),
             .sessionStarted(_, let s, _, _, _, _, _, _),
             .sessionPaused(_, let s, _, _, _, _, _, _),
             .sessionResumed(_, let s, _, _, _, _, _),
             .phaseAdvanced(_, let s, _, _, _, _, _, _, _),
             .appTerminationSweepTriggered(_, let s, _, _, _, _, _),
             .sessionCompleted(_, let s, _, _, _, _, _, _),
             .sessionAborted(_, let s, _, _, _, _, _),
             .tamperDetected(_, let s, _, _, _, _, _, _):
            return s
        }
    }
    
    public var sequenceNumber: Int64 {
        switch self {
        case .sessionCreated(_, _, let seq, _, _, _, _),
             .sessionStarted(_, _, let seq, _, _, _, _, _),
             .sessionPaused(_, _, let seq, _, _, _, _, _),
             .sessionResumed(_, _, let seq, _, _, _, _),
             .phaseAdvanced(_, _, let seq, _, _, _, _, _, _),
             .appTerminationSweepTriggered(_, _, let seq, _, _, _, _),
             .sessionCompleted(_, _, let seq, _, _, _, _, _),
             .sessionAborted(_, _, let seq, _, _, _, _),
             .tamperDetected(_, _, let seq, _, _, _, _, _):
            return seq
        }
    }
}
