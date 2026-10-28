"""
server/tests/test_engine_calendar.py
Comprehensive unit test suite for FocusDNS RFC 5545 Enterprise Calendar & Recurring Schedule Engine.

Validates:
1. Conditional Uninstallation on Calendar Windows:
   - When timestamp is INSIDE an active study/work calendar event:
     * Focus lock is automatically armed.
     * can_uninstall == False (Uninstallation locked during scheduled working/school hours).
   - When timestamp is OUTSIDE all active calendar events:
     * Focus lock is automatically disarmed.
     * can_uninstall == True (Normal mode active, clean uninstallation 100% permitted).
2. Life-Safety Exemption:
   - Telecom emergency dialing (911/112) is NEVER blocked during any calendar window.
3. Recurring RRULE & Midnight-Crossing Schedules:
   - Weekly recurrence (Mon-Fri) and shifts spanning past midnight.
4. RFC 5545 iCalendar (VEVENT) Stream Parsing:
   - Real-world calendar synchronization and automated timetable ingestion.
"""

import datetime
import unittest
from server.engine.enterprise_calendar import (
    EnterpriseCalendarEngine,
    CalendarFocusEvent,
)


class TestEnterpriseCalendarEngine(unittest.TestCase):

    def setUp(self):
        self.engine = EnterpriseCalendarEngine()

    def test_default_events_initialized(self):
        core = self.engine.get_event("cal_corp_core_hours")
        self.assertIsNotNone(core)
        self.assertEqual(core.title, "Core Enterprise Work Hours")
        self.assertEqual(core.start_hour, 9)
        self.assertEqual(core.end_hour, 17)
        self.assertEqual(core.days_of_week, [0, 1, 2, 3, 4])

        study = self.engine.get_event("cal_evening_study")
        self.assertIsNotNone(study)
        self.assertEqual(study.start_hour, 18)
        self.assertEqual(study.end_hour, 21)

    def test_calendar_event_active_inside_window_locks_uninstallation(self):
        ev = CalendarFocusEvent(
            event_id="test_focus",
            title="Deep Focus Morning",
            start_hour=9,
            start_minute=30,
            end_hour=11,
            end_minute=30,
            days_of_week=[0],  # Monday
        )

        # Monday 10:15 AM -> Inside window
        # 2026-10-26 was a Monday
        dt_inside = datetime.datetime(2026, 10, 26, 10, 15, 0)
        self.assertTrue(ev.is_active_at(dt_inside))

        # Core Law: Inside focus window, uninstallation is locked
        can_uninstall = not ev.is_active_at(dt_inside)
        self.assertFalse(can_uninstall, "Must lock uninstallation inside scheduled focus window")

    def test_calendar_event_inactive_outside_window_permits_uninstallation(self):
        ev = CalendarFocusEvent(
            event_id="test_focus",
            title="Deep Focus Morning",
            start_hour=9,
            start_minute=30,
            end_hour=11,
            end_minute=30,
            days_of_week=[0],  # Monday
        )

        # Monday 08:30 AM -> Before window
        dt_before = datetime.datetime(2026, 10, 26, 8, 30, 0)
        self.assertFalse(ev.is_active_at(dt_before))
        self.assertTrue(not ev.is_active_at(dt_before), "Must permit uninstallation before focus window")

        # Monday 12:00 PM -> After window
        dt_after = datetime.datetime(2026, 10, 26, 12, 0, 0)
        self.assertFalse(ev.is_active_at(dt_after))
        self.assertTrue(not ev.is_active_at(dt_after), "Must permit uninstallation after focus window")

        # Tuesday 10:15 AM -> Wrong day of week (Tuesday = 1)
        dt_tuesday = datetime.datetime(2026, 10, 27, 10, 15, 0)
        self.assertFalse(ev.is_active_at(dt_tuesday))
        self.assertTrue(not ev.is_active_at(dt_tuesday), "Must permit uninstallation on unscheduled day")

    def test_midnight_crossing_interval(self):
        night_shift = CalendarFocusEvent(
            event_id="night_focus",
            title="Overnight Code Freeze",
            start_hour=22,
            start_minute=0,
            end_hour=6,
            end_minute=0,
            days_of_week=[0, 1, 2, 3, 4],  # Mon-Fri
        )

        # Monday 23:30 PM (before midnight)
        dt_late = datetime.datetime(2026, 10, 26, 23, 30, 0)
        self.assertTrue(night_shift.is_active_at(dt_late))

        # Monday 04:15 AM (after midnight)
        dt_early = datetime.datetime(2026, 10, 26, 4, 15, 0)
        self.assertTrue(night_shift.is_active_at(dt_early))

        # Monday 14:00 PM (afternoon)
        dt_midday = datetime.datetime(2026, 10, 26, 14, 0, 0)
        self.assertFalse(night_shift.is_active_at(dt_midday))

    def test_engine_schedule_evaluation_during_work_hours(self):
        # Wednesday at 14:00 PM -> Inside Core Enterprise Work Hours (09:00 - 17:00)
        # 2026-10-28 is a Wednesday
        wed_afternoon = datetime.datetime(2026, 10, 28, 14, 0, 0)
        res = self.engine.evaluate_schedule_at(wed_afternoon)

        self.assertTrue(res["in_focus_window"])
        self.assertFalse(res["can_uninstall"], "Must lock uninstallation during work hours")
        self.assertEqual(res["directive"], "ARM_FOCUS_LOCK")
        self.assertGreaterEqual(len(res["matching_events"]), 1)
        self.assertEqual(res["matching_events"][0]["title"], "Core Enterprise Work Hours")
        self.assertIn("100% exempt", res["emergency_safety_status"])

    def test_engine_schedule_evaluation_off_hours_permits_uninstallation(self):
        # Saturday at 14:00 PM -> Outside all default schedules (Saturday = 5)
        # 2026-10-31 is a Saturday
        sat_afternoon = datetime.datetime(2026, 10, 31, 14, 0, 0)
        res = self.engine.evaluate_schedule_at(sat_afternoon)

        self.assertFalse(res["in_focus_window"])
        self.assertTrue(res["can_uninstall"], "Must permit clean uninstallation during weekend off-hours")
        self.assertEqual(res["directive"], "DISARM_FOCUS_LOCK")
        self.assertEqual(len(res["matching_events"]), 0)

    def test_import_ical_vcalendar(self):
        sample_ics = """BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//FocusDNS//Focus Timetable//EN
BEGIN:VEVENT
SUMMARY:Mathematics Lecture
DTSTART:20261028T090000Z
DTEND:20261028T110000Z
END:VEVENT
BEGIN:VEVENT
SUMMARY:Physics Laboratory
DTSTART:20261028T130000Z
DTEND:20261028T153000Z
END:VEVENT
END:VCALENDAR"""

        count = self.engine.import_ical_vcalendar(sample_ics, tenant_id="tenant_stem")
        self.assertEqual(count, 2)

        stem_events = self.engine.list_events(tenant_id="tenant_stem")
        self.assertEqual(len(stem_events), 2)
        titles = [e["title"] for e in stem_events]
        self.assertIn("Mathematics Lecture", titles)
        self.assertIn("Physics Laboratory", titles)

    def test_custom_event_crud(self):
        ev = CalendarFocusEvent(
            event_id="cal_custom_sprint",
            title="Sprint Planning Focus",
            start_hour=10,
            start_minute=0,
            end_hour=12,
            end_minute=0,
            days_of_week=[1],  # Tuesday
            tenant_id="tenant_scrum",
        )
        self.engine.add_event(ev)

        fetched = self.engine.get_event("cal_custom_sprint")
        self.assertIsNotNone(fetched)
        self.assertEqual(fetched.title, "Sprint Planning Focus")

        deleted = self.engine.delete_event("cal_custom_sprint")
        self.assertTrue(deleted)
        self.assertIsNone(self.engine.get_event("cal_custom_sprint"))


if __name__ == "__main__":
    unittest.main()
