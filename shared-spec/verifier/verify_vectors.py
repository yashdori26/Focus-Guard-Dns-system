#!/usr/bin/env python3
"""
FocusDNS Test Vector Verification Engine
Validates that the reference state machine, monotonic clock anchor,
and isBlocked policy evaluator conform 100% to shared-spec/vectors/state_machine_vectors.json.
"""

import sys
import json
import math
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Dict, Any, Optional

@dataclass
class PhaseInterval:
    phase_index: int
    phase_type: str
    cycle_number: int
    start_epoch_ms: int
    end_epoch_ms: int

@dataclass
class SessionState:
    session_id: str = "ses_default"
    primary_state: str = "INACTIVE"
    active_phase: str = "IDLE"
    config: Dict[str, Any] = field(default_factory=dict)
    wall_start_epoch_ms: int = 0
    mono_start_ms: int = 0
    total_target_end_epoch_ms: int = 0
    phases: List[PhaseInterval] = field(default_factory=list)
    active_phase_index: int = 0
    is_vpn_degraded: bool = False
    pause_end_epoch_ms: Optional[int] = None
    last_monotonic_tick_ms: int = 0
    total_intervention_kills: int = 0
    tamper_alerts: List[str] = field(default_factory=list)
    applied_event_keys: set = field(default_factory=set)

