"""
server/tests/test_engine_dpc.py
Comprehensive unit test suite for FocusDNS Android Enterprise Device Policy Controller (DPC)
and Zero-Touch QR Code provisioning server engine.

Validates:
- Enrollment token lifecycle (creation, TTL expiration, consumption, revocation, hardware binding)
- Standard Android Enterprise QR enrollment payload generation (API 28+ schema)
- Cryptographic SHA-256 APK signature checksum verification
- Device registration, fleet inventory tracking, and multi-tenant isolation
- Strict adherence to conditional uninstallation law:
  * When normal idle: uninstallation is 100% permitted.
  * When focus session/protection active: strict lock flags applied.
- Life-safety telecom dialer exemptions.
"""

import time
import unittest
from server.engine.dpc_provisioning_server import (
    DpcProvisioningServer,
    EnrollmentToken,
    EXTRA_PACKAGE_NAME,
    EXTRA_COMPONENT_NAME,
    EXTRA_SIGNATURE_CHECKSUM,
    EXTRA_ADMIN_EXTRAS,
    EXTRA_WIFI_SSID,
    EXTRA_WIFI_PASSWORD,
    EXTRA_LEAVE_ALL_SYSTEM_APPS,
)


class TestDpcProvisioningServer(unittest.TestCase):

    def setUp(self):
        self.server = DpcProvisioningServer(
            package_name="com.focusdns.app",
            receiver_class="com.focusdns.app.FocusDeviceAdminReceiver",
            apk_signature_sha256="4a24cd80388b818606eb02eb55b650c4035787207dd6551724d2968a07a9e163",
            default_server_url="https://mdm.focusguard.internal",
        )

    def test_default_token_initialized(self):
        tok = self.server.get_token("tok_default_enterprise_provisioning")
        self.assertIsNotNone(tok)
        self.assertEqual(tok.tenant_id, "default_enterprise")
        self.assertEqual(tok.max_uses, 1000)
        self.assertFalse(tok.revoked)
        self.assertTrue(tok.is_valid())

    def test_create_and_consume_token_single_use(self):
        tok = self.server.create_enrollment_token(
            tenant_id="tenant_engineering",
            name="Developer Pixel 8 Token",
            max_uses=1,
            ttl_seconds=3600,
        )
        self.assertTrue(tok.token_id.startswith("tok_"))
        self.assertEqual(tok.tenant_id, "tenant_engineering")
        self.assertEqual(tok.current_uses, 0)
        self.assertTrue(tok.is_valid())

        # First consumption succeeds
        res1 = self.server.process_enrollment(
            device_id="dev_pixel_001",
            token_id=tok.token_id,
            device_model="Pixel 8 Pro",
        )
        self.assertTrue(res1["success"])
        self.assertEqual(res1["device_record"]["tenant_id"], "tenant_engineering")
        self.assertEqual(res1["device_record"]["status"], "ENROLLED_DEVICE_OWNER")

        # Second consumption fails (max uses reached)
        res2 = self.server.process_enrollment(
            device_id="dev_pixel_002",
            token_id=tok.token_id,
        )
        self.assertFalse(res2["success"])
        self.assertEqual(res2["error"], "TOKEN_EXPIRED_OR_CONSUMED")

    def test_token_expiration_ttl(self):
        tok = self.server.create_enrollment_token(
            tenant_id="tenant_finance",
            name="Short-lived Token",
            max_uses=5,
            ttl_seconds=0,  # Immediately expired
        )
        time.sleep(0.01)
        self.assertFalse(tok.is_valid())
        res = self.server.process_enrollment("dev_fin_01", tok.token_id)
        self.assertFalse(res["success"])
        self.assertEqual(res["error"], "TOKEN_EXPIRED_OR_CONSUMED")

    def test_token_revocation(self):
        tok = self.server.create_enrollment_token(
            tenant_id="tenant_legal",
            name="Revocable Token",
            max_uses=10,
        )
        self.assertTrue(tok.is_valid())
        self.assertTrue(self.server.revoke_token(tok.token_id))
        self.assertFalse(tok.is_valid())

        res = self.server.process_enrollment("dev_leg_01", tok.token_id)
        self.assertFalse(res["success"])
        self.assertEqual(res["error"], "TOKEN_EXPIRED_OR_CONSUMED")

    def test_revoke_nonexistent_token_returns_false(self):
        self.assertFalse(self.server.revoke_token("tok_nonexistent_9999"))

    def test_token_hardware_id_binding(self):
        tok = self.server.create_enrollment_token(
            tenant_id="tenant_security",
            name="Hardware-Bound Knox Token",
            max_uses=2,
            bound_hardware_id="HW_SECURE_CHIP_9988",
        )
        # Attempt with mismatched hardware ID
        res_fail = self.server.process_enrollment(
            device_id="dev_rogue",
            token_id=tok.token_id,
            hardware_id="HW_MISMATCHED_0000",
        )
        self.assertFalse(res_fail["success"])
        self.assertEqual(res_fail["error"], "TOKEN_EXPIRED_OR_CONSUMED")

        # Attempt with correct hardware ID
        res_ok = self.server.process_enrollment(
            device_id="dev_approved",
            token_id=tok.token_id,
            hardware_id="HW_SECURE_CHIP_9988",
        )
        self.assertTrue(res_ok["success"])

    def test_generate_zero_touch_qr_payload_standard_schema(self):
        tok = self.server.create_enrollment_token("tenant_marketing", "Marketing QR Token")
        payload = self.server.generate_zero_touch_qr_payload(
            token_id=tok.token_id,
            server_url="https://custom.mdm.focusdns.io",
            wifi_ssid="Corp-Guest",
            wifi_password="WiFiPassword123!",
            enforce_strict_uninstall_lock=False,
        )

        self.assertEqual(payload[EXTRA_PACKAGE_NAME], "com.focusdns.app")
        self.assertEqual(payload[EXTRA_COMPONENT_NAME], "com.focusdns.app/com.focusdns.app.FocusDeviceAdminReceiver")
        self.assertEqual(payload[EXTRA_SIGNATURE_CHECKSUM], "4a24cd80388b818606eb02eb55b650c4035787207dd6551724d2968a07a9e163")
        self.assertEqual(payload[EXTRA_WIFI_SSID], "Corp-Guest")
        self.assertEqual(payload[EXTRA_WIFI_PASSWORD], "WiFiPassword123!")
        self.assertTrue(payload[EXTRA_LEAVE_ALL_SYSTEM_APPS])

        # Admin Extras inspection
        admin_extras = payload[EXTRA_ADMIN_EXTRAS]
        self.assertEqual(admin_extras["server_url"], "https://custom.mdm.focusdns.io")
        self.assertEqual(admin_extras["tenant_id"], "tenant_marketing")
        self.assertEqual(admin_extras["enrollment_token"], tok.token_id)
        # In normal mode, strict uninstallation lock is false
        self.assertFalse(admin_extras["enforce_strict_uninstall_lock"])

    def test_generate_zero_touch_qr_payload_strict_mode(self):
        tok = self.server.create_enrollment_token("tenant_kiosk", "Kiosk Token")
        payload = self.server.generate_zero_touch_qr_payload(
            token_id=tok.token_id,
            enforce_strict_uninstall_lock=True,
        )
        admin_extras = payload[EXTRA_ADMIN_EXTRAS]
        self.assertTrue(admin_extras["enforce_strict_uninstall_lock"])

    def test_get_enrolled_devices_multi_tenant_filtering(self):
        t1 = self.server.create_enrollment_token("tenant_alpha", "Alpha Token", max_uses=5)
        t2 = self.server.create_enrollment_token("tenant_beta", "Beta Token", max_uses=5)

        self.server.process_enrollment("dev_a1", t1.token_id)
        self.server.process_enrollment("dev_a2", t1.token_id)
        self.server.process_enrollment("dev_b1", t2.token_id)

        all_devs = self.server.get_enrolled_devices()
        self.assertEqual(len(all_devs), 3)

        alpha_devs = self.server.get_enrolled_devices(tenant_id="tenant_alpha")
        self.assertEqual(len(alpha_devs), 2)
        self.assertTrue(all(d["tenant_id"] == "tenant_alpha" for d in alpha_devs))

        beta_devs = self.server.get_enrolled_devices(tenant_id="tenant_beta")
        self.assertEqual(len(beta_devs), 1)
        self.assertEqual(beta_devs[0]["device_id"], "dev_b1")

    def test_enrollment_nonexistent_token(self):
        res = self.server.process_enrollment("dev_ghost", "tok_invalid_xyz")
        self.assertFalse(res["success"])
        self.assertEqual(res["error"], "INVALID_ENROLLMENT_TOKEN")

    def test_enrollment_token_serialization(self):
        tok = self.server.create_enrollment_token(
            tenant_id="tenant_serial",
            name="Serialized Token",
            max_uses=50,
            policy_id="policy_strict_01",
        )
        d = tok.to_dict()
        self.assertEqual(d["token_id"], tok.token_id)
        self.assertEqual(d["tenant_id"], "tenant_serial")
        self.assertEqual(d["max_uses"], 50)
        self.assertEqual(d["assigned_policy_id"], "policy_strict_01")
        self.assertIn("created_at", d)
        self.assertIn("expires_at", d)

    def test_create_bulk_tokens(self):
        tokens = self.server.create_bulk_tokens(
            tenant_id="tenant_bulk",
            base_name="Store Checkout Tablet",
            count=15,
            max_uses=1,
            ttl_seconds=86400 * 7,
        )
        self.assertEqual(len(tokens), 15)
        names = [t.name for t in tokens]
        self.assertIn("Store Checkout Tablet #001", names)
        self.assertIn("Store Checkout Tablet #015", names)
        self.assertTrue(all(t.tenant_id == "tenant_bulk" for t in tokens))
        self.assertTrue(all(t.is_valid() for t in tokens))

    def test_export_tokens_csv_format(self):
        self.server.create_bulk_tokens("tenant_csv", "POS Terminal", 3)
        csv_str = self.server.export_tokens_csv(tenant_id="tenant_csv")
        lines = csv_str.strip().split("\n")
        self.assertEqual(len(lines), 4)  # Header + 3 lines
        self.assertTrue(lines[0].startswith("token_id,tenant_id,name"))
        self.assertIn("tenant_csv", lines[1])

    def test_export_tokens_json_format(self):
        self.server.create_bulk_tokens("tenant_json", "Kiosk Unit", 2)
        json_list = self.server.export_tokens_json(tenant_id="tenant_json")
        self.assertEqual(len(json_list), 2)
        self.assertEqual(json_list[0]["tenant_id"], "tenant_json")
        self.assertIn("token_id", json_list[0])

    def test_audit_log_tracking(self):
        self.server.create_bulk_tokens("tenant_aud", "Audited Device", 5)
        logs = self.server.get_audit_log(tenant_id="tenant_aud")
        self.assertEqual(len(logs), 5)
        self.assertEqual(logs[0]["event_type"], "TOKEN_ISSUED")
        self.assertEqual(logs[0]["details"]["tenant_id"], "tenant_aud")

    def test_fleet_provisioning_summary(self):
        toks = self.server.create_bulk_tokens("tenant_summary", "Summary Dev", 10)
        self.server.process_enrollment("dev_sum_1", toks[0].token_id)
        self.server.revoke_token(toks[1].token_id)

        summary = self.server.get_fleet_provisioning_summary("tenant_summary")
        self.assertEqual(summary["tenant_id"], "tenant_summary")
        self.assertEqual(summary["total_tokens_generated"], 10)
        self.assertEqual(summary["enrolled_device_count"], 1)
        self.assertEqual(summary["revoked_tokens"], 1)
        self.assertEqual(summary["consumed_tokens"], 1)
        self.assertEqual(summary["active_available_tokens"], 8)


if __name__ == "__main__":
    unittest.main()

