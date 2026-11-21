import XCTest
@testable import FocusDnsEngine

final class SessionStateMachineTests: XCTestCase {
    
    // Mock monotonic clock for deterministic time manipulation
    final class MockClock: MonotonicClockProvider, @unchecked Sendable {
        var currentMs: Int64
        init(initialMs: Int64 = 100_000) {
            self.currentMs = initialMs
        }
        func uptimeMilliseconds() -> Int64 {
            return currentMs
        }
    }
    
    func testNormalLifecycle() {
        let clock = MockClock(initialMs: 50_000)
        let engine = SessionStateMachineEngine(monotonicClock: clock)
        let wallStart: Int64 = 1_700_000_000_000
        
        let config = SessionConfig(mode: .normal)
        let startRes = engine.startSession(config: config, wallNowMs: wallStart, monoNowMs: 50_000)
        XCTAssertTrue(try! startRes.get().primaryState == .activeNormal)
        
        let target = EvaluationTarget(domain: "instagram.com")
        let dec = engine.isBlocked(target: target, wallNowMs: wallStart + 1000, monoNowMs: 51_000)
        XCTAssertTrue(dec.isBlocked)
        
        // Clean domain should not be blocked
        let cleanTarget = EvaluationTarget(domain: "wikipedia.org")
        let cleanDec = engine.isBlocked(target: cleanTarget, wallNowMs: wallStart + 2000, monoNowMs: 52_000)
        XCTAssertFalse(cleanDec.isBlocked)
        
        // Pause session (allowed in normal mode)
        let pauseRes = engine.pauseSession(pauseMinutes: 15, wallNowMs: wallStart + 3000, monoNowMs: 53_000)
        XCTAssertTrue(try! pauseRes.get().primaryState == .paused)
        
        // While paused, block is lifted
        let pausedDec = engine.isBlocked(target: target, wallNowMs: wallStart + 4000, monoNowMs: 54_000)
        XCTAssertFalse(pausedDec.isBlocked)
        
        // Resume session
        let resRes = engine.resumeSession(wallNowMs: wallStart + 5000, monoNowMs: 55_000)
        XCTAssertTrue(try! resRes.get().primaryState == .activeNormal)
        
        // Stop session
        let stopRes = engine.stopSession(wallNowMs: wallStart + 6000, monoNowMs: 56_000)
        XCTAssertTrue(try! stopRes.get().primaryState == .completed)
    }
    
    func testStrictModeIroncladLockoutRejection() {
        let clock = MockClock(initialMs: 10_000)
        let engine = SessionStateMachineEngine(monotonicClock: clock)
        let wallStart: Int64 = 1_700_000_000_000
        
        let config = SessionConfig(mode: .strict, strictMinutes: 25)
        let startRes = engine.startSession(config: config, wallNowMs: wallStart, monoNowMs: 10_000)
        XCTAssertTrue(try! startRes.get().primaryState == .strictRunning)
        XCTAssertTrue(engine.currentSnapshot.isStrictLockout)
        
        // Option B: Attempt to pause MUST fail with ERR_PAUSE_NOT_ALLOWED
        let pauseRes = engine.pauseSession(pauseMinutes: 5, wallNowMs: wallStart + 1000, monoNowMs: 11_000)
        switch pauseRes {
        case .success:
            XCTFail("Option B Ironclad Lockout violation: pause was permitted during strict session!")
        case .failure(let error):
            XCTAssertTrue(error.localizedDescription.contains("ERR_PAUSE_NOT_ALLOWED"))
        }
        
        // Option B: Attempt to stop MUST fail with ERR_STRICT_LOCKOUT_ACTIVE
        let stopRes = engine.stopSession(wallNowMs: wallStart + 2000, monoNowMs: 12_000)
        switch stopRes {
        case .success:
            XCTFail("Option B Ironclad Lockout violation: stop was permitted during strict session!")
        case .failure(let error):
            XCTAssertTrue(error.localizedDescription.contains("ERR_STRICT_LOCKOUT_ACTIVE"))
        }
        
        // Monotonic Catch-up completion: advance clock past 25 minutes (1,500,000 ms)
        clock.currentMs = 10_000 + 1_501_000
        let events = engine.evaluateCatchUp(wallNowMs: wallStart + 1_501_000, monoNowMs: clock.currentMs)
        XCTAssertTrue(engine.currentSnapshot.primaryState == .completed)
        XCTAssertFalse(events.isEmpty)
    }
    
