"""
Tests for Phone SMS OTP Authentication & GeoIP Discovery
"""

import json
import os
import unittest
from http.server import HTTPServer
import threading
import urllib.request
import urllib.error

# Ensure test DB
os.environ["FOCUS_DNS_TEST_MODE"] = "1"
os.environ["FOCUS_DNS_DB_PATH"] = ":memory:"

from server import db
from server.api_router import FocusDNSApiHandler
from server.geo_ip import get_geo_info, country_code_to_flag, DIAL_CODES


class TestPhoneAuthAndGeoIP(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Set up in-memory DB
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

    def test_01_country_code_to_flag(self):
        self.assertEqual(country_code_to_flag("IN"), "🇮🇳")
        self.assertEqual(country_code_to_flag("US"), "🇺🇸")
        self.assertEqual(country_code_to_flag("GB"), "🇬🇧")
        self.assertEqual(country_code_to_flag("JP"), "🇯🇵")
        self.assertEqual(country_code_to_flag(""), "🌐")

    def test_02_get_geo_ip_endpoint(self):
        req = urllib.request.Request(f"{self.base_url}/api/geo/ip")
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            self.assertTrue(data.get("success"))
            self.assertIn("country_code", data)
            self.assertIn("dial_code", data)
            self.assertIn("flag", data)
            self.assertIn("country_name", data)
            self.assertTrue(data["dial_code"].startswith("+"))

    def test_03_get_geo_ip_with_headers(self):
        req = urllib.request.Request(f"{self.base_url}/api/geo/ip", headers={
            "CF-IPCountry": "US"
        })
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            self.assertEqual(data["country_code"], "US")
            self.assertEqual(data["flag"], "🇺🇸")
            self.assertEqual(data["dial_code"], "+1")

        req = urllib.request.Request(f"{self.base_url}/api/geo/ip", headers={
            "Accept-Language": "en-GB,en;q=0.9"
        })
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            self.assertEqual(data["country_code"], "GB")
            self.assertEqual(data["flag"], "🇬🇧")
            self.assertEqual(data["dial_code"], "+44")

    def test_04_get_geo_countries(self):
        req = urllib.request.Request(f"{self.base_url}/api/geo/countries")
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            self.assertTrue(data.get("success"))
            countries = data.get("countries", [])
            self.assertGreater(len(countries), 50)
            in_item = next((c for c in countries if c["country_code"] == "IN"), None)
            self.assertIsNotNone(in_item)
            self.assertEqual(in_item["dial_code"], "+91")
            self.assertEqual(in_item["flag"], "🇮🇳")

    def test_05_send_and_verify_otp_flow(self):
        phone = "+919876543210"
        
        # 1. Send OTP
        send_payload = json.dumps({"phone": phone}).encode()
        req = urllib.request.Request(
            f"{self.base_url}/api/auth/phone/send-otp",
            data=send_payload,
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            self.assertTrue(data.get("success"))
            dev_otp = data.get("dev_otp")
            self.assertIsNotNone(dev_otp)

        # 2. Reject incorrect OTP
        verify_wrong = json.dumps({"phone": phone, "otp": "000000"}).encode()
        req_wrong = urllib.request.Request(
            f"{self.base_url}/api/auth/phone/verify-otp",
            data=verify_wrong,
            headers={"Content-Type": "application/json"}
        )
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req_wrong)
        self.assertEqual(ctx.exception.code, 401)

        # 3. Verify with correct OTP
        verify_ok = json.dumps({"phone": phone, "otp": dev_otp}).encode()
        req_ok = urllib.request.Request(
            f"{self.base_url}/api/auth/phone/verify-otp",
            data=verify_ok,
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req_ok) as resp:
            result = json.loads(resp.read().decode())
            self.assertTrue(result.get("success"))
            self.assertEqual(result.get("phone"), phone)
            self.assertIn("token", result)
            self.assertIn("profiles", result)
            self.assertGreater(len(result["profiles"]), 0)
            active_profile = result.get("active_profile")
            self.assertIsNotNone(active_profile)

    def test_06_phone_profile_creation_and_listing(self):
        phone = "+14155552671"
        # Verify with universal dev OTP 123456
        db.store_otp(phone, "123456", 300)
        verify_ok = json.dumps({"phone": phone, "otp": "123456"}).encode()
        req_ok = urllib.request.Request(
            f"{self.base_url}/api/auth/phone/verify-otp",
            data=verify_ok,
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req_ok) as resp:
            res = json.loads(resp.read().decode())
            token = res["token"]

        # Create a second profile for this phone
        create_payload = json.dumps({
            "name": "Work Focus Mode",
            "phone": phone
        }).encode()
        req_create = urllib.request.Request(
            f"{self.base_url}/api/user/profiles",
            data=create_payload,
            headers={
                "Content-Type": "application/json",
                "X-Api-Key": token
            }
        )
        with urllib.request.urlopen(req_create) as resp:
            res_create = json.loads(resp.read().decode())
            self.assertTrue(res_create.get("success"))
            new_pid = res_create.get("profile_id")
            self.assertIsNotNone(new_pid)

        # List profiles for this phone
        req_list = urllib.request.Request(
            f"{self.base_url}/api/user/profiles?phone={urllib.parse.quote(phone)}",
            headers={"X-Api-Key": token}
        )
        with urllib.request.urlopen(req_list) as resp:
            res_list = json.loads(resp.read().decode())
            profiles = res_list.get("profiles", [])
            names = [p["name"] for p in profiles]
            self.assertIn("Work Focus Mode", names)

    def test_07_post_settings_update(self):
        token = db.get_or_create_api_token()
        pid = db.create_profile("Settings Test Profile")
        payload = json.dumps({
            "profile_id": pid,
            "profile_name": "Renamed Profile Via POST",
            "log_retention": "1 month"
        }).encode()
        req = urllib.request.Request(
            f"{self.base_url}/api/settings",
            data=payload,
            headers={
                "Content-Type": "application/json",
                "X-Api-Key": token
            }
        )
        with urllib.request.urlopen(req) as resp:
            res = json.loads(resp.read().decode())
            self.assertTrue(res.get("success"))

        # Verify updated name
        p = db.get_profile(pid)
        self.assertEqual(p["name"], "Renamed Profile Via POST")
        self.assertEqual(p["log_retention"], "1 month")


if __name__ == "__main__":
    unittest.main()
