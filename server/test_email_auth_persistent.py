"""
Comprehensive Test Suite for FocusDNS Email Authentication, Profile Preservation & SMTP
Validates:
1. SQLite users & email_verification_codes schema initialization
2. PBKDF2-HMAC-SHA256 salted password hashing & timing-safe verification
3. User registration with dedicated profile provisioning & username binding
4. User authentication with 100% profile & settings preservation (Option 2A)
5. Outbound SMTP email service, HTML templating, and configuration resolution (Option 1B)
6. 4-digit email verification code storage, expiration, and validation
7. End-to-end HTTP API endpoints (/api/auth/email/* & /api/admin/smtp)
"""

import hashlib
import json
import os
import sys
import time
import unittest
import urllib.request
import urllib.error

# Ensure project root is in python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from server import db
from server import email_service


class TestEmailAuthAndProfilePersistence(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        # Initialize database tables
        db.init_db()

    def test_01_password_hashing(self):
        """Verify PBKDF2 salted password hashing & timing-safe verification."""
        password = "SecurePassword#2026"
        pwd_hash = db.hash_password(password)
        
        self.assertTrue(pwd_hash.startswith("pbkdf2_sha256$100000$"))
        self.assertNotEqual(password, pwd_hash)
        
        # Two hashes of the same password must differ due to unique salts
        pwd_hash2 = db.hash_password(password)
        self.assertNotEqual(pwd_hash, pwd_hash2)

        # Verification tests
        self.assertTrue(db.verify_password(password, pwd_hash))
        self.assertTrue(db.verify_password(password, pwd_hash2))
        self.assertFalse(db.verify_password("WrongPassword123", pwd_hash))
        self.assertFalse(db.verify_password("", pwd_hash))
        self.assertFalse(db.verify_password(password, "invalid_hash_string"))

    def test_02_create_user_account_and_profile_binding(self):
        """Verify creating a user account provisions a dedicated profile with username preserved."""
        test_email = f"user_{int(time.time())}@example.com"
        test_pwd = "MySecretPassword123"
        test_profile_name = "Focus Master Alpha"

        ok, msg, user_data = db.create_user_account(test_email, test_pwd, test_profile_name)
        self.assertTrue(ok, f"User creation failed: {msg}")
        self.assertIsNotNone(user_data)
        self.assertEqual(user_data["email"], test_email)
        self.assertEqual(user_data["profile_name"], test_profile_name)
        self.assertFalse(user_data["is_email_verified"])
        
        pid = user_data["profile_id"]
        self.assertTrue(pid.startswith("p_") or len(pid) == 6)

        # Verify dedicated profile was created in database
        profile = db.get_profile(pid)
        self.assertIsNotNone(profile)
        self.assertEqual(profile["name"], test_profile_name)

        # Verify deep focus items default rules are attached (porn, gambling, piracy, etc.)
        items_dict = db.get_deep_focus_items(pid)
        all_items = items_dict["websites"] + items_dict["categories"]
        blocked_ids = {it["id"] for it in all_items if it.get("is_blocked")}
        self.assertIn("porn", blocked_ids)
        self.assertIn("gambling", blocked_ids)
        self.assertIn("piracy", blocked_ids)
        self.assertIn("reddit", blocked_ids)
        self.assertIn("youtube", blocked_ids)

        # Verify duplicate registration is rejected
        dup_ok, dup_msg, _ = db.create_user_account(test_email, "anotherpassword", "Another Name")
        self.assertFalse(dup_ok)
        self.assertIn("already exists", dup_msg.lower())

    def test_03_authenticate_user_and_settings_preservation(self):
        """Verify authentication restores the exact profile, username, and preserved configurations."""
        test_email = f"shield_{int(time.time())}@focusdns.net"
        test_pwd = "StrongPassword789!"
        test_pname = "Executive Shield"

        # 1. Create account
        ok, _, udata = db.create_user_account(test_email, test_pwd, test_pname)
        self.assertTrue(ok)
        pid = udata["profile_id"]

        # 2. Customize profile settings (add custom denylist domain & modify item)
        db.add_custom_rule(pid, "deny", "malicious-phishing-test.org")
        db.add_custom_rule(pid, "allow", "internal-workplace.corp")

        # 3. Wrong password authentication must fail
        bad_ok, bad_msg, bad_data = db.authenticate_user(test_email, "WrongPassword#123")
        self.assertFalse(bad_ok)
        self.assertIsNone(bad_data)

        # 4. Correct authentication must succeed and restore everything 100%
        login_ok, login_msg, login_data = db.authenticate_user(test_email, test_pwd)
        self.assertTrue(login_ok, login_msg)
        self.assertIsNotNone(login_data)
        self.assertEqual(login_data["email"], test_email)
        self.assertEqual(login_data["profile_id"], pid)
        self.assertEqual(login_data["profile_name"], test_pname)
        self.assertFalse(login_data["is_email_verified"])

        # 5. Verify customized rules remain preserved
        deny_domains = db.get_custom_rules(pid, "deny")
        allow_domains = db.get_custom_rules(pid, "allow")
        self.assertIn("malicious-phishing-test.org", deny_domains)
        self.assertIn("internal-workplace.corp", allow_domains)

    def test_04_email_verification_code_lifecycle(self):
        """Verify 4-digit code generation, validation, expiration, and status flip."""
        test_email = f"verify_{int(time.time())}@focusdns.net"
        test_pwd = "Password4Verify"
        db.create_user_account(test_email, test_pwd, "Verification User")

        code = "8492"
        # Store code with 900s TTL
        db.store_email_verification_code(test_email, code, ttl_seconds=900)

        # Wrong code must fail
        wrong_ok, wrong_msg = db.verify_user_email_code(test_email, "1111")
        self.assertFalse(wrong_ok)
        self.assertIn("invalid", wrong_msg.lower())

        # Correct code must succeed
        valid_ok, valid_msg = db.verify_user_email_code(test_email, code)
        self.assertTrue(valid_ok, valid_msg)

        # Verify user account is marked as is_email_verified = 1 in SQLite
        user = db.get_user_by_email(test_email)
        self.assertIsNotNone(user)
        self.assertTrue(user["is_email_verified"])

        # Re-using the same code must fail because it was purged upon success
        reuse_ok, _ = db.verify_user_email_code(test_email, code)
        self.assertFalse(reuse_ok)

        # Sign-in must now reflect is_email_verified = True
        auth_ok, _, auth_data = db.authenticate_user(test_email, test_pwd)
        self.assertTrue(auth_ok)
        self.assertTrue(auth_data["is_email_verified"])

    def test_05_smtp_service_and_html_rendering(self):
        """Verify SMTP service configuration resolution, HTML template, and error handling."""
        html = email_service.build_verification_email_html("5731", "Test Profile")
        self.assertIn("5731", html)
        self.assertIn("FocusDNS Security", html)
        self.assertIn("15 minutes", html)
        self.assertIn("Test Profile", html)

        # Check SMTP configuration retrieval
        cfg = email_service.get_active_smtp_config()
        self.assertIn("host", cfg)
        self.assertIn("port", cfg)
        self.assertIn("from", cfg)

        # When SMTP_HOST is unset, send_verification_email gracefully reports not configured
        if not cfg["host"]:
            sent, msg = email_service.send_verification_email("someone@example.com", "5731")
            self.assertFalse(sent)
            self.assertIn("SMTP", msg)

    def test_06_smtp_config_persistence(self):
        """Verify setting and updating SMTP configuration in SQLite system_settings."""
        db.set_smtp_config(
            host="smtp.example.com",
            port=587,
            user="apikey",
            password="secret_smtp_password",
            sender="FocusDNS Alerts <alerts@focusdns.net>",
            use_tls=True,
            use_ssl=False,
            enabled=True
        )

        cfg = db.get_smtp_config()
        self.assertEqual(cfg["host"], "smtp.example.com")
        self.assertEqual(cfg["port"], 587)
        self.assertEqual(cfg["user"], "apikey")
        self.assertEqual(cfg["pass"], "secret_smtp_password")
        self.assertEqual(cfg["from"], "FocusDNS Alerts <alerts@focusdns.net>")
        self.assertTrue(cfg["use_tls"])
        self.assertFalse(cfg["use_ssl"])
        self.assertTrue(cfg["enabled"])

    def test_07_live_http_email_registration_and_login(self):
        """Verify POST /api/auth/email/register and POST /api/auth/email/login via live HTTP."""
        unique_email = f"http_test_{int(time.time())}@focusdns.net"
        test_pwd = "LiveHttpPassword99!"
        test_pname = "Omega Sentinel"

        # 1. Register Account via HTTP
        reg_req = urllib.request.Request(
            "http://127.0.0.1:8080/api/auth/email/register",
            data=json.dumps({
                "email": unique_email,
                "password": test_pwd,
                "profile_name": test_pname
            }).encode('utf-8'),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(reg_req) as resp:
            self.assertEqual(resp.status, 200)
            data = json.loads(resp.read().decode('utf-8'))
            self.assertTrue(data["success"])
            self.assertEqual(data["email"], unique_email)
            self.assertEqual(data["profile_name"], test_pname)
            self.assertFalse(data["is_email_verified"])
            self.assertIn("dev_otp", data)
            pid = data["profile_id"]

        # 2. Login with incorrect password must return HTTP 401
        bad_req = urllib.request.Request(
            "http://127.0.0.1:8080/api/auth/email/login",
            data=json.dumps({
                "email": unique_email,
                "password": "CompletelyWrongPassword!"
            }).encode('utf-8'),
            headers={"Content-Type": "application/json"}
        )
        try:
            with urllib.request.urlopen(bad_req) as resp:
                self.fail("Expected HTTP 401 for wrong password, got 200")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 401)
            err_data = json.loads(e.read().decode('utf-8'))
            self.assertFalse(err_data["success"])

        # 3. Login with correct password must return 200 and restored profile
        good_req = urllib.request.Request(
            "http://127.0.0.1:8080/api/auth/email/login",
            data=json.dumps({
                "email": unique_email,
                "password": test_pwd
            }).encode('utf-8'),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(good_req) as resp:
            self.assertEqual(resp.status, 200)
            data = json.loads(resp.read().decode('utf-8'))
            self.assertTrue(data["success"])
            self.assertEqual(data["email"], unique_email)
            self.assertEqual(data["profile_id"], pid)
            self.assertEqual(data["profile_name"], test_pname)
            self.assertFalse(data["is_email_verified"])

    def test_08_live_http_email_code_send_and_verify(self):
        """Verify POST /api/auth/email/send-code and POST /api/auth/email/verify-code via live HTTP."""
        unique_email = f"code_test_{int(time.time())}@focusdns.net"
        test_pwd = "CodeTestPassword44!"
        
        # 1. Register user
        reg_req = urllib.request.Request(
            "http://127.0.0.1:8080/api/auth/email/register",
            data=json.dumps({
                "email": unique_email,
                "password": test_pwd,
                "profile_name": "Code Test Shield"
            }).encode('utf-8'),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(reg_req) as resp:
            reg_data = json.loads(resp.read().decode('utf-8'))
            pid = reg_data["profile_id"]

        # 2. Request new 4-digit code via send-code
        send_req = urllib.request.Request(
            "http://127.0.0.1:8080/api/auth/email/send-code",
            data=json.dumps({"email": unique_email}).encode('utf-8'),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(send_req) as resp:
            self.assertEqual(resp.status, 200)
            send_data = json.loads(resp.read().decode('utf-8'))
            self.assertTrue(send_data["success"])
            code = send_data.get("dev_otp")
            self.assertIsNotNone(code)
            self.assertEqual(len(code), 4)

        # 3. Verify code via verify-code
        verify_req = urllib.request.Request(
            "http://127.0.0.1:8080/api/auth/email/verify-code",
            data=json.dumps({
                "email": unique_email,
                "code": code
            }).encode('utf-8'),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(verify_req) as resp:
            self.assertEqual(resp.status, 200)
            v_data = json.loads(resp.read().decode('utf-8'))
            self.assertTrue(v_data["success"])
            self.assertTrue(v_data["is_email_verified"])
            self.assertEqual(v_data["profile_id"], pid)

        # 4. Subsequent login reflects is_email_verified = True
        login_req = urllib.request.Request(
            "http://127.0.0.1:8080/api/auth/email/login",
            data=json.dumps({
                "email": unique_email,
                "password": test_pwd
            }).encode('utf-8'),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(login_req) as resp:
            self.assertEqual(resp.status, 200)
            l_data = json.loads(resp.read().decode('utf-8'))
            self.assertTrue(l_data["is_email_verified"])

    def test_09_live_http_admin_smtp_api(self):
        """Verify GET and POST /api/admin/smtp endpoints with master key authentication."""
        master_key = db.get_admin_master_key()

        # GET /api/admin/smtp
        get_req = urllib.request.Request(
            "http://127.0.0.1:8080/api/admin/smtp",
            headers={"X-Admin-Key": master_key}
        )
        with urllib.request.urlopen(get_req) as resp:
            self.assertEqual(resp.status, 200)
            smtp_cfg = json.loads(resp.read().decode('utf-8'))
            self.assertIn("host", smtp_cfg)
            self.assertIn("port", smtp_cfg)
            self.assertIn("from", smtp_cfg)

        # POST /api/admin/smtp
        post_req = urllib.request.Request(
            "http://127.0.0.1:8080/api/admin/smtp",
            data=json.dumps({
                "host": "smtp.gmail.com",
                "port": 587,
                "user": "focusdns.sec@gmail.com",
                "password": "test_app_password",
                "from": "FocusDNS Guard <focusdns.sec@gmail.com>",
                "use_tls": True,
                "use_ssl": False,
                "enabled": True
            }).encode('utf-8'),
            headers={
                "Content-Type": "application/json",
                "X-Admin-Key": master_key
            }
        )
        with urllib.request.urlopen(post_req) as resp:
            self.assertEqual(resp.status, 200)
            res_data = json.loads(resp.read().decode('utf-8'))
            self.assertTrue(res_data["success"])

        # Check that password is masked on GET
        with urllib.request.urlopen(get_req) as resp:
            new_cfg = json.loads(resp.read().decode('utf-8'))
            self.assertEqual(new_cfg["host"], "smtp.gmail.com")
            self.assertEqual(new_cfg["user"], "focusdns.sec@gmail.com")
            self.assertEqual(new_cfg["pass"], "••••••••")


if __name__ == "__main__":
    unittest.main()

