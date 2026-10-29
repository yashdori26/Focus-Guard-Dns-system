"""
FocusDNS Enterprise Engine - Classroom & Fleet Session Orchestrator.

Dedicated commercial fleet control plane engineered for K-12 schools, universities,
and corporate training centers.

Key Capabilities:
  1. Dynamic Classroom Periods & Student Roster Presence Tracking.
  2. Multi-Mode Focus Policies:
     - NORMAL_PROTECTION: Standard school category filtering.
     - RESTRICTED_RESEARCH: Whitelisted research & educational resources only.
     - STRICT_EXAM_MODE: Total lockdown to designated testing FQDNs.
  3. Real-Time WebSocket Fleet Push: Instantaneous sub-50ms classroom lock triggers.
  4. Student Attention & Distraction Tracking: Detects off-task browsing attempts.
  5. Inviolable Conditional Whitelisting Law:
     Whitelisting domains during active exam mode strictly raises ERROR_ACCESS_DENIED (5).
  6. Inviolable Life-Safety Exemption Guarantee: Emergency domains can NEVER be blocked.
"""

import collections
import datetime
import json
import logging
import secrets
import threading
import time
from enum import Enum
from typing import Dict, List, Set, Optional, Tuple, Any

from server.enterprise.fleet_websocket_server import (
    FleetWebSocketServer,
    get_fleet_websocket_server,
)
from server.enterprise.tenant_manager import TenantManager, get_tenant_manager
from server.enterprise.rbac_engine import RbacEngine, RoleTier, get_rbac_engine

logger = logging.getLogger("FocusDNS.Enterprise.Classroom")

LIFE_SAFETY_DOMAINS: Set[str] = {
    "911.gov",
    "112.gov",
    "emergency.gov",
    "cops.usdoj.gov",
    "fema.gov",
    "update.microsoft.com",
    "windowsupdate.com",
    "push.apple.com",
    "identity.apple.com",
    "play.googleapis.com",
    "android.googleapis.com",
    "mtalk.google.com",
    "gcm-http.googleapis.com",
    "icloud.com",
    "crashlytics.com",
}


class ClassroomFocusMode(str, Enum):
    NORMAL_PROTECTION = "NORMAL_PROTECTION"
    RESTRICTED_RESEARCH = "RESTRICTED_RESEARCH"
    STRICT_EXAM_MODE = "STRICT_EXAM_MODE"


class StudentDeviceState:
    """Represents a student endpoint connected in an active classroom session."""
    __slots__ = (
        "device_id", "student_name", "student_id", "client_ip",
        "last_query_time", "last_queried_domain", "distraction_count",
        "is_locked", "hand_raised"
    )

    def __init__(
        self,
        device_id: str,
        student_name: str,
        student_id: str,
        client_ip: str = "127.0.0.1"
    ):
        self.device_id = device_id
        self.student_name = student_name
        self.student_id = student_id
        self.client_ip = client_ip
        self.last_query_time = 0.0
        self.last_queried_domain = ""
        self.distraction_count = 0
        self.is_locked = False
        self.hand_raised = False

    def to_dict(self) -> Dict[str, Any]:
        return {
            "device_id": self.device_id,
            "student_name": self.student_name,
            "student_id": self.student_id,
            "client_ip": self.client_ip,
            "last_query_time": self.last_query_time,
            "last_queried_domain": self.last_queried_domain,
            "distraction_count": self.distraction_count,
            "is_locked": self.is_locked,
            "hand_raised": self.hand_raised,
        }


class ClassroomSession:
    """Represents a timed instructional class period with synchronized fleet rules."""
    __slots__ = (
        "session_id", "org_id", "unit_id", "fleet_id", "classroom_name",
        "teacher_user_id", "mode", "duration_seconds", "started_at", "ends_at",
        "is_active", "allowed_exam_domains", "students", "distraction_alerts"
    )

    def __init__(
        self,
        session_id: str,
        org_id: str,
        unit_id: str,
        fleet_id: str,
        classroom_name: str,
        teacher_user_id: str,
        mode: ClassroomFocusMode = ClassroomFocusMode.NORMAL_PROTECTION,
        duration_seconds: int = 2700,  # Standard 45-minute class period
        allowed_exam_domains: Optional[Set[str]] = None,
    ):
        self.session_id = session_id
        self.org_id = org_id
        self.unit_id = unit_id
        self.fleet_id = fleet_id
        self.classroom_name = classroom_name
        self.teacher_user_id = teacher_user_id
        self.mode = mode
        self.duration_seconds = duration_seconds
        self.started_at = time.time()
        self.ends_at = self.started_at + duration_seconds
        self.is_active = True
        self.allowed_exam_domains = allowed_exam_domains or {
            "canvas.instructure.com",
            "blackboard.com",
            "quizlet.com",
            "exam.school.edu",
        }
        self.students: Dict[str, StudentDeviceState] = {}
        self.distraction_alerts: List[Dict[str, Any]] = []

    @property
    def remaining_seconds(self) -> int:
        if not self.is_active:
            return 0
        rem = int(self.ends_at - time.time())
        return max(0, rem)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "session_id": self.session_id,
            "org_id": self.org_id,
            "unit_id": self.unit_id,
            "fleet_id": self.fleet_id,
            "classroom_name": self.classroom_name,
            "teacher_user_id": self.teacher_user_id,
            "mode": self.mode.value,
            "duration_seconds": self.duration_seconds,
            "remaining_seconds": self.remaining_seconds,
            "is_active": self.is_active,
            "student_count": len(self.students),
            "students": [s.to_dict() for s in self.students.values()],
            "distraction_alert_count": len(self.distraction_alerts),
            "allowed_exam_domains": sorted(list(self.allowed_exam_domains)),
        }


