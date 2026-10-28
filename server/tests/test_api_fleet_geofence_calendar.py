"""
server/tests/test_api_fleet_geofence_calendar.py
Integration test suite for FocusDNS MDM Phase 4 REST API Endpoints & CLI Commands.

Validates:
1. Fleet Control Plane Endpoints:
   - GET /api/v1/mdm/fleet/devices
   - GET /api/v1/mdm/fleet/telemetry
   - GET /api/v1/mdm/fleet/uninstall-check
   - GET /api/v1/mdm/fleet/commands
   - POST /api/v1/mdm/fleet/heartbeat
   - POST /api/v1/mdm/fleet/command
   - POST /api/v1/mdm/fleet/unlock-uninstall
2. Geofence Policy Endpoints:
   - GET /api/v1/mdm/geofence/zones
   - GET /api/v1/mdm/geofence/evaluate
   - POST /api/v1/mdm/geofence/zone
   - POST /api/v1/mdm/geofence/evaluate
3. Enterprise Calendar Endpoints:
   - GET /api/v1/mdm/calendar/events
   - GET /api/v1/mdm/calendar/status
   - POST /api/v1/mdm/calendar/event
   - POST /api/v1/mdm/calendar/parse-ical
4. Push Hub & CLI Subcommands:
   - POST /api/v1/mdm/push/dispatch
   - mdm-control, mdm-geofence, mdm-schedule CLI invocations
"""

import io
import json
import os
import sys
import threading
import time
import unittest
import urllib.request
import urllib.error
from http.server import ThreadingHTTPServer
from unittest.mock import patch

from server import db
from server.api_router import FocusDNSApiHandler
from server.engine.cli_engine import main as cli_main


