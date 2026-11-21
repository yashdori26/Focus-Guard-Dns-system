package com.focusdns.engine

import com.focusdns.engine.session.EnforcerType
import com.focusdns.engine.session.EvaluationTarget
import com.focusdns.engine.session.PhaseType
import com.focusdns.engine.session.PrimaryState
import com.focusdns.engine.session.SessionConfig
import com.focusdns.engine.session.SessionMode
import com.focusdns.engine.session.SessionStateMachineEngine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class SessionStateMachineTest {

    private lateinit var engine: SessionStateMachineEngine

    @Before
    fun setUp() {
        engine = SessionStateMachineEngine()
    }

    @Test
    fun testNormalLifecycle() {
        val wallStart = 1732104000000L
        val monoStart = 1000000L

        // 1. Create and Start
        val startRes = engine.startSession(
            SessionConfig(mode = SessionMode.NORMAL),
            wallStart,
            monoStart
        )
        assertTrue(startRes.isSuccess)
        assertEquals(PrimaryState.ACTIVE_NORMAL, engine.currentSnapshot.primaryState)

        // 2. Pause 15m
        val pauseRes = engine.pauseSession(15, wallStart + 600000L, monoStart + 600000L)
        assertTrue(pauseRes.isSuccess)
        assertEquals(PrimaryState.PAUSED, engine.currentSnapshot.primaryState)

        // Decision during pause is unblocked
        val dec1 = engine.isBlocked(
            EvaluationTarget(packageName = "com.instagram.android"),
            wallStart + 700000L,
            monoStart + 700000L
        )
        assertFalse(dec1.isBlocked)

        // 3. Resume
        val resRes = engine.resumeSession(wallStart + 800000L, monoStart + 800000L)
        assertTrue(resRes.isSuccess)
        assertEquals(PrimaryState.ACTIVE_NORMAL, engine.currentSnapshot.primaryState)

        // 4. Stop
        val stopRes = engine.stopSession(wallStart + 900000L, monoStart + 900000L)
        assertTrue(stopRes.isSuccess)
        assertEquals(PrimaryState.COMPLETED, engine.currentSnapshot.primaryState)
    }

    @Test
    fun testFeedOnlySubfeatureMatrix() {
        val wallStart = 1732104000000L
        val monoStart = 1000000L

        engine.startSession(
            SessionConfig(mode = SessionMode.FEED_ONLY),
            wallStart,
            monoStart
        )
        assertEquals(PrimaryState.ACTIVE_FEED, engine.currentSnapshot.primaryState)

        // YouTube Shorts -> BLOCKED
        val shortsDec = engine.isBlocked(
            EvaluationTarget(packageName = "com.google.android.youtube", domain = "youtube.com", subfeature = "reelsOrShorts"),
            wallStart + 1000L,
            monoStart + 1000L
        )
        assertTrue(shortsDec.isBlocked)
        assertEquals(EnforcerType.FEED_INSPECTOR, shortsDec.enforcedBy)

        // YouTube Watch video -> ALLOWED
        val watchDec = engine.isBlocked(
            EvaluationTarget(packageName = "com.google.android.youtube", domain = "youtube.com", subfeature = "watch"),
            wallStart + 2000L,
            monoStart + 2000L
        )
        assertFalse(watchDec.isBlocked)

        // Instagram Direct Messages -> ALLOWED
        val dmDec = engine.isBlocked(
            EvaluationTarget(packageName = "com.instagram.android", domain = "instagram.com", subfeature = "messages"),
            wallStart + 3000L,
            monoStart + 3000L
        )
        assertFalse(dmDec.isBlocked)

        // Instagram Reels -> BLOCKED
        val reelsDec = engine.isBlocked(
            EvaluationTarget(packageName = "com.instagram.android", domain = "instagram.com", subfeature = "reelsOrShorts"),
            wallStart + 4000L,
            monoStart + 4000L
        )
        assertTrue(reelsDec.isBlocked)
        assertEquals(EnforcerType.FEED_INSPECTOR, reelsDec.enforcedBy)
    }

    @Test
    fun testStrictModeIroncladLockoutRejection() {
        val wallStart = 1732104000000L
        val monoStart = 1000000L

        engine.startSession(
            SessionConfig(mode = SessionMode.STRICT, strictMinutes = 60),
            wallStart,
            monoStart
        )
        assertEquals(PrimaryState.STRICT_RUNNING, engine.currentSnapshot.primaryState)

        // Attempt pause -> Must fail
        val pauseRes = engine.pauseSession(15, wallStart + 600000L, monoStart + 600000L)
        assertTrue(pauseRes.isFailure)
        assertEquals(PrimaryState.STRICT_RUNNING, engine.currentSnapshot.primaryState)

        // Attempt stop -> Must fail
        val stopRes = engine.stopSession(wallStart + 1200000L, monoStart + 1200000L)
        assertTrue(stopRes.isFailure)
        assertEquals(PrimaryState.STRICT_RUNNING, engine.currentSnapshot.primaryState)

        // Advance to full 60m expiry
        engine.evaluateCatchUp(wallStart + 3601000L, monoStart + 3601000L)
        assertEquals(PrimaryState.COMPLETED, engine.currentSnapshot.primaryState)
    }

    @Test
    fun testCyclesTimelineAndCatchUp() {
        val wallStart = 1732104000000L
        val monoStart = 1000000L

        engine.startSession(
            SessionConfig(
                mode = SessionMode.CYCLES,
                focusMinutes = 25,
                breakMinutes = 5,
                totalCycles = 2
            ),
            wallStart,
            monoStart
        )
        assertEquals(PrimaryState.CYCLES_RUNNING, engine.currentSnapshot.primaryState)
        assertEquals(8, engine.currentSnapshot.phases.size)
        assertEquals(PhaseType.PREPARATION_GRACE, engine.currentSnapshot.activePhase)

        // Advance past prep grace into focus
        engine.evaluateCatchUp(wallStart + 15000L, monoStart + 15000L)
        assertEquals(PhaseType.FOCUS_SESSION, engine.currentSnapshot.activePhase)

        // Verify focus session blocks app
        val focusDec = engine.isBlocked(
            EvaluationTarget(packageName = "com.instagram.android"),
            wallStart + 20000L,
            monoStart + 20000L
        )
        assertTrue(focusDec.isBlocked)

        // Advance into break session (26m in)
        engine.evaluateCatchUp(wallStart + (26 * 60 * 1000L), monoStart + (26 * 60 * 1000L))
        assertEquals(PhaseType.BREAK_SESSION, engine.currentSnapshot.activePhase)

        // Verify break allows app
        val breakDec = engine.isBlocked(
            EvaluationTarget(packageName = "com.instagram.android"),
            wallStart + (26 * 60 * 1000L),
            monoStart + (26 * 60 * 1000L)
        )
        assertFalse(breakDec.isBlocked)
    }

    @Test
    fun testAntiTamperClockManipulation() {
        val wallStart = 1732104000000L
        val monoStart = 1000000L

        engine.startSession(
            SessionConfig(mode = SessionMode.STRICT, strictMinutes = 60),
            wallStart,
            monoStart
        )

        // User sets clock forward 2 hours, but monotonic clock only advanced 1 minute
        val fakeWall = wallStart + (2 * 3600 * 1000L)
        val realMono = monoStart + 60000L

        val events = engine.evaluateCatchUp(fakeWall, realMono)
        assertTrue(events.any { it is com.focusdns.engine.session.SessionEvent.TamperDetected })
        // Lockout must NOT complete early!
        assertEquals(PrimaryState.STRICT_RUNNING, engine.currentSnapshot.primaryState)
    }

    @Test
    fun testBoundaryLimits() {
        // Strict < 5 min
        val res1 = engine.createSession(SessionConfig(mode = SessionMode.STRICT, strictMinutes = 4))
        assertTrue(res1.isFailure)

        // Strict > 480 min
        val res2 = engine.createSession(SessionConfig(mode = SessionMode.STRICT, strictMinutes = 481))
        assertTrue(res2.isFailure)

        // Break < 5 min
        val res3 = engine.createSession(SessionConfig(mode = SessionMode.CYCLES, breakMinutes = 4))
        assertTrue(res3.isFailure)

        // Break > 30 min
        val res4 = engine.createSession(SessionConfig(mode = SessionMode.CYCLES, breakMinutes = 31))
        assertTrue(res4.isFailure)
    }

    @Test
    fun testEmergencyPanicOverride15Seconds() {
        val wallStart = 1732104000000L
        val monoStart = 1000000L

        engine.startSession(
            SessionConfig(mode = SessionMode.STRICT, strictMinutes = 60),
            wallStart,
            monoStart
        )
        assertTrue(engine.currentSnapshot.isStrictLockout)

        // 1. Normal stop must fail
        val stopRes = engine.stopSession(wallStart + 10000L, monoStart + 10000L)
        assertTrue(stopRes.isFailure)
        assertEquals(PrimaryState.STRICT_RUNNING, engine.currentSnapshot.primaryState)

        // 2. Emergency panic with hold < 15s must fail
        val shortPanicRes = engine.requestEmergencyPanicUnlock(
            holdDurationMs = 14999L,
            wallNowMs = wallStart + 20000L,
            monoNowMs = monoStart + 20000L
        )
        assertTrue(shortPanicRes.isFailure)
        assertEquals(PrimaryState.STRICT_RUNNING, engine.currentSnapshot.primaryState)

        // 3. Emergency panic with hold >= 15s must succeed
        val fullPanicRes = engine.requestEmergencyPanicUnlock(
            holdDurationMs = 15000L,
            wallNowMs = wallStart + 35000L,
            monoNowMs = monoStart + 35000L
        )
        assertTrue(fullPanicRes.isSuccess)
        assertEquals(PrimaryState.COMPLETED, engine.currentSnapshot.primaryState)
        assertFalse(engine.currentSnapshot.isStrictLockout)
    }

    @Test
    fun testRebootRecoveryReconciliation() {
        val wallStart = 1732104000000L
        val monoStart = 5000000L
        val strictMinutes = 30

        engine.startSession(
            SessionConfig(mode = SessionMode.STRICT, strictMinutes = strictMinutes),
            wallStart,
            monoStart
        )
        val initialSnap = engine.currentSnapshot

        // Simulate phone rebooting 10 minutes later:
        // Monotonic clock resets to 15,000ms after boot!
        val rebootMono = 15000L
        val verifiedWallTime1 = wallStart + (10 * 60 * 1000L)

        val reconcileRes = engine.reconcileAfterReboot(initialSnap, verifiedWallTime1, rebootMono)
        assertTrue(reconcileRes.isSuccess)
        val restoredSnap = engine.currentSnapshot
        assertEquals(PrimaryState.STRICT_RUNNING, restoredSnap.primaryState)
        assertEquals(rebootMono, restoredSnap.monoStartMs)
        // 20 minutes remaining from verified wall time
        assertEquals(verifiedWallTime1 + (20 * 60 * 1000L), restoredSnap.totalTargetEndEpochMs)

        // Simulate phone rebooting when target end has ALREADY expired (e.g. 40 minutes later):
        val verifiedWallTime2 = wallStart + (40 * 60 * 1000L)
        val expiredReconcileRes = engine.reconcileAfterReboot(initialSnap, verifiedWallTime2, rebootMono)
        assertTrue(expiredReconcileRes.isSuccess)
        assertEquals(PrimaryState.COMPLETED, engine.currentSnapshot.primaryState)
    }
}

