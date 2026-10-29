"""
FocusDNS Enterprise Engine - Classroom & Fleet Orchestrator Unit Tests.

Tests:
  1. Classroom instructional periods & student presence roster management.
  2. Focus modes: NORMAL_PROTECTION, RESTRICTED_RESEARCH, and STRICT_EXAM_MODE.
  3. Student attention monitoring and real-time distraction alerts.
  4. Inviolable Conditional Whitelisting Law: Whitelist additions during active exam lock
     strictly raise PermissionError: ERROR_ACCESS_DENIED (5).
  5. Inviolable Life Safety Exemption: Emergency calling (911.gov, 112.gov, emergency.gov)
     and OS updates can NEVER be blocked by any classroom lock.
  6. Real-time WebSocket fleet lock and unlock push frame dispatch.
"""

import time
import unittest

from server.enterprise.classroom_orchestrator import (
    ClassroomOrchestrator,
    ClassroomFocusMode,
    ClassroomSession,
    LIFE_SAFETY_DOMAINS,
)
from server.enterprise.fleet_websocket_server import FleetWebSocketServer


class DummyWebSocketHub:
    """Mock WebSocket hub recording broadcast frames."""

    def __init__(self):
        self.dispatched_fleet_frames = []

    def broadcast_to_fleet(self, fleet_id: str, message: dict) -> int:
        self.dispatched_fleet_frames.append((fleet_id, message))
        return 1


