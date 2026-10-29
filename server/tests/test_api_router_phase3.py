"""
Integration Test Suite for Topic 5 Phase 3 REST API Routes.

Tests:
1. MikroTik RouterOS routes: /api/v1/mikrotik/status, /script, /lock, /unlock, /teardown.
2. Ubiquiti EdgeOS & UniFi routes: /api/v1/ubiquiti/status, /script, /lock, /unlock, /teardown.
3. Master Router Orchestrator routes: /api/v1/orchestrator/status, /lock, /unlock, /stop.
4. Conditional Uninstallation Law: Teardown returns HTTP 403 when active focus or timer is engaged.
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


class TestApiRouterPhase3(unittest.TestCase):

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
            ct = resp.headers.get("Content-Type", "")
            if "json" in ct:
                return resp.status, json.loads(data.decode("utf-8"))
            return resp.status, data

    def _post(self, path: str, body: dict):
        payload = json.dumps(body).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.token}"
        }
        req = urllib.request.Request(f"{self.base_url}{path}", data=payload, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=3.0) as resp:
                data = resp.read()
                return resp.status, json.loads(data.decode("utf-8"))
        except urllib.error.HTTPError as e:
            err_data = e.read()
            return e.code, json.loads(err_data.decode("utf-8"))

    def test_mikrotik_status_and_script(self):
        status, data = self._get("/api/v1/mikrotik/status")
        self.assertEqual(status, 200)
        self.assertIn("MikroTik", data["platform"])
        self.assertIn("can_uninstall", data)

        status, data = self._get("/api/v1/mikrotik/script")
        self.assertEqual(status, 200)
        self.assertTrue(data["success"])
        self.assertIn("nat", data)
        self.assertIn("filter", data)
        self.assertIn("netwatch", data)
        self.assertIn("container", data)

    def test_mikrotik_lock_and_conditional_teardown(self):
        # 1. Engage lock
        status, data = self._post("/api/v1/mikrotik/lock", {"duration_seconds": 1800})
        self.assertEqual(status, 200)
        self.assertTrue(data["is_locked"])
        self.assertFalse(data["can_uninstall"])

        # 2. Teardown while locked -> 403 Forbidden
        status, data = self._post("/api/v1/mikrotik/teardown", {})
        self.assertEqual(status, 403)
        self.assertFalse(data["success"])
        self.assertIn("ERROR_ACCESS_DENIED", data["error"])

        # 3. Unlock
        status, data = self._post("/api/v1/mikrotik/unlock", {})
        self.assertEqual(status, 200)
        self.assertFalse(data["is_locked"])
        self.assertTrue(data["can_uninstall"])

        # 4. Teardown while unlocked -> 200 OK
        status, data = self._post("/api/v1/mikrotik/teardown", {})
        self.assertEqual(status, 200)
        self.assertTrue(data["success"])
        self.assertIn("script", data)

    def test_ubiquiti_status_and_script(self):
        status, data = self._get("/api/v1/ubiquiti/status")
        self.assertEqual(status, 200)
        self.assertIn("Ubiquiti", data["platform"])
        self.assertIn("can_uninstall", data)

        status, data = self._get("/api/v1/ubiquiti/script")
        self.assertEqual(status, 200)
        self.assertTrue(data["success"])
        self.assertIn("edgeos", data)
        self.assertIn("unifi", data)

    def test_ubiquiti_lock_and_conditional_teardown(self):
        # 1. Engage lock
        status, data = self._post("/api/v1/ubiquiti/lock", {"duration_seconds": 3600})
        self.assertEqual(status, 200)
        self.assertTrue(data["is_locked"])
        self.assertFalse(data["can_uninstall"])

        # 2. Teardown while locked -> 403 Forbidden
        status, data = self._post("/api/v1/ubiquiti/teardown", {})
        self.assertEqual(status, 403)
        self.assertFalse(data["success"])
        self.assertIn("ERROR_ACCESS_DENIED", data["error"])

        # 3. Unlock
        status, data = self._post("/api/v1/ubiquiti/unlock", {})
        self.assertEqual(status, 200)
        self.assertFalse(data["is_locked"])
        self.assertTrue(data["can_uninstall"])

        # 4. Teardown while unlocked -> 200 OK
        status, data = self._post("/api/v1/ubiquiti/teardown", {})
        self.assertEqual(status, 200)
        self.assertTrue(data["success"])
        self.assertIn("script", data)

    def test_orchestrator_status_and_lifecycle(self):
        # 1. Get status
        status, data = self._get("/api/v1/orchestrator/status")
        self.assertEqual(status, 200)
        self.assertIn("router_id", data)
        self.assertIn("subsystems", data)

        # 2. Lock orchestrator
        status, data = self._post("/api/v1/orchestrator/lock", {"duration_seconds": 1200})
        self.assertEqual(status, 200)
        self.assertTrue(data["is_locked"])
        self.assertFalse(data["can_uninstall"])

        # 3. Stop while locked -> 403 Forbidden
        status, data = self._post("/api/v1/orchestrator/stop", {})
        self.assertEqual(status, 403)
        self.assertFalse(data["success"])
        self.assertIn("ERROR_ACCESS_DENIED", data["error"])

        # 4. Unlock orchestrator
        status, data = self._post("/api/v1/orchestrator/unlock", {})
        self.assertEqual(status, 200)
        self.assertFalse(data["is_locked"])
        self.assertTrue(data["can_uninstall"])

        # 5. Stop while unlocked -> 200 OK
        status, data = self._post("/api/v1/orchestrator/stop", {})
        self.assertEqual(status, 200)
        self.assertTrue(data["success"])


if __name__ == "__main__":
    unittest.main()
