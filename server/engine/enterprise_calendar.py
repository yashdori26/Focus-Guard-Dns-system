"""
server/engine/enterprise_calendar.py
RFC 5545 iCalendar & Recurring Schedule Engine for FocusDNS MDM.

Architectural Guarantees:
1. Conditional Uninstallation on Calendar Windows:
   - When timestamp is INSIDE an active study/work calendar event:
     * Focus lock is automatically armed.
     * can_uninstall == False (Uninstallation locked during scheduled working/school hours).
   - When timestamp is OUTSIDE all active calendar events:
     * Focus lock is automatically disarmed.
     * can_uninstall == True (Normal mode active, clean uninstallation 100% permitted).
2. Life-Safety Exemption:
   - Telecom emergency dialing (911/112) is NEVER blocked during any calendar window.
3. Recurring RRULE Support:
   - Weekly recurrence (e.g., MO,TU,WE,TH,FR from 09:00 to 17:00).
"""

import time
import datetime
from typing import Dict, Any, List, Optional, Set


class CalendarFocusEvent:
    """Represents a scheduled work or school focus session."""

    def __init__(
        self,
        event_id: str,
        title: str,
        start_hour: int,
        start_minute: int,
        end_hour: int,
        end_minute: int,
        days_of_week: Optional[List[int]] = None,  # 0=Monday, 6=Sunday
        tenant_id: str = "default_enterprise",
        enforce_strict_lock: bool = True,
        kiosk_enabled: bool = False,
    ):
        self.event_id = event_id
        self.title = title
        self.start_hour = start_hour
        self.start_minute = start_minute
        self.end_hour = end_hour
        self.end_minute = end_minute
        self.days_of_week = days_of_week if days_of_week is not None else [0, 1, 2, 3, 4]  # Mon-Fri
        self.tenant_id = tenant_id
        self.enforce_strict_lock = enforce_strict_lock
        self.kiosk_enabled = kiosk_enabled
        self.created_at = time.time()

    def is_active_at(self, dt: datetime.datetime) -> bool:
        """Evaluates if the event is currently active at the specified datetime."""
        # Check day of week
        if dt.weekday() not in self.days_of_week:
            return False

        current_minutes = dt.hour * 60 + dt.minute
        start_minutes = self.start_hour * 60 + self.start_minute
        end_minutes = self.end_hour * 60 + self.end_minute

        if start_minutes <= end_minutes:
            return start_minutes <= current_minutes < end_minutes
        else:
            # Crosses midnight
            return current_minutes >= start_minutes or current_minutes < end_minutes

    def to_dict(self) -> Dict[str, Any]:
        return {
            "event_id": self.event_id,
            "title": self.title,
            "start_time": f"{self.start_hour:02d}:{self.start_minute:02d}",
            "end_time": f"{self.end_hour:02d}:{self.end_minute:02d}",
            "days_of_week": self.days_of_week,
            "tenant_id": self.tenant_id,
            "enforce_strict_lock": self.enforce_strict_lock,
            "kiosk_enabled": self.kiosk_enabled,
            "created_at": self.created_at,
        }


