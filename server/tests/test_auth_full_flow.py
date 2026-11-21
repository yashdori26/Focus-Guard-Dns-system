"""
Full Flow Integration Tests for Enterprise Phone Auth, Sessions, and Profile Setup Wizard
"""

import json
import os
import unittest
from http.server import HTTPServer
import threading
import urllib.request
import urllib.error

os.environ["FOCUS_DNS_TEST_MODE"] = "1"
os.environ["FOCUS_DNS_DB_PATH"] = ":memory:"

from server import db
from server.api_router import FocusDNSApiHandler


class TestAuthFullFlow(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        db.init_db()
        cls.server = HTTPServer(("127.0.0.1", 0), FocusDNSApiHandler)
        cls.port = cls.server.server_port
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def test_01_session_verify_unauthenticated(self):
        req = urllib.request.Request(f"{self.base_url}/api/auth/session/verify")
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req)
        self.assertEqual(ctx.exception.code, 401)

    def test_02_full_phone_auth_and_session_verify(self):
        phone = "+919876543219"
        # 1. Send OTP
        send_req = urllib.request.Request(
            f"{self.base_url}/api/auth/phone/send-otp",
            data=json.dumps({"phone": phone}).encode(),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(send_req) as resp:
            data = json.loads(resp.read().decode())
            self.assertTrue(data["success"])
            otp = data["dev_otp"]

        # 2. Verify OTP
        verify_req = urllib.request.Request(
            f"{self.base_url}/api/auth/phone/verify-otp",
            data=json.dumps({"phone": phone, "otp": otp}).encode(),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(verify_req) as resp:
            v_data = json.loads(resp.read().decode())
            self.assertTrue(v_data["success"])
            token = v_data["token"]
            self.assertIsNotNone(token)

        # 3. Verify Session via token header
        sess_req = urllib.request.Request(
            f"{self.base_url}/api/auth/session/verify",
            headers={"Authorization": f"Bearer {token}"}
        )
        with urllib.request.urlopen(sess_req) as resp:
            s_data = json.loads(resp.read().decode())
            self.assertTrue(s_data["success"])
            self.assertEqual(s_data["phone"], phone)
            self.assertIn("active_profile_id", s_data)

        # 4. Profile Setup Wizard (Name Profile)
        setup_req = urllib.request.Request(
            f"{self.base_url}/api/auth/profile/setup",
            data=json.dumps({
                "phone": phone,
                "profile_id": s_data["active_profile_id"],
                "profile_name": "Executive Mac Shield",
                "preset": "strict",
                "icon": "shield",
                "device_type": "mac"
            }).encode(),
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"}
        )
        with urllib.request.urlopen(setup_req) as resp:
            setup_data = json.loads(resp.read().decode())
            self.assertTrue(setup_data["success"])
            self.assertEqual(setup_data["profile_name"], "Executive Mac Shield")
            self.assertEqual(setup_data["preset"], "strict")

        # 5. Check Active Sessions
        active_req = urllib.request.Request(
            f"{self.base_url}/api/auth/sessions/active?phone={urllib.parse.quote(phone)}",
            headers={"Authorization": f"Bearer {token}"}
        )
        with urllib.request.urlopen(active_req) as resp:
            act_data = json.loads(resp.read().decode())
            self.assertTrue(act_data["success"])
            self.assertGreater(len(act_data["sessions"]), 0)

        # 6. Logout Session
        logout_req = urllib.request.Request(
            f"{self.base_url}/api/auth/session/logout",
            data=json.dumps({}).encode(),
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"}
        )
        with urllib.request.urlopen(logout_req) as resp:
            logout_data = json.loads(resp.read().decode())
            self.assertTrue(logout_data["success"])

        # 7. Verifying again after logout fails
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(sess_req)
        self.assertEqual(ctx.exception.code, 401)


if __name__ == "__main__":
    unittest.main()