class SessionEngine:
    def __init__(self):
        self.state = SessionState()

    def validate_config(self, cfg: Dict[str, Any]) -> tuple[bool, Optional[str]]:
        mode = cfg.get("mode")
        if mode == "STRICT":
            strict_min = cfg.get("strictMinutes", 0)
            if strict_min < 5 or strict_min > 480:
                return False, "ERR_OUT_OF_BOUNDS"
        elif mode == "CYCLES":
            f_min = cfg.get("focusMinutes", 0)
            b_min = cfg.get("breakMinutes", 0)
            c_cnt = cfg.get("totalCycles", 0)
            if f_min < 5 or f_min > 480 or b_min < 5 or b_min > 30 or c_cnt < 1 or c_cnt > 12:
                return False, "ERR_OUT_OF_BOUNDS"
        elif mode in ("NORMAL", "FEED_ONLY"):
            pause_min = cfg.get("pauseMinutes")
            if pause_min is not None and pause_min not in (5, 15, 30):
                return False, "ERR_INVALID_PAUSE_DURATION"
        return True, None

    def create_session(self, cfg: Dict[str, Any], wall_time_ms: int, mono_time_ms: int):
        valid, err = self.validate_config(cfg)
        if not valid:
            raise ValueError(err)
        self.state = SessionState(
            session_id=f"ses_{wall_time_ms}",
            primary_state="INACTIVE",
            active_phase="IDLE",
            config=cfg,
            wall_start_epoch_ms=wall_time_ms,
            mono_start_ms=mono_time_ms,
            last_monotonic_tick_ms=mono_time_ms
        )

    def start_session(self, cfg: Optional[Dict[str, Any]], wall_time_ms: int, mono_time_ms: int):
        if cfg:
            self.create_session(cfg, wall_time_ms, mono_time_ms)

        mode = self.state.config.get("mode", "NORMAL")
        self.state.wall_start_epoch_ms = wall_time_ms
        self.state.mono_start_ms = mono_time_ms
        self.state.last_monotonic_tick_ms = mono_time_ms

        if mode == "NORMAL":
            self.state.primary_state = "ACTIVE_NORMAL"
            self.state.active_phase = "FOCUS_SESSION"
            self.state.total_target_end_epoch_ms = wall_time_ms + 86400000
        elif mode == "FEED_ONLY":
            self.state.primary_state = "ACTIVE_FEED"
            self.state.active_phase = "FOCUS_SESSION"
            self.state.total_target_end_epoch_ms = wall_time_ms + 86400000
        elif mode == "STRICT":
            self.state.primary_state = "STRICT_RUNNING"
            self.state.active_phase = "FOCUS_SESSION"
            duration_ms = self.state.config.get("strictMinutes", 25) * 60 * 1000
            self.state.total_target_end_epoch_ms = wall_time_ms + duration_ms
        elif mode == "CYCLES":
            self.state.primary_state = "CYCLES_RUNNING"
            self._build_cycles_timeline(wall_time_ms)

    def _build_cycles_timeline(self, start_ms: int):
        f_ms = self.state.config.get("focusMinutes", 25) * 60 * 1000
        b_ms = self.state.config.get("breakMinutes", 5) * 60 * 1000
        cycles = self.state.config.get("totalCycles", 2)
        prep_grace_ms = 10 * 1000
        break_grace_ms = 30 * 1000

        phases: List[PhaseInterval] = []
        curr = start_ms
        idx = 0

        # Initial preparation grace
        phases.append(PhaseInterval(idx, "PREPARATION_GRACE", 1, curr, curr + prep_grace_ms))
        curr += prep_grace_ms
        idx += 1

        for c in range(1, cycles + 1):
            # Focus Session
            phases.append(PhaseInterval(idx, "FOCUS_SESSION", c, curr, curr + f_ms))
            curr += f_ms
            idx += 1

            # Break Session (less break grace)
            main_break_ms = max(0, b_ms - break_grace_ms)
            phases.append(PhaseInterval(idx, "BREAK_SESSION", c, curr, curr + main_break_ms))
            curr += main_break_ms
            idx += 1

            # Break Expiring Grace
            phases.append(PhaseInterval(idx, "BREAK_EXPIRING_GRACE", c, curr, curr + break_grace_ms))
            curr += break_grace_ms
            idx += 1

        phases.append(PhaseInterval(idx, "COMPLETED", cycles, curr, curr))
        idx += 1

        self.state.phases = phases
        self.state.active_phase_index = 0
        self.state.active_phase = phases[0].phase_type
        self.state.total_target_end_epoch_ms = curr

    def pause_session(self, pause_minutes: int, wall_time_ms: int, mono_time_ms: int):
        if self.state.primary_state in ("STRICT_RUNNING", "CYCLES_RUNNING"):
            raise PermissionError("ERR_PAUSE_NOT_ALLOWED")
        if pause_minutes not in (5, 15, 30):
            raise ValueError("ERR_INVALID_PAUSE_DURATION")

        self.state.primary_state = "PAUSED"
        self.state.pause_end_epoch_ms = wall_time_ms + (pause_minutes * 60 * 1000)

    def resume_session(self, wall_time_ms: int, mono_time_ms: int):
        if self.state.primary_state != "PAUSED":
            return
        mode = self.state.config.get("mode", "NORMAL")
        self.state.primary_state = "ACTIVE_FEED" if mode == "FEED_ONLY" else "ACTIVE_NORMAL"
        self.state.pause_end_epoch_ms = None

    def stop_session(self, wall_time_ms: int, mono_time_ms: int):
        if self.state.primary_state in ("STRICT_RUNNING", "CYCLES_RUNNING"):
            raise PermissionError("ERR_STRICT_LOCKOUT_ACTIVE")
        self.state.primary_state = "COMPLETED"
        self.state.active_phase = "IDLE"

    def advance_time_catchup(self, wall_time_ms: int, mono_time_ms: int):
        # Monotonic anchor drift evaluation
        elapsed_mono = mono_time_ms - self.state.mono_start_ms
        effective_now = self.state.wall_start_epoch_ms + elapsed_mono

        # Check for user clock tampering
        if wall_time_ms < self.state.wall_start_epoch_ms:
            self.state.tamper_alerts.append("BACKWARD_TIME_JUMP_DETECTED")
        elif (wall_time_ms - effective_now) > 15000:
            self.state.tamper_alerts.append("CLOCK_MANIPULATION_DETECTED")

        # Auto-resume pause if expired
        if self.state.primary_state == "PAUSED" and self.state.pause_end_epoch_ms:
            if wall_time_ms >= self.state.pause_end_epoch_ms:
                self.resume_session(wall_time_ms, mono_time_ms)

        if self.state.primary_state == "STRICT_RUNNING":
            if effective_now >= self.state.total_target_end_epoch_ms:
                self.state.primary_state = "COMPLETED"
                self.state.active_phase = "COMPLETED"
            return

        if self.state.primary_state == "CYCLES_RUNNING":
            if effective_now >= self.state.total_target_end_epoch_ms:
                self.state.primary_state = "COMPLETED"
                self.state.active_phase = "COMPLETED"
                return

            for p in self.state.phases:
                if effective_now >= p.start_epoch_ms and effective_now < p.end_epoch_ms:
                    if self.state.active_phase_index != p.phase_index:
                        self.state.active_phase_index = p.phase_index
                        self.state.active_phase = p.phase_type
                    break

    def is_blocked(self, target: Dict[str, Any], now_wall_ms: int, now_mono_ms: int) -> Dict[str, Any]:
        # Always run catch-up evaluation prior to policy decision
        self.advance_time_catchup(now_wall_ms, now_mono_ms)

        st = self.state.primary_state
        if st in ("INACTIVE", "COMPLETED", "PAUSED"):
            return {
                "isBlocked": False,
                "reason": "Session is paused" if st == "PAUSED" else "Session inactive",
                "enforcedBy": "NONE",
                "allowFallback": False
            }

        subfeature = target.get("subfeature")
        category = target.get("category")
        pkg = target.get("packageName", "")
        domain = target.get("domain", "")

        # Category checks
        if category in ("porn", "gambling", "piracy"):
            cat_name = "Adult & Pornography" if category == "porn" else ("Gambling" if category == "gambling" else "Piracy")
            return {
                "isBlocked": True,
                "reason": f"Blocked category: {cat_name}",
                "enforcedBy": "DNS",
                "allowFallback": False
            }

        if st == "ACTIVE_FEED":
            if subfeature in ("reelsOrShorts", "feed", "explore"):
                return {
                    "isBlocked": True,
                    "reason": f"Feed-Only restriction: {subfeature}",
                    "enforcedBy": "FEED_INSPECTOR",
                    "allowFallback": False
                }
            elif subfeature in ("watch", "messages", "search"):
                sub_reason = "Educational watch subfeature permitted in Feed-Only mode" if subfeature == "watch" else "Direct messaging permitted in Feed-Only mode"
                return {
                    "isBlocked": False,
                    "reason": sub_reason,
                    "enforcedBy": "NONE",
                    "allowFallback": False
                }

        if st == "CYCLES_RUNNING":
            if self.state.active_phase == "BREAK_SESSION":
                return {
                    "isBlocked": False,
                    "reason": "Micro-Break allowance active",
                    "enforcedBy": "NONE",
                    "allowFallback": False
                }

        clean_domains = {"wikipedia.org", "google.com", "apple.com", "github.com"}
        if domain in clean_domains and not pkg and not category:
            return {
                "isBlocked": False,
                "reason": "Allowed clean domain",
                "enforcedBy": "NONE",
                "allowFallback": False
            }

        # Strict or Focus or Normal mode
        reason = "Strict Lockout active (monotonic anchor enforced)" if st == "STRICT_RUNNING" else (
            "Cycle Focus Session active" if st == "CYCLES_RUNNING" else (
                "App blocked in session (degraded DNS fallback to shield)" if self.state.is_vpn_degraded else "App or domain blocked in active session"
            )
        )
        enforced_by = "SHIELD" if (self.state.is_vpn_degraded or pkg) else "DNS"
        return {
            "isBlocked": True,
            "reason": reason,
            "enforcedBy": enforced_by,
            "allowFallback": self.state.is_vpn_degraded
        }

    def apply_event(self, event: Dict[str, Any]):
        idem = event.get("idempotencyKey")
        if idem in self.state.applied_event_keys:
            # Idempotent replay: ignore duplicate
            return
        self.state.applied_event_keys.add(idem)

        etype = event.get("eventType")
        payload = event.get("payload", {})
        wall_ms = event.get("timestampEpochMs", 0)
        mono_ms = event.get("monoTimestampMs", 0)

        if etype == "SessionStarted":
            self.start_session(payload, wall_ms, mono_ms)
        elif etype == "SessionPaused":
            self.pause_session(payload.get("pauseMinutes", 15), wall_ms, mono_ms)
        elif etype == "SessionResumed":
            self.resume_session(wall_ms, mono_ms)
        elif etype == "SessionAborted":
            self.stop_session(wall_ms, mono_ms)


