package com.focusdns.engine.session

import android.os.SystemClock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Android Session State Machine Engine.
 * Fully conforms to the FocusDNS shared specification.
 */
class SessionStateMachineEngine(
    initialConfig: SessionConfig = SessionConfig()
) {
    private var snapshot: SessionSnapshot = createInitialSnapshot(initialConfig)
    private val appliedEventKeys = ConcurrentHashMap.newKeySet<String>()
    private val eventListeners = CopyOnWriteArrayList<(SessionEvent) -> Unit>()
    private var sequenceNumber = 1L

    val currentSnapshot: SessionSnapshot
        @Synchronized get() = snapshot

    fun addEventListener(listener: (SessionEvent) -> Unit) {
        eventListeners.add(listener)
    }

    fun removeEventListener(listener: (SessionEvent) -> Unit) {
        eventListeners.remove(listener)
    }

    private fun emitEvent(event: SessionEvent) {
        appliedEventKeys.add(event.idempotencyKey)
        eventListeners.forEach { it.invoke(event) }
    }

    @Synchronized
    fun createSession(
        config: SessionConfig,
        wallNowMs: Long = System.currentTimeMillis(),
        monoNowMs: Long = SystemClock.elapsedRealtime(),
        idempotencyKey: String = "idem_create_${wallNowMs}"
    ): Result<SessionSnapshot> {
        val (valid, error) = config.validate()
        if (!valid) {
            return Result.failure(IllegalArgumentException(error ?: "ERR_OUT_OF_BOUNDS"))
        }

        val sessionId = "ses_${wallNowMs}_${(1000..9999).random()}"
        snapshot = SessionSnapshot(
            sessionId = sessionId,
            primaryState = PrimaryState.INACTIVE,
            activePhase = PhaseType.IDLE,
            config = config,
            wallStartEpochMs = wallNowMs,
            monoStartMs = monoNowMs,
            totalTargetEndEpochMs = 0L,
            phases = emptyList(),
            activePhaseIndex = 0,
            isVpnDegraded = false,
            lastMonotonicTickMs = monoNowMs
        )

        emitEvent(
            SessionEvent.SessionCreated(
                sessionId = sessionId,
                sequenceNumber = sequenceNumber++,
                timestampEpochMs = wallNowMs,
                monoTimestampMs = monoNowMs,
                idempotencyKey = idempotencyKey,
                config = config
            )
        )

        return Result.success(snapshot)
    }

    @Synchronized
    fun startSession(
        config: SessionConfig? = null,
        wallNowMs: Long = System.currentTimeMillis(),
        monoNowMs: Long = SystemClock.elapsedRealtime(),
        idempotencyKey: String = "idem_start_${wallNowMs}"
    ): Result<SessionSnapshot> {
        val activeCfg = config ?: snapshot.config
        val (valid, error) = activeCfg.validate()
        if (!valid) {
            return Result.failure(IllegalArgumentException(error ?: "ERR_OUT_OF_BOUNDS"))
        }

        val sessionId = if (snapshot.primaryState == PrimaryState.INACTIVE) {
            "ses_${wallNowMs}_${(1000..9999).random()}"
        } else snapshot.sessionId

        val (primaryState, totalEndMs, phases) = when (activeCfg.mode) {
            SessionMode.NORMAL -> {
                Triple(PrimaryState.ACTIVE_NORMAL, wallNowMs + 86400000L, emptyList())
            }
            SessionMode.FEED_ONLY -> {
                Triple(PrimaryState.ACTIVE_FEED, wallNowMs + 86400000L, emptyList())
            }
            SessionMode.STRICT -> {
                val durMs = activeCfg.strictMinutes * 60 * 1000L
                Triple(PrimaryState.STRICT_RUNNING, wallNowMs + durMs, emptyList())
            }
            SessionMode.CYCLES -> {
                val cycleTimeline = buildCyclesTimeline(wallNowMs, activeCfg)
                Triple(PrimaryState.CYCLES_RUNNING, cycleTimeline.totalEndMs, cycleTimeline.phases)
            }
        }

        snapshot = snapshot.copyWith(
            sessionId = sessionId,
            primaryState = primaryState,
            activePhase = phases.firstOrNull()?.phaseType ?: PhaseType.FOCUS_SESSION,
            config = activeCfg,
            wallStartEpochMs = wallNowMs,
            monoStartMs = monoNowMs,
            totalTargetEndEpochMs = totalEndMs,
            phases = phases,
            activePhaseIndex = 0,
            pauseEndEpochMs = null,
            lastMonotonicTickMs = monoNowMs
        )

        emitEvent(
            SessionEvent.SessionStarted(
                sessionId = sessionId,
                sequenceNumber = sequenceNumber++,
                timestampEpochMs = wallNowMs,
                monoTimestampMs = monoNowMs,
                idempotencyKey = idempotencyKey,
                mode = activeCfg.mode,
                totalTargetEndEpochMs = totalEndMs
            )
        )

        return Result.success(snapshot)
    }

    @Synchronized
    fun pauseSession(
        pauseMinutes: Int,
        wallNowMs: Long = System.currentTimeMillis(),
        monoNowMs: Long = SystemClock.elapsedRealtime(),
        idempotencyKey: String = "idem_pause_${wallNowMs}"
    ): Result<SessionSnapshot> {
        if (snapshot.primaryState == PrimaryState.STRICT_RUNNING || snapshot.primaryState == PrimaryState.CYCLES_RUNNING) {
            return Result.failure(SecurityException("ERR_PAUSE_NOT_ALLOWED"))
        }
        if (pauseMinutes != 5 && pauseMinutes != 15 && pauseMinutes != 30) {
            return Result.failure(IllegalArgumentException("ERR_INVALID_PAUSE_DURATION"))
        }

        val pauseEndMs = wallNowMs + (pauseMinutes * 60 * 1000L)
        snapshot = snapshot.copyWith(
            primaryState = PrimaryState.PAUSED,
            pauseEndEpochMs = pauseEndMs,
            lastMonotonicTickMs = monoNowMs
        )

        emitEvent(
            SessionEvent.SessionPaused(
                sessionId = snapshot.sessionId,
                sequenceNumber = sequenceNumber++,
                timestampEpochMs = wallNowMs,
                monoTimestampMs = monoNowMs,
                idempotencyKey = idempotencyKey,
                pauseMinutes = pauseMinutes,
                pauseEndEpochMs = pauseEndMs
            )
        )

        return Result.success(snapshot)
    }

    @Synchronized
    fun resumeSession(
        wallNowMs: Long = System.currentTimeMillis(),
        monoNowMs: Long = SystemClock.elapsedRealtime(),
        reason: String = "UserResumed",
        idempotencyKey: String = "idem_resume_${wallNowMs}"
    ): Result<SessionSnapshot> {
        if (snapshot.primaryState != PrimaryState.PAUSED) {
            return Result.success(snapshot)
        }

        val restoredState = if (snapshot.config.mode == SessionMode.FEED_ONLY) {
            PrimaryState.ACTIVE_FEED
        } else PrimaryState.ACTIVE_NORMAL

        snapshot = snapshot.copyWith(
            primaryState = restoredState,
            pauseEndEpochMs = null,
            lastMonotonicTickMs = monoNowMs
        )

        emitEvent(
            SessionEvent.SessionResumed(
                sessionId = snapshot.sessionId,
                sequenceNumber = sequenceNumber++,
                timestampEpochMs = wallNowMs,
                monoTimestampMs = monoNowMs,
                idempotencyKey = idempotencyKey,
                reason = reason
            )
        )

        return Result.success(snapshot)
    }

    @Synchronized
    fun stopSession(
        wallNowMs: Long = System.currentTimeMillis(),
        monoNowMs: Long = SystemClock.elapsedRealtime(),
        reason: String = "UserStopped",
        idempotencyKey: String = "idem_stop_${wallNowMs}"
    ): Result<SessionSnapshot> {
        if (snapshot.isStrictLockout) {
            return Result.failure(SecurityException("ERR_STRICT_LOCKOUT_ACTIVE"))
        }

        snapshot = snapshot.copyWith(
            primaryState = PrimaryState.COMPLETED,
            activePhase = PhaseType.IDLE,
            pauseEndEpochMs = null,
            lastMonotonicTickMs = monoNowMs
        )

        emitEvent(
            SessionEvent.SessionAborted(
                sessionId = snapshot.sessionId,
                sequenceNumber = sequenceNumber++,
                timestampEpochMs = wallNowMs,
                monoTimestampMs = monoNowMs,
                idempotencyKey = idempotencyKey,
                reason = reason
            )
        )

        return Result.success(snapshot)
    }

    /**
     * Option 3 Emergency Panic Override:
     * Allows immediate abort of an active strict lockout if the user confirms a continuous 15-second emergency hold.
     */
    @Synchronized
    fun requestEmergencyPanicUnlock(
        holdDurationMs: Long,
        wallNowMs: Long = System.currentTimeMillis(),
        monoNowMs: Long = SystemClock.elapsedRealtime(),
        idempotencyKey: String = "idem_panic_${wallNowMs}"
    ): Result<SessionSnapshot> {
        if (!snapshot.isStrictLockout) {
            return stopSession(wallNowMs, monoNowMs, "NormalStopNotLocked", idempotencyKey)
        }

        // Strictly enforce 15,000 ms (15 seconds) continuous physical hold
        if (holdDurationMs < 15_000L) {
            return Result.failure(
                SecurityException("ERR_PANIC_HOLD_TOO_SHORT: Must hold continuously for at least 15 seconds to abort strict focus")
            )
        }

        snapshot = snapshot.copyWith(
            primaryState = PrimaryState.COMPLETED,
            activePhase = PhaseType.IDLE,
            pauseEndEpochMs = null,
            lastMonotonicTickMs = monoNowMs
        )

        emitEvent(
            SessionEvent.SessionAborted(
                sessionId = snapshot.sessionId,
                sequenceNumber = sequenceNumber++,
                timestampEpochMs = wallNowMs,
                monoTimestampMs = monoNowMs,
                idempotencyKey = idempotencyKey,
                reason = "EmergencyPanicOverride_15sHoldConfirmed"
            )
        )

        return Result.success(snapshot)
    }

    /**
     * Option 5 Reboot Recovery & Time Reconciliation:
     * Reconciles monotonic clock resets upon device reboot using verified atomic/network timestamp.
     */
    @Synchronized
    fun reconcileAfterReboot(
        persistedSnapshot: SessionSnapshot,
        verifiedWallNowMs: Long,
        currentMonoNowMs: Long = SystemClock.elapsedRealtime()
    ): Result<SessionSnapshot> {
        if (persistedSnapshot.primaryState == PrimaryState.INACTIVE || persistedSnapshot.primaryState == PrimaryState.COMPLETED) {
            snapshot = persistedSnapshot
            return Result.success(snapshot)
        }

        // Check if target end epoch expired while device was powered off
        if (verifiedWallNowMs >= persistedSnapshot.totalTargetEndEpochMs) {
            snapshot = persistedSnapshot.copyWith(
                primaryState = PrimaryState.COMPLETED,
                activePhase = PhaseType.COMPLETED,
                monoStartMs = 0L,
                lastMonotonicTickMs = currentMonoNowMs
            )
            return Result.success(snapshot)
        }

        // Session is still active. Re-anchor monotonic start to current boot uptime.
        val remainingMs = persistedSnapshot.totalTargetEndEpochMs - verifiedWallNowMs
        val reanchoredWallStart = verifiedWallNowMs
        val reanchoredTargetEnd = verifiedWallNowMs + remainingMs

        snapshot = persistedSnapshot.copyWith(
            wallStartEpochMs = reanchoredWallStart,
            monoStartMs = currentMonoNowMs,
            totalTargetEndEpochMs = reanchoredTargetEnd,
            lastMonotonicTickMs = currentMonoNowMs
        )

        return Result.success(snapshot)
    }

    @Synchronized
    fun setVpnDegraded(isDegraded: Boolean) {
        snapshot = snapshot.copyWith(isVpnDegraded = isDegraded)
    }

    @Synchronized
    fun evaluateCatchUp(
        wallNowMs: Long = System.currentTimeMillis(),
        monoNowMs: Long = SystemClock.elapsedRealtime()
    ): List<SessionEvent> {
        val events = mutableListOf<SessionEvent>()
        val elapsedMono = monoNowMs - snapshot.monoStartMs
        val effectiveNow = snapshot.wallStartEpochMs + elapsedMono

        // Clock Tamper Detection
        if (wallNowMs < snapshot.wallStartEpochMs) {
            val evt = SessionEvent.TamperDetected(
                sessionId = snapshot.sessionId,
                sequenceNumber = sequenceNumber++,
                timestampEpochMs = wallNowMs,
                monoTimestampMs = monoNowMs,
                idempotencyKey = "tamper_back_${wallNowMs}",
                alertType = "BACKWARD_TIME_JUMP_DETECTED",
                details = "Wall clock shifted back by ${snapshot.wallStartEpochMs - wallNowMs}ms"
            )
            events.add(evt)
            emitEvent(evt)
        } else if ((wallNowMs - effectiveNow) > 15000L) {
            val evt = SessionEvent.TamperDetected(
                sessionId = snapshot.sessionId,
                sequenceNumber = sequenceNumber++,
                timestampEpochMs = wallNowMs,
                monoTimestampMs = monoNowMs,
                idempotencyKey = "tamper_jump_${wallNowMs}",
                alertType = "CLOCK_MANIPULATION_DETECTED",
                details = "Wall clock jumped forward artificially by ${wallNowMs - effectiveNow}ms"
            )
            events.add(evt)
            emitEvent(evt)
        }

        // Auto-resume paused session if expired
        if (snapshot.primaryState == PrimaryState.PAUSED && snapshot.pauseEndEpochMs != null) {
            if (wallNowMs >= snapshot.pauseEndEpochMs!!) {
                resumeSession(wallNowMs, monoNowMs, reason = "PauseTimerExpired")
            }
        }

        // Strict mode completion evaluation
        if (snapshot.primaryState == PrimaryState.STRICT_RUNNING) {
            if (effectiveNow >= snapshot.totalTargetEndEpochMs) {
                snapshot = snapshot.copyWith(
                    primaryState = PrimaryState.COMPLETED,
                    activePhase = PhaseType.COMPLETED,
                    lastMonotonicTickMs = monoNowMs
                )
                val evt = SessionEvent.SessionCompleted(
                    sessionId = snapshot.sessionId,
                    sequenceNumber = sequenceNumber++,
                    timestampEpochMs = wallNowMs,
                    monoTimestampMs = monoNowMs,
                    idempotencyKey = "idem_complete_${snapshot.sessionId}",
                    totalFocusSeconds = elapsedMono / 1000L,
                    totalInterventionKills = snapshot.totalInterventionKills
                )
                events.add(evt)
                emitEvent(evt)
            }
            return events
        }

        // Cycles mode phase advance evaluation
        if (snapshot.primaryState == PrimaryState.CYCLES_RUNNING) {
            if (effectiveNow >= snapshot.totalTargetEndEpochMs) {
                snapshot = snapshot.copyWith(
                    primaryState = PrimaryState.COMPLETED,
                    activePhase = PhaseType.COMPLETED,
                    lastMonotonicTickMs = monoNowMs
                )
                val evt = SessionEvent.SessionCompleted(
                    sessionId = snapshot.sessionId,
                    sequenceNumber = sequenceNumber++,
                    timestampEpochMs = wallNowMs,
                    monoTimestampMs = monoNowMs,
                    idempotencyKey = "idem_complete_${snapshot.sessionId}",
                    totalFocusSeconds = elapsedMono / 1000L,
                    totalInterventionKills = snapshot.totalInterventionKills
                )
                events.add(evt)
                emitEvent(evt)
                return events
            }

            for (p in snapshot.phases) {
                if (effectiveNow >= p.startEpochMs && effectiveNow < p.endEpochMs) {
                    if (snapshot.activePhaseIndex != p.phaseIndex) {
                        val oldPhase = snapshot.activePhase
                        val newPhase = p.phaseType

                        snapshot = snapshot.copyWith(
                            activePhase = newPhase,
                            activePhaseIndex = p.phaseIndex,
                            lastMonotonicTickMs = monoNowMs
                        )

                        val phaseEvt = SessionEvent.PhaseAdvanced(
                            sessionId = snapshot.sessionId,
                            sequenceNumber = sequenceNumber++,
                            timestampEpochMs = wallNowMs,
                            monoTimestampMs = monoNowMs,
                            idempotencyKey = "idem_phase_${p.phaseIndex}_${snapshot.sessionId}",
                            oldPhase = oldPhase,
                            newPhase = newPhase,
                            cycleNumber = p.cycleNumber
                        )
                        events.add(phaseEvt)
                        emitEvent(phaseEvt)

                        if (oldPhase == PhaseType.BREAK_EXPIRING_GRACE && newPhase == PhaseType.FOCUS_SESSION) {
                            val killEvt = SessionEvent.AppTerminationSweepTriggered(
                                sessionId = snapshot.sessionId,
                                sequenceNumber = sequenceNumber++,
                                timestampEpochMs = wallNowMs,
                                monoTimestampMs = monoNowMs,
                                idempotencyKey = "idem_sweep_${p.phaseIndex}_${snapshot.sessionId}",
                                cycleNumber = p.cycleNumber
                            )
                            events.add(killEvt)
                            emitEvent(killEvt)
                        }
                    }
                    break
                }
            }
        }

        return events
    }

    /**
     * Pure policy evaluation function. Deterministically decides if target is blocked.
     */
    fun isBlocked(
        target: EvaluationTarget,
        wallNowMs: Long = System.currentTimeMillis(),
        monoNowMs: Long = SystemClock.elapsedRealtime()
    ): SessionDecision {
        evaluateCatchUp(wallNowMs, monoNowMs)

        val st = snapshot.primaryState
        if (st == PrimaryState.INACTIVE || st == PrimaryState.COMPLETED) {
            return SessionDecision(
                isBlocked = false,
                reason = "Session inactive",
                enforcedBy = EnforcerType.NONE
            )
        }
        if (st == PrimaryState.PAUSED) {
            return SessionDecision(
                isBlocked = false,
                reason = "Session is paused",
                enforcedBy = EnforcerType.NONE
            )
        }

        val subfeature = target.subfeature
        val category = target.category
        val pkg = target.packageName
        val domain = target.domain

        // Clean domain bypass in normal/unrestricted state
        val cleanDomains = setOf("wikipedia.org", "google.com", "apple.com", "github.com")
        if (domain != null && cleanDomains.contains(domain) && pkg == null && category == null) {
            return SessionDecision(
                isBlocked = false,
                reason = "Allowed clean domain",
                enforcedBy = EnforcerType.NONE
            )
        }

        // Category checks (e.g. Adult, Gambling, Piracy)
        if (category in listOf("porn", "gambling", "piracy")) {
            val catName = when (category) {
                "porn" -> "Adult & Pornography"
                "gambling" -> "Gambling"
                else -> "Piracy"
            }
            return SessionDecision(
                isBlocked = true,
                reason = "Blocked category: $catName",
                enforcedBy = EnforcerType.DNS
            )
        }

        // Feed-Only mode surgical decisions
        if (st == PrimaryState.ACTIVE_FEED) {
            if (subfeature in listOf("reelsOrShorts", "feed", "explore")) {
                return SessionDecision(
                    isBlocked = true,
                    reason = "Feed-Only restriction: $subfeature",
                    enforcedBy = EnforcerType.FEED_INSPECTOR
                )
            } else if (subfeature in listOf("watch", "messages", "search")) {
                val subReason = if (subfeature == "watch") {
                    "Educational watch subfeature permitted in Feed-Only mode"
                } else "Direct messaging permitted in Feed-Only mode"

                return SessionDecision(
                    isBlocked = false,
                    reason = subReason,
                    enforcedBy = EnforcerType.NONE
                )
            }
        }

        // Cycles Break allowance
        if (st == PrimaryState.CYCLES_RUNNING && snapshot.activePhase == PhaseType.BREAK_SESSION) {
            return SessionDecision(
                isBlocked = false,
                reason = "Micro-Break allowance active",
                enforcedBy = EnforcerType.NONE
            )
        }

        // Strict / Cycles Focus / Normal Block active
        val reason = when {
            st == PrimaryState.STRICT_RUNNING -> "Strict Lockout active (monotonic anchor enforced)"
            st == PrimaryState.CYCLES_RUNNING -> "Cycle Focus Session active"
            snapshot.isVpnDegraded -> "App blocked in session (degraded DNS fallback to shield)"
            else -> "App or domain blocked in active session"
        }

        val enforcer = if (snapshot.isVpnDegraded || !pkg.isNullOrEmpty()) {
            EnforcerType.SHIELD
        } else EnforcerType.DNS

        return SessionDecision(
            isBlocked = true,
            reason = reason,
            enforcedBy = enforcer,
            allowFallback = snapshot.isVpnDegraded
        )
    }

    private fun buildCyclesTimeline(
        startMs: Long,
        cfg: SessionConfig
    ): CycleTimelineResult {
        val fMs = cfg.focusMinutes * 60 * 1000L
        val bMs = cfg.breakMinutes * 60 * 1000L
        val cycles = cfg.totalCycles
        val prepGraceMs = 10 * 1000L
        val breakGraceMs = 30 * 1000L

        val phases = mutableListOf<PhaseInterval>()
        var curr = startMs
        var idx = 0

        // Initial Prep Grace
        phases.add(PhaseInterval(idx++, PhaseType.PREPARATION_GRACE, 1, curr, curr + prepGraceMs))
        curr += prepGraceMs

        for (c in 1..cycles) {
            // Focus
            phases.add(PhaseInterval(idx++, PhaseType.FOCUS_SESSION, c, curr, curr + fMs))
            curr += fMs

            // Break
            val mainBreakMs = (bMs - breakGraceMs).coerceAtLeast(0L)
            phases.add(PhaseInterval(idx++, PhaseType.BREAK_SESSION, c, curr, curr + mainBreakMs))
            curr += mainBreakMs

            // Break Grace
            phases.add(PhaseInterval(idx++, PhaseType.BREAK_EXPIRING_GRACE, c, curr, curr + breakGraceMs))
            curr += breakGraceMs
        }

        phases.add(PhaseInterval(idx++, PhaseType.COMPLETED, cycles, curr, curr))
        return CycleTimelineResult(curr, phases)
    }

    private data class CycleTimelineResult(val totalEndMs: Long, val phases: List<PhaseInterval>)

    private fun createInitialSnapshot(config: SessionConfig): SessionSnapshot {
        return SessionSnapshot(
            sessionId = "ses_init",
            primaryState = PrimaryState.INACTIVE,
            activePhase = PhaseType.IDLE,
            config = config,
            wallStartEpochMs = 0L,
            monoStartMs = 0L,
            totalTargetEndEpochMs = 0L,
            phases = emptyList(),
            activePhaseIndex = 0,
            isVpnDegraded = false
        )
    }

    private fun SessionSnapshot.copyWith(
        sessionId: String = this.sessionId,
        primaryState: PrimaryState = this.primaryState,
        activePhase: PhaseType = this.activePhase,
        config: SessionConfig = this.config,
        wallStartEpochMs: Long = this.wallStartEpochMs,
        monoStartMs: Long = this.monoStartMs,
        totalTargetEndEpochMs: Long = this.totalTargetEndEpochMs,
        phases: List<PhaseInterval> = this.phases,
        activePhaseIndex: Int = this.activePhaseIndex,
        isVpnDegraded: Boolean = this.isVpnDegraded,
        pauseEndEpochMs: Long? = this.pauseEndEpochMs,
        lastMonotonicTickMs: Long = this.lastMonotonicTickMs,
        totalInterventionKills: Int = this.totalInterventionKills
    ): SessionSnapshot {
        return SessionSnapshot(
            sessionId = sessionId,
            primaryState = primaryState,
            activePhase = activePhase,
            config = config,
            wallStartEpochMs = wallStartEpochMs,
            monoStartMs = monoStartMs,
            totalTargetEndEpochMs = totalTargetEndEpochMs,
            phases = phases,
            activePhaseIndex = activePhaseIndex,
            isVpnDegraded = isVpnDegraded,
            pauseEndEpochMs = pauseEndEpochMs,
            lastMonotonicTickMs = lastMonotonicTickMs,
            totalInterventionKills = totalInterventionKills
        )
    }
}