class TestClassroomOrchestrator(unittest.TestCase):
    """Verifies teacher classroom orchestration, exam lockdown, and safety guarantees."""

    def setUp(self):
        self.ws_hub = DummyWebSocketHub()
        self.orchestrator = ClassroomOrchestrator(ws_hub=self.ws_hub)

    def tearDown(self):
        self.orchestrator.shutdown()

    def test_start_session_pushes_lock_frame(self):
        session = self.orchestrator.start_session(
            org_id="org_springfield",
            unit_id="unit_lincoln_high",
            fleet_id="flt_cart_4b",
            classroom_name="Period 2 Chemistry",
            teacher_user_id="teacher_skinner",
            mode=ClassroomFocusMode.NORMAL_PROTECTION,
            duration_seconds=1800,
        )
        self.assertIsNotNone(session)
        self.assertEqual(session.classroom_name, "Period 2 Chemistry")
        self.assertTrue(session.is_active)
        self.assertGreater(session.remaining_seconds, 1700)

        # Verify WebSocket broadcast
        self.assertEqual(len(self.ws_hub.dispatched_fleet_frames), 1)
        fleet_id, frame = self.ws_hub.dispatched_fleet_frames[0]
        self.assertEqual(fleet_id, "flt_cart_4b")
        self.assertEqual(frame["type"], "LOCK_SESSION")
        self.assertEqual(frame["mode"], "NORMAL_PROTECTION")

    def test_student_roster_registration_and_attention(self):
        session = self.orchestrator.start_session(
            org_id="org_springfield",
            unit_id="unit_lincoln_high",
            fleet_id="flt_cart_4b",
            classroom_name="Period 3 Biology",
            teacher_user_id="teacher_krabappel",
        )

        ok = self.orchestrator.register_student_device(
            session_id=session.session_id,
            device_id="chromebook_01",
            student_name="Bart Simpson",
            student_id="STU-001",
            client_ip="192.168.1.101"
        )
        self.assertTrue(ok)
        self.assertIn("chromebook_01", session.students)

        # Bart queries educational resource (ALLOWED)
        allowed, reason = self.orchestrator.record_student_query(
            device_id="chromebook_01",
            domain="biologycorner.com",
            action="ALLOWED"
        )
        self.assertTrue(allowed)
        self.assertEqual(reason, "ALLOWED")
        self.assertEqual(session.students["chromebook_01"].distraction_count, 0)

        # Bart queries gaming/distraction site (BLOCKED)
        allowed, reason = self.orchestrator.record_student_query(
            device_id="chromebook_01",
            domain="arcade-games-unblocked.io",
            action="BLOCKED"
        )
        self.assertFalse(allowed)
        self.assertEqual(reason, "DISTRACTION_BLOCKED")
        self.assertEqual(session.students["chromebook_01"].distraction_count, 1)
        self.assertEqual(len(session.distraction_alerts), 1)
        self.assertEqual(session.distraction_alerts[0]["violation"], "OFF_TASK_DISTRACTION")

    def test_strict_exam_mode_and_conditional_whitelisting_law(self):
        """
        Inviolable Conditional Whitelisting Law:
        Mutating whitelists while focus is locked strictly raises
        PermissionError: ERROR_ACCESS_DENIED (5).
        """
        session = self.orchestrator.start_session(
            org_id="org_springfield",
            unit_id="unit_lincoln_high",
            fleet_id="flt_cart_4b",
            classroom_name="AP Calculus Final Exam",
            teacher_user_id="teacher_skinner",
            mode=ClassroomFocusMode.STRICT_EXAM_MODE,
            duration_seconds=3600,
            allowed_exam_domains={"canvas.instructure.com", "apcentral.collegeboard.org"},
        )
        self.orchestrator.register_student_device(
            session_id=session.session_id,
            device_id="chromebook_05",
            student_name="Lisa Simpson",
            student_id="STU-002",
        )

        # 1. Allowed exam domain succeeds
        allowed, reason = self.orchestrator.record_student_query(
            device_id="chromebook_05",
            domain="apcentral.collegeboard.org",
            action="ALLOWED"
        )
        self.assertTrue(allowed)
        self.assertEqual(reason, "EXAM_WHITELIST_MATCH")

        # 2. Non-exam domain blocked during strict exam
        allowed, reason = self.orchestrator.record_student_query(
            device_id="chromebook_05",
            domain="reddit.com",
            action="ALLOWED"
        )
        self.assertFalse(allowed)
        self.assertEqual(reason, "EXAM_MODE_BLOCKED")

        # 3. Conditional Whitelisting Law: Whitelist mutation during active lock MUST raise ERROR_ACCESS_DENIED (5)
        with self.assertRaises(PermissionError) as ctx:
            self.orchestrator.request_whitelist_domain(session.session_id, "cheating-site.org")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

    def test_inviolable_life_safety_exemption_guarantee(self):
        """
        Inviolable Life Safety Exemption:
        Emergency domains (911.gov, 112.gov, emergency.gov) and critical update services
        can NEVER be blocked by any classroom lock, exam mode, or strict barrier.
        """
        session = self.orchestrator.start_session(
            org_id="org_springfield",
            unit_id="unit_lincoln_high",
            fleet_id="flt_cart_4b",
            classroom_name="Strict Exam",
            teacher_user_id="teacher_skinner",
            mode=ClassroomFocusMode.STRICT_EXAM_MODE,
            duration_seconds=3600,
            allowed_exam_domains={"canvas.instructure.com"},
        )
        self.orchestrator.register_student_device(
            session_id=session.session_id,
            device_id="chromebook_01",
            student_name="Student",
            student_id="STU-001",
        )

        # Emergency services must unconditionally resolve as allowed
        for emergency_fqdn in ["911.gov", "sub.emergency.gov", "112.gov", "update.microsoft.com", "push.apple.com"]:
            allowed, reason = self.orchestrator.record_student_query(
                device_id="chromebook_01",
                domain=emergency_fqdn,
                action="BLOCKED"  # Even if upstream flagged blocked
            )
            self.assertTrue(allowed, f"Life safety domain {emergency_fqdn} must be allowed!")
            self.assertEqual(reason, "LIFE_SAFETY_EXEMPTION")

    def test_end_session_unlocks_fleet(self):
        session = self.orchestrator.start_session(
            org_id="org_springfield",
            unit_id="unit_lincoln_high",
            fleet_id="flt_cart_4b",
            classroom_name="Period 5 History",
            teacher_user_id="teacher_hoover",
        )
        self.assertTrue(session.is_active)

        # Conclude session
        ended = self.orchestrator.end_session(session.session_id)
        self.assertFalse(ended.is_active)
        self.assertEqual(ended.remaining_seconds, 0)

        # Verify UNLOCK frame broadcast
        last_frame = self.ws_hub.dispatched_fleet_frames[-1][1]
        self.assertEqual(last_frame["type"], "UNLOCK_SESSION")


if __name__ == "__main__":
    unittest.main()