def run_vector_suite(vector_file: Path):
    with open(vector_file, "r") as f:
        suite = json.load(f)

    vectors = suite["vectors"]
    print(f"\n=======================================================")
    print(f" FocusDNS Shared Specification Test Vector Verification")
    print(f" Suite: {suite['suite']} (v{suite['version']})")
    print(f" Total Vectors to Validate: {len(vectors)}")
    print(f"=======================================================\n")

    total_steps = 0
    passed_vectors = 0

    for v in vectors:
        v_id = v["id"]
        desc = v["description"]
        print(f"Running [{v_id}]: {desc} ...", end=" ")

        engine = SessionEngine()
        vector_passed = True

        for s in v["steps"]:
            total_steps += 1
            action = s["action"]
            wall_ms = s.get("wallTimeMs", 0)
            mono_ms = s.get("monoTimeMs", 0)
            inp = s.get("input", {})

            try:
                if action == "VALIDATE_CONFIG":
                    valid, err = engine.validate_config(inp)
                    expected_valid = s.get("expectedValid")
                    assert valid == expected_valid, f"Step {s['step']}: Expected valid={expected_valid}, got {valid}"
                    if not valid and "expectedErrorCode" in s:
                        assert err == s["expectedErrorCode"], f"Step {s['step']}: Expected err={s['expectedErrorCode']}, got {err}"

                elif action == "CREATE_SESSION":
                    engine.create_session(inp, wall_ms, mono_ms)

                elif action == "START_SESSION":
                    engine.start_session(inp, wall_ms, mono_ms)

                elif action == "PAUSE_SESSION":
                    p_min = inp.get("pauseMinutes", 15)
                    try:
                        engine.pause_session(p_min, wall_ms, mono_ms)
                        assert "expectedError" not in s, f"Step {s['step']}: Expected error but succeeded"
                    except PermissionError as pe:
                        assert "expectedError" in s, f"Step {s['step']}: Unexpected error {pe}"
                        assert s["expectedError"]["code"] == str(pe)

                elif action == "RESUME_SESSION":
                    engine.resume_session(wall_ms, mono_ms)

                elif action == "STOP_SESSION":
                    try:
                        engine.stop_session(wall_ms, mono_ms)
                        assert "expectedError" not in s, f"Step {s['step']}: Expected error but succeeded"
                    except PermissionError as pe:
                        assert "expectedError" in s, f"Step {s['step']}: Unexpected error {pe}"
                        assert s["expectedError"]["code"] == str(pe)

                elif action == "ADVANCE_TIME_CATCHUP":
                    engine.advance_time_catchup(wall_ms, mono_ms)
                    if "expectedTamperAlert" in s:
                        assert s["expectedTamperAlert"] in engine.state.tamper_alerts, (
                            f"Step {s['step']}: Missing expected tamper alert {s['expectedTamperAlert']}"
                        )

                elif action == "NOTIFY_VPN_CONFLICT":
                    engine.state.is_vpn_degraded = True

                elif action == "APPLY_EVENT":
                    engine.apply_event(inp)

                elif action == "EVALUATE_IS_BLOCKED":
                    target = inp.get("target", {})
                    decision = engine.is_blocked(target, wall_ms, mono_ms)
                    expected = s.get("expectedDecision", {})
                    for k, expected_val in expected.items():
                        assert decision.get(k) == expected_val, (
                            f"Step {s['step']} Decision mismatch on '{k}': expected '{expected_val}', got '{decision.get(k)}'"
                        )

                # State assertions
                if "expectedState" in s:
                    exp = s["expectedState"]
                    if "primaryState" in exp:
                        assert engine.state.primary_state == exp["primaryState"], (
                            f"Step {s['step']}: expected primaryState={exp['primaryState']}, got {engine.state.primary_state}"
                        )
                    if "activePhase" in exp:
                        assert engine.state.active_phase == exp["activePhase"], (
                            f"Step {s['step']}: expected activePhase={exp['activePhase']}, got {engine.state.active_phase}"
                        )
                    if "activePhaseIndex" in exp:
                        assert engine.state.active_phase_index == exp["activePhaseIndex"], (
                            f"Step {s['step']}: expected activePhaseIndex={exp['activePhaseIndex']}, got {engine.state.active_phase_index}"
                        )
                    if "isVpnDegraded" in exp:
                        assert engine.state.is_vpn_degraded == exp["isVpnDegraded"], (
                            f"Step {s['step']}: expected isVpnDegraded={exp['isVpnDegraded']}, got {engine.state.is_vpn_degraded}"
                        )
                    if "totalTargetEndEpochMs" in exp:
                        assert engine.state.total_target_end_epoch_ms == exp["totalTargetEndEpochMs"], (
                            f"Step {s['step']}: expected endMs={exp['totalTargetEndEpochMs']}, got {engine.state.total_target_end_epoch_ms}"
                        )
                    if "phasesCount" in exp:
                        assert len(engine.state.phases) == exp["phasesCount"], (
                            f"Step {s['step']}: expected phases={exp['phasesCount']}, got {len(engine.state.phases)}"
                        )

            except Exception as e:
                print(f"FAILED!\n  -> Failure at step {s.get('step', '?')}: {e}")
                vector_passed = False
                break

        if vector_passed:
            print("[PASS]")
            passed_vectors += 1

    print(f"\n=======================================================")
    print(f" Verification Result: {passed_vectors}/{len(vectors)} Vectors Passed ({total_steps} total steps validated).")
    print(f"=======================================================\n")

    if passed_vectors == len(vectors):
        return 0
    return 1

if __name__ == "__main__":
    vector_path = Path(__file__).parent.parent / "vectors" / "state_machine_vectors.json"
    sys.exit(run_vector_suite(vector_path))
