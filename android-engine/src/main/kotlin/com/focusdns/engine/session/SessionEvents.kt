package com.focusdns.engine.session

import java.util.UUID

/**
 * Append-only immutable session event hierarchy.
 */
sealed class SessionEvent(
    open val eventId: String = "evt_" + UUID.randomUUID().toString().replace("-", "").take(16),
    open val sessionId: String,
    open val sequenceNumber: Long,
    open val timestampEpochMs: Long,
    open val monoTimestampMs: Long,
    open val idempotencyKey: String
) {
    data class SessionCreated(
        override val sessionId: String,
        override val sequenceNumber: Long,
        override val timestampEpochMs: Long,
        override val monoTimestampMs: Long,
        override val idempotencyKey: String,
        val config: SessionConfig
    ) : SessionEvent(sessionId = sessionId, sequenceNumber = sequenceNumber, timestampEpochMs = timestampEpochMs, monoTimestampMs = monoTimestampMs, idempotencyKey = idempotencyKey)

    data class SessionStarted(
        override val sessionId: String,
        override val sequenceNumber: Long,
        override val timestampEpochMs: Long,
        override val monoTimestampMs: Long,
        override val idempotencyKey: String,
        val mode: SessionMode,
        val totalTargetEndEpochMs: Long
    ) : SessionEvent(sessionId = sessionId, sequenceNumber = sequenceNumber, timestampEpochMs = timestampEpochMs, monoTimestampMs = monoTimestampMs, idempotencyKey = idempotencyKey)

    data class SessionPaused(
        override val sessionId: String,
        override val sequenceNumber: Long,
        override val timestampEpochMs: Long,
        override val monoTimestampMs: Long,
        override val idempotencyKey: String,
        val pauseMinutes: Int,
        val pauseEndEpochMs: Long
    ) : SessionEvent(sessionId = sessionId, sequenceNumber = sequenceNumber, timestampEpochMs = timestampEpochMs, monoTimestampMs = monoTimestampMs, idempotencyKey = idempotencyKey)

    data class SessionResumed(
        override val sessionId: String,
        override val sequenceNumber: Long,
        override val timestampEpochMs: Long,
        override val monoTimestampMs: Long,
        override val idempotencyKey: String,
        val reason: String
    ) : SessionEvent(sessionId = sessionId, sequenceNumber = sequenceNumber, timestampEpochMs = timestampEpochMs, monoTimestampMs = monoTimestampMs, idempotencyKey = idempotencyKey)

    data class PhaseAdvanced(
        override val sessionId: String,
        override val sequenceNumber: Long,
        override val timestampEpochMs: Long,
        override val monoTimestampMs: Long,
        override val idempotencyKey: String,
        val oldPhase: PhaseType,
        val newPhase: PhaseType,
        val cycleNumber: Int
    ) : SessionEvent(sessionId = sessionId, sequenceNumber = sequenceNumber, timestampEpochMs = timestampEpochMs, monoTimestampMs = monoTimestampMs, idempotencyKey = idempotencyKey)

    data class AppTerminationSweepTriggered(
        override val sessionId: String,
        override val sequenceNumber: Long,
        override val timestampEpochMs: Long,
        override val monoTimestampMs: Long,
        override val idempotencyKey: String,
        val cycleNumber: Int
    ) : SessionEvent(sessionId = sessionId, sequenceNumber = sequenceNumber, timestampEpochMs = timestampEpochMs, monoTimestampMs = monoTimestampMs, idempotencyKey = idempotencyKey)

    data class SessionCompleted(
        override val sessionId: String,
        override val sequenceNumber: Long,
        override val timestampEpochMs: Long,
        override val monoTimestampMs: Long,
        override val idempotencyKey: String,
        val totalFocusSeconds: Long,
        val totalInterventionKills: Int
    ) : SessionEvent(sessionId = sessionId, sequenceNumber = sequenceNumber, timestampEpochMs = timestampEpochMs, monoTimestampMs = monoTimestampMs, idempotencyKey = idempotencyKey)

    data class SessionAborted(
        override val sessionId: String,
        override val sequenceNumber: Long,
        override val timestampEpochMs: Long,
        override val monoTimestampMs: Long,
        override val idempotencyKey: String,
        val reason: String
    ) : SessionEvent(sessionId = sessionId, sequenceNumber = sequenceNumber, timestampEpochMs = timestampEpochMs, monoTimestampMs = monoTimestampMs, idempotencyKey = idempotencyKey)

    data class TamperDetected(
        override val sessionId: String,
        override val sequenceNumber: Long,
        override val timestampEpochMs: Long,
        override val monoTimestampMs: Long,
        override val idempotencyKey: String,
        val alertType: String,
        val details: String
    ) : SessionEvent(sessionId = sessionId, sequenceNumber = sequenceNumber, timestampEpochMs = timestampEpochMs, monoTimestampMs = monoTimestampMs, idempotencyKey = idempotencyKey)
}