class TestApiFleetGeofenceCalendar(unittest.TestCase):
    server: ThreadingHTTPServer = None
    server_thread: threading.Thread = None
    base_url: str = ""
    token: str = ""

    @classmethod
    def setUpClass(cls):
        db.init_db()
        cls.token = db.get_or_create_api_token()
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FocusDNSApiHandler)
        port = cls.server.server_address[1]
        cls.base_url = f"http://127.0.0.1:{port}"
        cls.server_thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()
        time.sleep(0.1)

    @classmethod
    def tearDownClass(cls):
        if cls.server:
            cls.server.shutdown()
            cls.server.server_close()

    def _request(self, method: str, path: str, data=None, auth: bool = True):
        headers = {"Content-Type": "application/json"}
        if auth and self.token:
            headers["X-Api-Key"] = self.token
        body = json.dumps(data).encode("utf-8") if data is not None else None
        req = urllib.request.Request(f"{self.base_url}{path}", data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req) as resp:
                status = resp.status
                payload = json.loads(resp.read().decode("utf-8"))
                return status, payload
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read().decode("utf-8"))

    # =========================================================================
    # 1. FLEET CONTROL PLANE REST API TESTS
    # =========================================================================

    def test_fleet_devices_and_telemetry_get(self):
        st, body = self._request("GET", "/api/v1/mdm/fleet/devices")
        self.assertEqual(st, 200)
        self.assertTrue(body["success"])
        self.assertGreaterEqual(body["count"], 2)

        st2, body2 = self._request("GET", "/api/v1/mdm/fleet/telemetry")
        self.assertEqual(st2, 200)
        self.assertTrue(body2["success"])
        self.assertIn("emergency_safety_status", body2["telemetry"])

    def test_fleet_heartbeat_and_uninstall_lock_law(self):
        # 1. Device reports active countdown timer
        hb_data = {
            "device_id": "dev_api_test_01",
            "lock_state": "STRICT_TIMER",
            "timer_remaining": 1200,
            "ip_address": "10.0.0.42",
            "compliance_score": 98,
        }
        st, body = self._request("POST", "/api/v1/mdm/fleet/heartbeat", hb_data)
        self.assertEqual(st, 200)
        self.assertTrue(body["success"])
        self.assertEqual(body["device"]["lock_state"], "STRICT_TIMER")
        self.assertFalse(body["device"]["can_uninstall"], "Active timer must lock uninstallation")

        # 2. Check uninstall endpoint confirms locked state
        st_chk, chk = self._request("GET", "/api/v1/mdm/fleet/uninstall-check?device_id=dev_api_test_01")
        self.assertEqual(st_chk, 200)
        self.assertFalse(chk["can_uninstall"], "Check uninstall must report False when locked")

        # 3. Queue command to device
        cmd_data = {
            "device_id": "dev_api_test_01",
            "command_type": "LOCK_FOCUS",
            "payload": {"duration_seconds": 1200},
        }
        st_cmd, cmd_resp = self._request("POST", "/api/v1/mdm/fleet/command", cmd_data)
        self.assertEqual(st_cmd, 200)
        self.assertTrue(cmd_resp["success"])
        self.assertTrue(cmd_resp["command_id"].startswith("cmd_"))

        # 4. Fetch pending commands
        st_get_cmd, cmds = self._request("GET", "/api/v1/mdm/fleet/commands?device_id=dev_api_test_01")
        self.assertEqual(st_get_cmd, 200)
        self.assertGreaterEqual(cmds["count"], 1)

        # 5. Operator unlocks device for clean uninstallation
        st_unlock, unl_resp = self._request("POST", "/api/v1/mdm/fleet/unlock-uninstall", {"device_id": "dev_api_test_01"})
        self.assertEqual(st_unlock, 200)
        self.assertTrue(unl_resp["can_uninstall"])

        # 6. Check uninstall endpoint confirms clean uninstallation is now permitted
        st_chk2, chk2 = self._request("GET", "/api/v1/mdm/fleet/uninstall-check?device_id=dev_api_test_01")
        self.assertEqual(st_chk2, 200)
        self.assertTrue(chk2["can_uninstall"], "Check uninstall must report True after operator unlock")

    # =========================================================================
    # 2. GEOFENCE POLICY REST API TESTS
    # =========================================================================

    def test_geofence_zones_get_and_post(self):
        st, body = self._request("GET", "/api/v1/mdm/geofence/zones")
        self.assertEqual(st, 200)
        self.assertTrue(body["success"])
        self.assertGreaterEqual(body["count"], 2)

        # Create new university geofence zone
        zone_payload = {
            "zone_id": "geo_api_test_zone",
            "name": "Biochemistry Hall",
            "latitude": 37.8715,
            "longitude": -122.2600,
            "radius_meters": 120.0,
            "enforce_focus_lock": True,
            "strict_uninstall_lock": True,
        }
        st_post, saved = self._request("POST", "/api/v1/mdm/geofence/zone", zone_payload)
        self.assertEqual(st_post, 200)
        self.assertTrue(saved["success"])
        self.assertEqual(saved["zone"]["name"], "Biochemistry Hall")

    def test_geofence_evaluate_inside_and_outside(self):
        # Inside SF HQ (37.7937, -122.4000)
        inside_payload = {
            "device_id": "dev_geo_eval",
            "latitude": 37.7937,
            "longitude": -122.4000,
        }
        st, res_inside = self._request("POST", "/api/v1/mdm/geofence/evaluate", inside_payload)
        self.assertEqual(st, 200)
        self.assertTrue(res_inside["inside_restricted_geofence"])
        self.assertFalse(res_inside["can_uninstall"], "Inside geofence must lock uninstallation")
        self.assertEqual(res_inside["directive"], "LOCK_FOCUS")

        # Outside all zones (37.3382, -121.8863)
        outside_payload = {
            "device_id": "dev_geo_eval",
            "latitude": 37.3382,
            "longitude": -121.8863,
        }
        st2, res_outside = self._request("POST", "/api/v1/mdm/geofence/evaluate", outside_payload)
        self.assertEqual(st2, 200)
        self.assertFalse(res_outside["inside_restricted_geofence"])
        self.assertTrue(res_outside["can_uninstall"], "Outside geofence must permit clean uninstallation")
        self.assertEqual(res_outside["directive"], "UNLOCK_FOCUS")

        # GET evaluation
        st3, res_get = self._request("GET", "/api/v1/mdm/geofence/evaluate?latitude=37.7937&longitude=-122.4000")
        self.assertEqual(st3, 200)
        self.assertTrue(res_get["inside_restricted_geofence"])

    # =========================================================================
    # 3. ENTERPRISE CALENDAR REST API TESTS
    # =========================================================================

    def test_calendar_events_and_status(self):
        st, body = self._request("GET", "/api/v1/mdm/calendar/events")
        self.assertEqual(st, 200)
        self.assertTrue(body["success"])
        self.assertGreaterEqual(body["count"], 2)

        st_stat, stat = self._request("GET", "/api/v1/mdm/calendar/status")
        self.assertEqual(st_stat, 200)
        self.assertIn("in_focus_window", stat)
        self.assertIn("emergency_safety_status", stat)

    def test_calendar_event_create_and_ical_parse(self):
        ev_data = {
            "event_id": "cal_api_seminar",
            "title": "Autonomous Systems Seminar",
            "start_hour": 13,
            "start_minute": 0,
            "end_hour": 15,
            "end_minute": 0,
            "days_of_week": [1, 3],
        }
        st, saved_ev = self._request("POST", "/api/v1/mdm/calendar/event", ev_data)
        self.assertEqual(st, 200)
        self.assertTrue(saved_ev["success"])
        self.assertEqual(saved_ev["event"]["title"], "Autonomous Systems Seminar")

        # Import iCalendar stream
        ics_text = """BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
SUMMARY:Compiler Design Focus
DTSTART:20261028T100000Z
DTEND:20261028T120000Z
END:VEVENT
END:VCALENDAR"""
        st_ics, ics_resp = self._request("POST", "/api/v1/mdm/calendar/parse-ical", {"ical_text": ics_text})
        self.assertEqual(st_ics, 200)
        self.assertEqual(ics_resp["imported_events_count"], 1)

    # =========================================================================
    # 4. PUSH HUB & CLI INTEGRATION TESTS
    # =========================================================================

    def test_push_hub_dispatch_api(self):
        push_data = {
            "topic": "device:dev_pixel_corp_01",
            "data": {"alert": "POLICY_UPDATE_REQUIRED", "priority": "HIGH"},
        }
        st, body = self._request("POST", "/api/v1/mdm/push/dispatch", push_data)
        self.assertEqual(st, 200)
        self.assertTrue(body["success"])
        self.assertEqual(body["topic"], "device:dev_pixel_corp_01")

    def test_cli_subcommands_phase4(self):
        # 1. mdm-control --list-fleet
        stdout_trap1 = io.StringIO()
        with patch("sys.stdout", stdout_trap1):
            with patch("sys.argv", ["cli_engine", "mdm-control", "--list-fleet"]):
                cli_main()
        self.assertIn("ENTERPRISE FLEET CONTROL PLANE", stdout_trap1.getvalue())

        # 2. mdm-geofence --lat 37.7937 --lon -122.4000
        stdout_trap2 = io.StringIO()
        with patch("sys.stdout", stdout_trap2):
            with patch("sys.argv", ["cli_engine", "mdm-geofence", "--lat", "37.7937", "--lon", "-122.4000"]):
                cli_main()
        out2 = stdout_trap2.getvalue()
        self.assertIn("GEOFENCE LOCATION EVALUATION", out2)
        self.assertIn("Inside Restricted:    True", out2)
        self.assertIn("Can Uninstall:        False", out2)

        # 3. mdm-schedule
        stdout_trap3 = io.StringIO()
        with patch("sys.stdout", stdout_trap3):
            with patch("sys.argv", ["cli_engine", "mdm-schedule"]):
                cli_main()
        out3 = stdout_trap3.getvalue()
        self.assertIn("ENTERPRISE CALENDAR SCHEDULE EVALUATION", out3)
        self.assertIn("Emergency 911/112 dialer is 100% exempt", out3)


if __name__ == "__main__":
    unittest.main()