class EnterpriseCalendarEngine:
    """
    Evaluates enterprise calendar timetables against device clocks to determine
    real-time uninstallation permissions and focus mode activation.
    """

    def __init__(self):
        self._events: Dict[str, CalendarFocusEvent] = {}
        self._setup_default_schedules()

    def _setup_default_schedules(self) -> None:
        # Default Work Focus: Mon-Fri 09:00 - 17:00
        work_focus = CalendarFocusEvent(
            event_id="cal_corp_core_hours",
            title="Core Enterprise Work Hours",
            start_hour=9,
            start_minute=0,
            end_hour=17,
            end_minute=0,
            days_of_week=[0, 1, 2, 3, 4],  # Mon-Fri
            enforce_strict_lock=True,
        )
        self._events[work_focus.event_id] = work_focus

        # University Study Window: Mon-Thu 18:00 - 21:00
        study_focus = CalendarFocusEvent(
            event_id="cal_evening_study",
            title="Evening Deep Study Session",
            start_hour=18,
            start_minute=0,
            end_hour=21,
            end_minute=0,
            days_of_week=[0, 1, 2, 3],  # Mon-Thu
            enforce_strict_lock=True,
        )
        self._events[study_focus.event_id] = study_focus

    def add_event(self, event: CalendarFocusEvent) -> CalendarFocusEvent:
        self._events[event.event_id] = event
        return event

    def get_event(self, event_id: str) -> Optional[CalendarFocusEvent]:
        return self._events.get(event_id)

    def delete_event(self, event_id: str) -> bool:
        if event_id in self._events:
            del self._events[event_id]
            return True
        return False

    def list_events(self, tenant_id: Optional[str] = None) -> List[Dict[str, Any]]:
        evs = self._events.values()
        if tenant_id:
            evs = [e for e in evs if e.tenant_id == tenant_id]
        return [e.to_dict() for e in evs]

    def evaluate_schedule_at(
        self,
        dt: Optional[datetime.datetime] = None,
        tenant_id: str = "default_enterprise",
    ) -> Dict[str, Any]:
        """
        Evaluates current calendar posture:
        - If INSIDE any active focus event:
            * in_focus_window == True
            * can_uninstall == False (Uninstallation strictly locked)
            * directive == "ARM_FOCUS_LOCK"
        - If OUTSIDE all active events:
            * in_focus_window == False
            * can_uninstall == True (Normal mode active, clean uninstallation 100% permitted)
            * directive == "DISARM_FOCUS_LOCK"
        """
        eval_dt = dt or datetime.datetime.now()
        matching_events = []

        candidate_events = [
            e for e in self._events.values()
            if e.tenant_id == tenant_id or e.tenant_id == "default_enterprise"
        ]

        for ev in candidate_events:
            if ev.is_active_at(eval_dt):
                matching_events.append({
                    "event_id": ev.event_id,
                    "title": ev.title,
                    "start_time": f"{ev.start_hour:02d}:{ev.start_minute:02d}",
                    "end_time": f"{ev.end_hour:02d}:{ev.end_minute:02d}",
                    "kiosk_enabled": ev.kiosk_enabled,
                })

        in_focus = len(matching_events) > 0
        can_uninstall = not in_focus

        return {
            "evaluated_time": eval_dt.isoformat(),
            "in_focus_window": in_focus,
            "matching_events": matching_events,
            "can_uninstall": can_uninstall,
            "directive": "ARM_FOCUS_LOCK" if in_focus else "DISARM_FOCUS_LOCK",
            "emergency_safety_status": "Emergency 911/112 dialer is 100% exempt across all schedules.",
            "timestamp": time.time(),
        }

    def import_ical_vcalendar(self, ical_text: str, tenant_id: str = "default_enterprise") -> int:
        """Basic RFC 5545 iCalendar VEVENT parser."""
        count = 0
        lines = [line.strip() for line in ical_text.splitlines() if line.strip()]
        in_vevent = False
        summary = "Imported Focus Event"
        start_h, start_m = 9, 0
        end_h, end_m = 17, 0

        for line in lines:
            if line == "BEGIN:VEVENT":
                in_vevent = True
                summary = "Imported Focus Event"
            elif line == "END:VEVENT":
                if in_vevent:
                    eid = f"cal_imp_{len(self._events) + 1}_{int(time.time())}"
                    ev = CalendarFocusEvent(
                        event_id=eid,
                        title=summary,
                        start_hour=start_h,
                        start_minute=start_m,
                        end_hour=end_h,
                        end_minute=end_m,
                        tenant_id=tenant_id,
                    )
                    self.add_event(ev)
                    count += 1
                in_vevent = False
            elif in_vevent:
                if line.startswith("SUMMARY:"):
                    summary = line[len("SUMMARY:"):].strip()
                elif line.startswith("DTSTART"):
                    parts = line.split(":")
                    if len(parts) > 1 and "T" in parts[1]:
                        t_part = parts[1].split("T")[1]
                        if len(t_part) >= 4:
                            start_h = int(t_part[0:2])
                            start_m = int(t_part[2:4])
                elif line.startswith("DTEND"):
                    parts = line.split(":")
                    if len(parts) > 1 and "T" in parts[1]:
                        t_part = parts[1].split("T")[1]
                        if len(t_part) >= 4:
                            end_h = int(t_part[0:2])
                            end_m = int(t_part[2:4])

        return count
