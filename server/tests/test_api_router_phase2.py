"""
Integration Test Suite for Topic 5 Phase 2 REST API Routes.

Tests:
1. macOS NetworkExtension routes: /api/v1/macos/status, /mobileconfig, /launchd, /lock, /unlock, /telemetry.
2. Linux eBPF routes: /api/v1/ebpf/status, /lock, /unlock, /unload (conditional uninstallation check).
3. Asuswrt-Merlin & DD-WRT routes: /api/v1/asuswrt/dnsmasq-postconf, /nat-start, /api/v1/ddwrt/rc-firewall.
4. Router DoQ & DNSSEC routes: /api/v1/router/doq/telemetry, /api/v1/router/dnssec/stats.
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


class TestApiRouterPhase2(unittest.TestCase):

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

    def test_macos_status_and_lock_flow(self):
        # 1. Check initial status
        status, data = self._get("/api/v1/macos/status")
        self.assertEqual(status, 200)
        self.assertEqual(data["platform"], "macOS")
        self.assertTrue(data["can_uninstall"])

        # 2. Lock focus mode for 15 minutes
        status_lock, lock_resp = self._post("/api/v1/macos/lock", {"duration_seconds": 900})
        self.assertEqual(status_lock, 200)
        self.assertFalse(lock_resp["can_uninstall"])
        self.assertEqual(lock_resp["remaining_timer_seconds"], 900)

        # 3. Simulate tamper telemetry during lock
        status_tel, tel_resp = self._post("/api/v1/macos/telemetry", {"event_type": "ATTEMPT_UNINSTALL"})
        self.assertEqual(status_tel, 403)
        self.assertEqual(tel_resp["error_code"], "ERROR_ACCESS_DENIED")

        # 4. Unlock and verify uninstallation allowed
        status_unl, unl_resp = self._post("/api/v1/macos/unlock", {})
        self.assertEqual(status_unl, 200)
        self.assertTrue(unl_resp["can_uninstall"])

    def test_macos_mobileconfig_download(self):
        status, data = self._get("/api/v1/macos/mobileconfig?profile_id=profile_strict_kids")
        self.assertEqual(status, 200)
        self.assertIn(b"com.apple.dnsProxy.managed", data)
        self.assertIn(b"com.apple.webcontent-filter", data)

    def test_macos_launchd_plist_route(self):
        status, data = self._get("/api/v1/macos/launchd")
        self.assertEqual(status, 200)
        self.assertIn("launchd_plist", data)
        self.assertIn("com.focusguard.dns.daemon", data["launchd_plist"])

    def test_ebpf_status_and_unload_protection(self):
        status, data = self._get("/api/v1/ebpf/status")
        self.assertEqual(status, 200)
        self.assertTrue(data["can_uninstall"])

        # Lock eBPF
        status_lock, lock_resp = self._post("/api/v1/ebpf/lock", {"duration_seconds": 600})
        self.assertEqual(status_lock, 200)
        self.assertFalse(lock_resp["can_uninstall"])

        # Attempt to unload while locked -> Expect HTTP 403
        status_unload_locked, unload_resp = self._post("/api/v1/ebpf/unload", {})
        self.assertEqual(status_unload_locked, 403)
        self.assertIn("ERROR_ACCESS_DENIED", unload_resp["error"])

        # Unlock and unload successfully
        status_unl, _ = self._post("/api/v1/ebpf/unlock", {})
        self.assertEqual(status_unl, 200)

        status_unload_ok, ok_resp = self._post("/api/v1/ebpf/unload", {})
        self.assertEqual(status_unload_ok, 200)
        self.assertTrue(ok_resp["success"])

    def test_asuswrt_and_ddwrt_routes(self):
        status_postconf, data_postconf = self._get("/api/v1/asuswrt/dnsmasq-postconf")
        self.assertEqual(status_postconf, 200)
        self.assertIn("pc_replace", data_postconf["script"])

        status_nat, data_nat = self._get("/api/v1/asuswrt/nat-start")
        self.assertEqual(status_nat, 200)
        self.assertIn("REDIRECT --to-ports 5353", data_nat["script"])

        status_ddwrt, data_ddwrt = self._get("/api/v1/ddwrt/rc-firewall")
        self.assertEqual(status_ddwrt, 200)
        self.assertIn("REDIRECT --to-ports 5353", data_ddwrt["script"])

    def test_doq_and_dnssec_routes(self):
        status_doq, data_doq = self._get("/api/v1/router/doq/telemetry")
        self.assertEqual(status_doq, 200)
        self.assertEqual(data_doq["alpn"], "doq")

        status_dnssec, data_dnssec = self._get("/api/v1/router/dnssec/stats")
        self.assertEqual(status_dnssec, 200)
        self.assertGreaterEqual(data_dnssec["trust_anchors_count"], 2)


if __name__ == "__main__":
    unittest.main()
