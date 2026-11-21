package com.focusdns.engine.session

/**
 * Fundamental session modes supported by FocusDNS.
 */
enum class SessionMode {
    NORMAL,
    STRICT,
    CYCLES,
    FEED_ONLY
}

/**
 * Top-level session machine state.
 */
enum class PrimaryState {
    INACTIVE,
    ACTIVE_NORMAL,
    ACTIVE_FEED,
    PAUSED,
    STRICT_RUNNING,
    CYCLES_RUNNING,
    COMPLETED
}

/**
 * Sub-phases inside Cycles or Focus sessions.
 */
enum class PhaseType {
    IDLE,
    PREPARATION_GRACE,
    FOCUS_SESSION,
    BREAK_SESSION,
    BREAK_EXPIRING_GRACE,
    APP_TERMINATION_SWEEP,
    CYCLE_ADVANCE,
    COMPLETED
}

/**
 * Mechanism enforcing the block decision.
 */
enum class EnforcerType {
    NONE,
    DNS,
    SHIELD,
    FEED_INSPECTOR
}

/**
 * Immutable phase interval in an absolute timeline.
 */
data class PhaseInterval(
    val phaseIndex: Int,
    val phaseType: PhaseType,
    val cycleNumber: Int,
    val startEpochMs: Long,
    val endEpochMs: Long
) {
    val durationMs: Long get() = endEpochMs - startEpochMs
}

/**
 * Configuration payload defining session parameters.
 */
data class SessionConfig(
    val mode: SessionMode = SessionMode.NORMAL,
    val strictMinutes: Int = 25,
    val focusMinutes: Int = 25,
    val breakMinutes: Int = 5,
    val totalCycles: Int = 4,
    val autoTerminateOnBreakEnd: Boolean = true,
    val label: String = "Focus Routine"
) {
    fun validate(): Pair<Boolean, String?> {
        return when (mode) {
            SessionMode.STRICT -> {
                if (strictMinutes < 5 || strictMinutes > 480) {
                    Pair(false, "ERR_OUT_OF_BOUNDS")
                } else Pair(true, null)
            }
            SessionMode.CYCLES -> {
                if (focusMinutes < 5 || focusMinutes > 480 ||
                    breakMinutes < 5 || breakMinutes > 30 ||
                    totalCycles < 1 || totalCycles > 12
                ) {
                    Pair(false, "ERR_OUT_OF_BOUNDS")
                } else Pair(true, null)
            }
            SessionMode.NORMAL, SessionMode.FEED_ONLY -> Pair(true, null)
        }
    }
}

/**
 * Deterministic policy decision returned by pure function `isBlocked`.
 */
data class SessionDecision(
    val isBlocked: Boolean,
    val reason: String,
    val enforcedBy: EnforcerType,
    val allowFallback: Boolean = false
)

/**
 * Target evaluation request.
 */
data class EvaluationTarget(
    val packageName: String? = null,
    val domain: String? = null,
    val subfeature: String? = null, // "reelsOrShorts", "feed", "explore", "messages", "watch"
    val category: String? = null    // "porn", "gambling", "piracy", "social", "gaming"
)

/**
 * Immutable session snapshot at any instant.
 */
data class SessionSnapshot(
    val sessionId: String,
    val primaryState: PrimaryState,
    val activePhase: PhaseType,
    val config: SessionConfig,
    val wallStartEpochMs: Long,
    val monoStartMs: Long,
    val totalTargetEndEpochMs: Long,
    val phases: List<PhaseInterval>,
    val activePhaseIndex: Int,
    val isVpnDegraded: Boolean = false,
    val pauseEndEpochMs: Long? = null,
    val lastMonotonicTickMs: Long = 0L,
    val totalInterventionKills: Int = 0
) {
    val isRunning: Boolean
        get() = primaryState != PrimaryState.INACTIVE && primaryState != PrimaryState.COMPLETED

    val isStrictLockout: Boolean
        get() = primaryState == PrimaryState.STRICT_RUNNING || primaryState == PrimaryState.CYCLES_RUNNING

    val isFocusActive: Boolean
        get() = activePhase == PhaseType.FOCUS_SESSION || primaryState == PrimaryState.STRICT_RUNNING

    val isBreakActive: Boolean
        get() = activePhase == PhaseType.BREAK_SESSION
}
