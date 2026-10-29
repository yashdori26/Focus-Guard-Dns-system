"""
server/tests/test_api_router_wfp.py
Integration Test Suite for Topic 5 Router Gateway & Windows WFP REST API Routes.

Tests live HTTP endpoints against ephemeral test server:
1. GET /api/v1/router/status & GET /api/v1/router/devices
2. POST /api/v1/router/device/profile
3. GET /api/v1/router/install-script (OpenWrt, pfSense, OPNSense)
4. GET /api/v1/router/pf-anchor
5. GET /api/v1/wfp/status & GET /api/v1/wfp/uninstall-check
6. Inviolable Conditional Service Protection Law via REST API:
   - Lock Focus -> simulate-stop returns HTTP 403 ERROR_ACCESS_DENIED.
   - Unlock Focus -> simulate-stop returns HTTP 200 SERVICE_STOPPED.
7. POST /api/v1/wfp/block-app and unblock-app.
"""

import unittest
import json
import urllib.request
import urllib.error
from http.server import HTTPServer
import threading
import time

from server import db
from server.api_router import FocusDNSApiHandler


class TestApiRouterWfp(unittest.TestCase):
    """Integration test suite for Topic 5 REST API routes."""

    token: str = ""

    @classmethod
    def setUpClass(cls):
        db.init_db()
        cls.token = db.get_or_create_api_token()
        cls.server = HTTPServer(("127.0.0.1", 0), FocusDNSApiHandler)
        cls.port = cls.server.server_port
        cls.base_url = f"http://127.0.0.1:{cls.port}"
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        time.sleep(0.1)

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def _get(self, path: str):
        headers = {"Authorization": f"Bearer {self.token}"}
        req = urllib.request.Request(f"{self.base_url}{path}", headers=headers)
        with urllib.request.urlopen(req, timeout=3.0) as resp:
            data = resp.read()
            return resp.status, json.loads(data.decode("utf-8"))

    def _post(self, path: str, body: dict):
        payload = json.dumps(body).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.token}",
        }
        req = urllib.request.Request(
            f"{self.base_url}{path}",
            data=payload,
            headers=headers,
        )
        try:
            with urllib.request.urlopen(req, timeout=3.0) as resp:
                data = resp.read()
                return resp.status, json.loads(data.decode("utf-8"))
        except urllib.error.HTTPError as e:
            data = e.read()
            return e.code, json.loads(data.decode("utf-8"))

    def test_router_status_and_devices_endpoints(self):
        """Verifies GET /api/v1/router/status and devices."""
        status_code, data = self._get("/api/v1/router/status")
        self.assertEqual(status_code, 200)
        self.assertIn("platform_type", data)
        self.assertIn("can_uninstall", data)

        dev_status, dev_data = self._get("/api/v1/router/devices")
        self.assertEqual(dev_status, 200)
        self.assertTrue(dev_data["success"])
        self.assertGreaterEqual(dev_data["count"], 1)

    def test_assign_device_profile_endpoint(self):
        """Verifies POST /api/v1/router/device/profile mapping."""
        code, data = self._post("/api/v1/router/device/profile", {
            "mac_address": "D8:9E:3F:AA:BB:CC",
            "profile_id": "profile_strict_kids",
            "hostname": "Test-iPad",
            "device_category": "Tablet",
            "strict_lock": True,
        })
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])
        self.assertEqual(data["assigned_profile"], "profile_strict_kids")
        self.assertTrue(data["strict_lock"])

    def test_router_install_script_and_pf_anchor_endpoints(self):
        """Verifies 1-click script generation and BSD PF anchor compilation."""
        # OpenWrt script
        c1, d1 = self._get("/api/v1/router/install-script?platform=openwrt&profile_id=profile_kids")
        self.assertEqual(c1, 200)
        self.assertIn("luci-app-focus-dns", d1["command"])

        # pfSense script
        c2, d2 = self._get("/api/v1/router/install-script?platform=pfsense&profile_id=profile_kids")
        self.assertEqual(c2, 200)
        self.assertIn("focus_dns_sync_config", d2["command"])

        # PF anchor rules
        c3, d3 = self._get("/api/v1/router/pf-anchor")
        self.assertEqual(c3, 200)
        self.assertIn("rdr pass on", d3["anchor_config"])
        self.assertTrue(d3["success"])

    def test_windows_wfp_conditional_uninstallation_law(self):
        """
        Inviolable Conditional Uninstallation Law REST API Verification:
        1. Idle mode: uninstall-check returns True.
        2. Arm focus lock: uninstall-check returns False.
        3. Attempt simulate-stop: returns HTTP 403 ERROR_ACCESS_DENIED.
        4. Disarm focus lock: uninstall-check returns True.
        5. Attempt simulate-stop: returns HTTP 200 SERVICE_STOPPED.
        """
        # Unlock initially
        self._post("/api/v1/wfp/unlock", {})
        c_check, d_check = self._get("/api/v1/wfp/uninstall-check")
        self.assertEqual(c_check, 200)
        self.assertTrue(d_check["can_uninstall"])

        # 1. Arm focus lock
        c_lock, d_lock = self._post("/api/v1/wfp/lock", {"duration_seconds": 900})
        self.assertEqual(c_lock, 200)
        self.assertFalse(d_lock["can_uninstall"])

        # 2. Check uninstallation status
        c_chk2, d_chk2 = self._get("/api/v1/wfp/uninstall-check")
        self.assertEqual(c_chk2, 200)
        self.assertFalse(d_chk2["can_uninstall"])

        # 3. Simulate service stop attempt during active focus
        c_stop_locked, d_stop_locked = self._post("/api/v1/wfp/simulate-stop", {})
        self.assertEqual(c_stop_locked, 403)
        self.assertFalse(d_stop_locked["allowed"])
        self.assertIn("ERROR_ACCESS_DENIED", d_stop_locked["message"])

        # 4. Disarm focus lock
        c_unlock, d_unlock = self._post("/api/v1/wfp/unlock", {})
        self.assertEqual(c_unlock, 200)
        self.assertTrue(d_unlock["can_uninstall"])

        # 5. Clean service stop permitted in normal idle mode
        c_stop_clean, d_stop_clean = self._post("/api/v1/wfp/simulate-stop", {})
        self.assertEqual(c_stop_clean, 200)
        self.assertTrue(d_stop_clean["allowed"])
        self.assertIn("SERVICE_STOPPED", d_stop_clean["message"])

    def test_wfp_app_blocking_and_audit(self):
        """Verifies blocking/unblocking apps and querying audit telemetry."""
        cb, db = self._post("/api/v1/wfp/block-app", {"app_name": "Discord"})
        self.assertEqual(cb, 200)
        self.assertTrue(db["is_blocked"])

        cu, du = self._post("/api/v1/wfp/unblock-app", {"app_name": "Discord"})
        self.assertEqual(cu, 200)
        self.assertFalse(du["is_blocked"])

        ca, da = self._get("/api/v1/wfp/audit")
        self.assertEqual(ca, 200)
        self.assertTrue(da["success"])


if __name__ == "__main__":
    unittest.main()
