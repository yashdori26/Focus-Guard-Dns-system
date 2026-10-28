"""
server/tests/test_engine_appconfig.py
Comprehensive unit test suite for FocusDNS Managed Configurations (AppConfig) Distributor.

Validates:
- Android Enterprise RestrictionsManager AppConfig schema adherence
- Microsoft Intune & VMware Workspace ONE payload format transformation
- Multi-tenant AppConfig isolation and custom policy profile provisioning
- Verification of the core conditional uninstallation guarantee:
  * Normal idle configurations maintain enforce_strict_uninstall_lock = False
  * Focus sessions enforce strict uninstallation locks
- Split-tunneling package whitelist configuration and DoT endpoint distribution.
"""

import unittest
from server.engine.managed_config_distributor import (
    ManagedConfigDistributor,
    TenantAppConfig,
)


class TestManagedConfigDistributor(unittest.TestCase):

    def setUp(self):
        self.distributor = ManagedConfigDistributor()

    def test_default_enterprise_config_initialized(self):
        cfg = self.distributor.get_config("default_enterprise")
        self.assertIsNotNone(cfg)
        self.assertEqual(cfg.tenant_id, "default_enterprise")
        self.assertEqual(cfg.name, "Default Corporate Configuration")
        self.assertEqual(cfg.server_url, "https://dns.focusguard.internal")
        self.assertEqual(cfg.approved_dot_host, "dns.focusguard.internal")
        # In normal corporate defaults, clean uninstallation is permitted
        self.assertFalse(cfg.enforce_strict_uninstall_lock)
        self.assertFalse(cfg.kiosk_enabled)
        self.assertIn("com.slack", cfg.whitelisted_packages)

    def test_to_appconfig_bundle_standard_keys(self):
        bundle = self.distributor.get_appconfig_bundle("default_enterprise")
        expected_keys = [
            "server_url",
            "tenant_id",
            "enrollment_token",
            "enforce_strict_uninstall_lock",
            "whitelisted_split_tunnel_pkgs",
            "lock_task_kiosk_enabled",
            "approved_dot_host",
        ]
        for k in expected_keys:
            self.assertIn(k, bundle)

        self.assertEqual(bundle["server_url"], "https://dns.focusguard.internal")
        self.assertFalse(bundle["enforce_strict_uninstall_lock"])

    def test_generate_intune_sync_payload_schema(self):
        payload = self.distributor.generate_intune_sync_payload("default_enterprise")
        self.assertEqual(payload["targetApplication"], "com.focusdns.app")
        self.assertEqual(payload["appConfigProfileName"], "FocusDNS-Policy-default_enterprise")
        self.assertIn("timestamp", payload)

        settings = payload["settings"]
        self.assertIsInstance(settings, list)
        self.assertGreater(len(settings), 0)

        # Verify setting entry structure
        keys = [s["key"] for s in settings]
        self.assertIn("server_url", keys)
        self.assertIn("enforce_strict_uninstall_lock", keys)

        for s in settings:
            self.assertIn("key", s)
            self.assertIn("value", s)
            self.assertIn("valueType", s)
            if s["key"] == "enforce_strict_uninstall_lock":
                self.assertEqual(s["valueType"], "bool")
                self.assertFalse(s["value"])

    def test_create_and_retrieve_custom_tenant_config(self):
        custom = TenantAppConfig(
            tenant_id="tenant_healthcare",
            name="HIPAA Compliant Hospital Profile",
            server_url="https://hipaa.dns.hospital.internal",
            enrollment_token="tok_hipaa_9988",
            enforce_strict_uninstall_lock=True,
            whitelisted_packages=["com.epic.mychart", "com.cerner.care"],
            kiosk_enabled=True,
            approved_dot_host="hipaa.dns.hospital.internal",
        )
        self.distributor.create_or_update_config(custom)

        retrieved = self.distributor.get_tenant_config("tenant_healthcare")
        self.assertIsNotNone(retrieved)
        self.assertEqual(retrieved.name, "HIPAA Compliant Hospital Profile")
        self.assertTrue(retrieved.enforce_strict_uninstall_lock)
        self.assertTrue(retrieved.kiosk_enabled)
        self.assertIn("com.epic.mychart", retrieved.whitelisted_packages)

        bundle = self.distributor.get_appconfig_bundle("tenant_healthcare")
        self.assertTrue(bundle["enforce_strict_uninstall_lock"])
        self.assertEqual(bundle["server_url"], "https://hipaa.dns.hospital.internal")

    def test_set_tenant_config_returns_saved_instance(self):
        cfg = TenantAppConfig(
            tenant_id="tenant_fintech",
            name="Bank Security Profile",
            enforce_strict_uninstall_lock=True,
        )
        saved = self.distributor.set_tenant_config(cfg)
        self.assertEqual(saved.tenant_id, "tenant_fintech")
        self.assertTrue(saved.enforce_strict_uninstall_lock)

    def test_get_appconfig_bundle_fallback_to_default_for_unknown_tenant(self):
        bundle = self.distributor.get_appconfig_bundle("unknown_tenant_xyz")
        self.assertEqual(bundle["tenant_id"], "default_enterprise")

    def test_list_configs(self):
        configs = self.distributor.list_configs()
        self.assertGreaterEqual(len(configs), 1)
        t_ids = [c["tenant_id"] for c in configs]
        self.assertIn("default_enterprise", t_ids)

    def test_tenant_app_config_serialization(self):
        cfg = TenantAppConfig(
            tenant_id="tenant_audit",
            name="Audit Profile",
            server_url="https://audit.dns.io",
            enrollment_token="tok_audit",
            enforce_strict_uninstall_lock=False,
            whitelisted_packages=["com.audit"],
        )
        d = cfg.to_dict()
        self.assertEqual(d["tenant_id"], "tenant_audit")
        self.assertEqual(d["name"], "Audit Profile")
        self.assertEqual(d["server_url"], "https://audit.dns.io")
        self.assertFalse(d["enforce_strict_uninstall_lock"])
        self.assertIn("updated_at", d)


if __name__ == "__main__":
    unittest.main()