    func testCyclesTimelineAndCatchUp() {
        let clock = MockClock(initialMs: 20_000)
        let engine = SessionStateMachineEngine(monotonicClock: clock)
        let wallStart: Int64 = 1_700_000_000_000
        
        // 25m focus, 5m break, 2 cycles
        let config = SessionConfig(mode: .cycles, focusMinutes: 25, breakMinutes: 5, totalCycles: 2)
        let startRes = engine.startSession(config: config, wallNowMs: wallStart, monoNowMs: 20_000)
        XCTAssertTrue(try! startRes.get().primaryState == .cyclesRunning)
        
        // Initial phase is preparation grace (10s)
        XCTAssertEqual(engine.currentSnapshot.activePhase, .preparationGrace)
        
        // Advance clock into Focus Session 1 (e.g. + 15 seconds)
        clock.currentMs = 20_000 + 15_000
        engine.evaluateCatchUp(wallNowMs: wallStart + 15_000, monoNowMs: clock.currentMs)
        XCTAssertEqual(engine.currentSnapshot.activePhase, .focusSession)
        
        let target = EvaluationTarget(domain: "youtube.com")
        let focusDec = engine.isBlocked(target: target, wallNowMs: wallStart + 15_000, monoNowMs: clock.currentMs)
        XCTAssertTrue(focusDec.isBlocked)
        
        // Advance clock into Break Session 1 (Prep 10s + Focus 25m = 1510s) -> jump to 1520s
        let breakTimeOffset: Int64 = (10 + 25 * 60 + 10) * 1000
        clock.currentMs = 20_000 + breakTimeOffset
        engine.evaluateCatchUp(wallNowMs: wallStart + breakTimeOffset, monoNowMs: clock.currentMs)
        XCTAssertEqual(engine.currentSnapshot.activePhase, .breakSession)
        
        // During break, entertainment target is allowed!
        let breakDec = engine.isBlocked(target: target, wallNowMs: wallStart + breakTimeOffset, monoNowMs: clock.currentMs)
        XCTAssertFalse(breakDec.isBlocked)
    }
    
    func testFeedOnlySubfeatureMatrix() {
        let clock = MockClock(initialMs: 0)
        let engine = SessionStateMachineEngine(monotonicClock: clock)
        let wallStart: Int64 = 1_700_000_000_000
        
        let config = SessionConfig(mode: .feedOnly)
        _ = engine.startSession(config: config, wallNowMs: wallStart, monoNowMs: 0)
        
        // Reels/Shorts: BLOCKED
        let reelsTarget = EvaluationTarget(domain: "instagram.com", subfeature: "reelsOrShorts")
        let reelsDec = engine.isBlocked(target: reelsTarget, wallNowMs: wallStart + 1000, monoNowMs: 1000)
        XCTAssertTrue(reelsDec.isBlocked)
        XCTAssertEqual(reelsDec.enforcedBy, .feedInspector)
        
        // Infinite Feed: BLOCKED
        let feedTarget = EvaluationTarget(domain: "instagram.com", subfeature: "feed")
        let feedDec = engine.isBlocked(target: feedTarget, wallNowMs: wallStart + 2000, monoNowMs: 2000)
        XCTAssertTrue(feedDec.isBlocked)
        
        // Direct Messaging: ALLOWED
        let msgTarget = EvaluationTarget(domain: "instagram.com", subfeature: "messages")
        let msgDec = engine.isBlocked(target: msgTarget, wallNowMs: wallStart + 3000, monoNowMs: 3000)
        XCTAssertFalse(msgDec.isBlocked)
        
        // Educational Watch: ALLOWED
        let watchTarget = EvaluationTarget(domain: "youtube.com", subfeature: "watch")
        let watchDec = engine.isBlocked(target: watchTarget, wallNowMs: wallStart + 4000, monoNowMs: 4000)
        XCTAssertFalse(watchDec.isBlocked)
    }
    
    func testAntiTamperClockManipulation() {
        let clock = MockClock(initialMs: 100_000)
        let engine = SessionStateMachineEngine(monotonicClock: clock)
        let wallStart: Int64 = 1_700_000_000_000
        
        let config = SessionConfig(mode: .strict, strictMinutes: 25)
        _ = engine.startSession(config: config, wallNowMs: wallStart, monoNowMs: 100_000)
        
        // Simulate user rolling back the wall clock by 10 minutes while monotonic elapsed is only 5s
        let rollbackWall: Int64 = wallStart - 600_000
        let monoNow: Int64 = 100_000 + 5_000
        
        let events = engine.evaluateCatchUp(wallNowMs: rollbackWall, monoNowMs: monoNow)
        let tamperEvent = events.first { event in
            if case .tamperDetected(_, _, _, _, _, _, let alert, _) = event {
                return alert == "BACKWARD_TIME_JUMP_DETECTED"
            }
            return false
        }
        XCTAssertNotNil(tamperEvent)
    }
    
    func testBoundaryLimits() {
        let configStrictBad = SessionConfig(mode: .strict, strictMinutes: 2)
        let validation1 = configStrictBad.validate()
        XCTAssertFalse(validation1.isValid)
        XCTAssertEqual(validation1.error, "ERR_OUT_OF_BOUNDS")
        
        let configCyclesBad = SessionConfig(mode: .cycles, focusMinutes: 600)
        let validation2 = configCyclesBad.validate()
        XCTAssertFalse(validation2.isValid)
        XCTAssertEqual(validation2.error, "ERR_OUT_OF_BOUNDS")
    }
}