class ClassroomOrchestrator:
    """
    Teacher and school administrator orchestration service coordinating
    synchronized fleet locks, exam modes, and attention monitoring.
    """

    def __init__(
        self,
        ws_hub: Optional[FleetWebSocketServer] = None,
        tenants: Optional[TenantManager] = None,
        rbac: Optional[RbacEngine] = None,
    ):
        self._lock = threading.RLock()
        self.ws_hub = ws_hub or get_fleet_websocket_server()
        self.tenants = tenants or get_tenant_manager()
        self.rbac = rbac or get_rbac_engine()

        # Active sessions: session_id -> ClassroomSession
        self._sessions: Dict[str, ClassroomSession] = {}
        # Fleet to session mapping: fleet_id -> session_id
        self._fleet_to_session: Dict[str, str] = {}

        # Watchdog loop for session timeouts
        self._running = True
        self._stop_event = threading.Event()
        self._timer_thread = threading.Thread(
            target=self._expiration_watchdog,
            name="ClassroomTimerWatchdog",
            daemon=True
        )
        self._timer_thread.start()

    def start_session(
        self,
        org_id: str,
        unit_id: str,
        fleet_id: str,
        classroom_name: str,
        teacher_user_id: str,
        mode: ClassroomFocusMode = ClassroomFocusMode.NORMAL_PROTECTION,
        duration_seconds: int = 2700,
        allowed_exam_domains: Optional[Set[str]] = None,
    ) -> ClassroomSession:
        """Starts an instructional classroom session and pushes fleet lock."""
        with self._lock:
            # End previous session on fleet if exists
            prev_session_id = self._fleet_to_session.get(fleet_id)
            if prev_session_id and prev_session_id in self._sessions:
                self.end_session(prev_session_id)

            session_id = f"cls_{secrets.token_hex(6)}"
            session = ClassroomSession(
                session_id=session_id,
                org_id=org_id,
                unit_id=unit_id,
                fleet_id=fleet_id,
                classroom_name=classroom_name,
                teacher_user_id=teacher_user_id,
                mode=mode,
                duration_seconds=duration_seconds,
                allowed_exam_domains=allowed_exam_domains,
            )

            self._sessions[session_id] = session
            self._fleet_to_session[fleet_id] = session_id

            # Broadcast lock to fleet over WebSocket
            if self.ws_hub:
                push_frame = {
                    "type": "LOCK_SESSION",
                    "duration_seconds": duration_seconds,
                    "reason": f"Classroom Focus: {classroom_name} ({mode.value})",
                    "mode": mode.value,
                    "allowed_exam_domains": sorted(list(session.allowed_exam_domains)),
                }
                self.ws_hub.broadcast_to_fleet(fleet_id, push_frame)

            logger.info(
                f"[CLASSROOM] Session '{classroom_name}' ({session_id}) started on fleet '{fleet_id}' "
                f"for {duration_seconds}s in mode {mode.value}."
            )
            return session

    def end_session(self, session_id: str) -> Optional[ClassroomSession]:
        """Concludes an active classroom session and unlocks student fleet."""
        with self._lock:
            session = self._sessions.get(session_id)
            if not session or not session.is_active:
                return session

            session.is_active = False
            self._fleet_to_session.pop(session.fleet_id, None)

            # Broadcast unlock to fleet over WebSocket
            if self.ws_hub:
                unlock_frame = {
                    "type": "UNLOCK_SESSION",
                    "reason": f"Classroom period {session.classroom_name} concluded.",
                }
                self.ws_hub.broadcast_to_fleet(session.fleet_id, unlock_frame)

            logger.info(f"[CLASSROOM] Session '{session.classroom_name}' ({session_id}) ended.")
            return session

    def set_focus_mode(self, session_id: str, new_mode: ClassroomFocusMode) -> bool:
        """Dynamically switches session focus mode and updates fleet policies."""
        with self._lock:
            session = self._sessions.get(session_id)
            if not session or not session.is_active:
                return False

            session.mode = new_mode

            # Broadcast updated policy frame
            if self.ws_hub:
                update_frame = {
                    "type": "POLICY_UPDATE",
                    "mode": new_mode.value,
                    "allowed_domains": sorted(list(session.allowed_exam_domains)),
                    "reason": f"Classroom mode changed to {new_mode.value}",
                }
                self.ws_hub.broadcast_to_fleet(session.fleet_id, update_frame)

            logger.info(f"[CLASSROOM] Session {session_id} switched to mode {new_mode.value}.")
            return True

    def register_student_device(
        self,
        session_id: str,
        device_id: str,
        student_name: str,
        student_id: str,
        client_ip: str = "127.0.0.1"
    ) -> bool:
        """Registers a student device in the classroom roster."""
        with self._lock:
            session = self._sessions.get(session_id)
            if not session:
                return False

            student = StudentDeviceState(
                device_id=device_id,
                student_name=student_name,
                student_id=student_id,
                client_ip=client_ip
            )
            session.students[device_id] = student
            return True

    def record_student_query(
        self,
        device_id: str,
        domain: str,
        action: str
    ) -> Tuple[bool, str]:
        """
        Records a query from a student device.
        Flags distraction if a blocked/prohibited domain was requested during class.
        Returns: Tuple[is_allowed, reason]
        """
        clean_domain = domain.lower().strip(".")

        # Inviolable Life-Safety Guarantee
        if clean_domain in LIFE_SAFETY_DOMAINS:
            return True, "LIFE_SAFETY_EXEMPTION"
        for safe in LIFE_SAFETY_DOMAINS:
            if clean_domain.endswith("." + safe):
                return True, "LIFE_SAFETY_EXEMPTION"

        with self._lock:
            # Find student session
            for session in self._sessions.values():
                if session.is_active and device_id in session.students:
                    student = session.students[device_id]
                    student.last_query_time = time.time()
                    student.last_queried_domain = clean_domain

                    # In STRICT_EXAM_MODE, only exam domains allowed
                    if session.mode == ClassroomFocusMode.STRICT_EXAM_MODE:
                        is_exam_allowed = clean_domain in session.allowed_exam_domains or any(
                            clean_domain.endswith("." + d) for d in session.allowed_exam_domains
                        )
                        if not is_exam_allowed:
                            student.distraction_count += 1
                            alert = {
                                "timestamp": time.time(),
                                "student_name": student.student_name,
                                "device_id": device_id,
                                "domain": clean_domain,
                                "violation": "EXAM_LOCKDOWN_BREACH_ATTEMPT",
                            }
                            session.distraction_alerts.append(alert)
                            return False, "EXAM_MODE_BLOCKED"
                        return True, "EXAM_WHITELIST_MATCH"

                    # If regular blocked query
                    if action in ("BLOCKED", "SINKHOLED"):
                        student.distraction_count += 1
                        alert = {
                            "timestamp": time.time(),
                            "student_name": student.student_name,
                            "device_id": device_id,
                            "domain": clean_domain,
                            "violation": "OFF_TASK_DISTRACTION",
                        }
                        session.distraction_alerts.append(alert)
                        return False, "DISTRACTION_BLOCKED"

                    return True, "ALLOWED"

            return True, "NO_ACTIVE_CLASSROOM_SESSION"

    # =========================================================================
    # Conditional Whitelisting Law Enforcement
    # =========================================================================

    def request_whitelist_domain(self, session_id: str, domain: str) -> bool:
        """
        Attempts to whitelist a domain during a classroom session.
        Strictly raises PermissionError: ERROR_ACCESS_DENIED (5) if session is in STRICT_EXAM_MODE.
        """
        clean_domain = domain.lower().strip(".")
        with self._lock:
            session = self._sessions.get(session_id)
            if not session or not session.is_active:
                return True

            if session.mode == ClassroomFocusMode.STRICT_EXAM_MODE or session.remaining_seconds > 0:
                raise PermissionError(
                    f"ERROR_ACCESS_DENIED (5): Cannot whitelist domain '{clean_domain}'. "
                    f"Classroom '{session.classroom_name}' is locked in {session.mode.value} "
                    f"with {session.remaining_seconds}s remaining."
                )

            session.allowed_exam_domains.add(clean_domain)
            return True

    def get_session(self, session_id: str) -> Optional[ClassroomSession]:
        with self._lock:
            return self._sessions.get(session_id)

    def list_active_sessions(self, org_id: Optional[str] = None) -> List[Dict[str, Any]]:
        with self._lock:
            active = [
                s.to_dict() for s in self._sessions.values()
                if s.is_active and (not org_id or s.org_id == org_id)
            ]
            return active

    def _expiration_watchdog(self) -> None:
        """Background loop unlocking sessions when period countdown expires."""
        while self._running:
            if self._stop_event.wait(1.0):
                break
            now = time.time()
            to_expire = []
            with self._lock:
                for session_id, session in self._sessions.items():
                    if session.is_active and now >= session.ends_at:
                        to_expire.append(session_id)

            for s_id in to_expire:
                self.end_session(s_id)

    def shutdown(self) -> None:
        self._running = False
        self._stop_event.set()
        if self._timer_thread.is_alive():
            self._timer_thread.join(timeout=0.5)


# Global Singleton
_global_classroom_orchestrator: Optional[ClassroomOrchestrator] = None
_classroom_lock = threading.Lock()


def get_classroom_orchestrator() -> ClassroomOrchestrator:
    global _global_classroom_orchestrator
    with _classroom_lock:
        if _global_classroom_orchestrator is None:
            _global_classroom_orchestrator = ClassroomOrchestrator()
        return _global_classroom_orchestrator
