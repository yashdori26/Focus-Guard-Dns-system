"""
Unit Test Suite for FocusDNS Enterprise - Tenant & Fleet Relational Manager.
Validates multi-tenant nesting, device enrollment tokens, quota enforcement,
fleet locking, and the Conditional Whitelisting Law.
"""

import os
import tempfile
import time
import unittest
from server.enterprise.tenant_manager import (
    TenantManager,
    Organization,
    TenantUnit,
    DeviceFleet,
    TenantQuota
)


class TestEnterpriseTenantManager(unittest.TestCase):

    def setUp(self):
        self.temp_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        self.temp_db.close()
        self.tm = TenantManager(db_path=self.temp_db.name)

    def tearDown(self):
        if os.path.exists(self.temp_db.name):
            os.unlink(self.temp_db.name)

    def test_organization_crud_and_quota(self):
        """Creates and retrieves top-level enterprise organization."""
        quota = TenantQuota(max_devices=100, max_qps=2000, retention_days=30)
        org = self.tm.create_organization(
            name="Springfield School District",
            domain="springfield.edu",
            plan_tier="EDUCATION",
            quota=quota
        )
        self.assertTrue(org.org_id.startswith("org_"))
        self.assertEqual(org.name, "Springfield School District")

        fetched = self.tm.get_organization(org.org_id)
        self.assertIsNotNone(fetched)
        self.assertEqual(fetched.quota.max_devices, 100)

    def test_tenant_unit_hierarchy(self):
        """Provisions sub-tenant units linked to parent organization."""
        org = self.tm.create_organization("Acme Corp", "acme.com")
        unit_1 = self.tm.create_tenant_unit(org.org_id, "Lincoln High School", "SCHOOL")
        unit_2 = self.tm.create_tenant_unit(org.org_id, "Jefferson Middle School", "SCHOOL")

        units = self.tm.list_tenant_units(org.org_id)
        self.assertEqual(len(units), 2)
        unit_names = {u.name for u in units}
        self.assertIn("Lincoln High School", unit_names)
        self.assertIn("Jefferson Middle School", unit_names)

    def test_fleet_creation_and_lock_whitelisting_law(self):
        """
        Validates fleet creation and the Conditional Whitelisting Law:
        Strictly raises PermissionError: ERROR_ACCESS_DENIED (5) when fleet is locked.
        """
        org = self.tm.create_organization("Acme Corp", "acme.com")
        unit = self.tm.create_tenant_unit(org.org_id, "Grade 4")
        fleet = self.tm.create_device_fleet(org.org_id, unit.unit_id, "Chromebook Cart A", "CHROMEOS")

        # 1. Idle mode: Whitelisting allowed
        self.assertTrue(self.tm.modify_fleet_whitelist(fleet.fleet_id, "khanacademy.org"))

        # 2. Lock fleet for 1800s
        locked_fleet = self.tm.lock_fleet(fleet.fleet_id, 1800)
        self.assertTrue(locked_fleet.is_locked)
        self.assertGreater(locked_fleet.remaining_lock_seconds, 1700)

        # 3. Whitelist attempt during locked session MUST FAIL
        with self.assertRaises(PermissionError) as ctx:
            self.tm.modify_fleet_whitelist(fleet.fleet_id, "youtube.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

        # 4. Unlock fleet
        unlocked_fleet = self.tm.unlock_fleet(fleet.fleet_id)
        self.assertFalse(unlocked_fleet.is_locked)
        self.assertTrue(self.tm.modify_fleet_whitelist(fleet.fleet_id, "youtube.com"))

    def test_device_enrollment_tokens_and_quota_cap(self):
        """Generates device enrollment tokens and enforces maximum device limits."""
        quota = TenantQuota(max_devices=2)  # Quota capped at 2 devices
        org = self.tm.create_organization("Small Business", "smallbiz.com", quota=quota)
        unit = self.tm.create_tenant_unit(org.org_id, "Main Office")
        fleet = self.tm.create_device_fleet(org.org_id, unit.unit_id, "Laptops")

        token = self.tm.generate_enrollment_token(org.org_id, unit.unit_id, fleet.fleet_id, max_uses=5)
        self.assertTrue(token.startswith("enr_"))

        # Enroll Device 1
        dev1 = self.tm.validate_and_consume_enrollment(token)
        self.assertIsNotNone(dev1)

        # Enroll Device 2
        dev2 = self.tm.validate_and_consume_enrollment(token)
        self.assertIsNotNone(dev2)

        # Enroll Device 3 (Must fail due to max_devices = 2 quota cap)
        dev3 = self.tm.validate_and_consume_enrollment(token)
        self.assertIsNone(dev3, "Enrolled device beyond organization quota limit!")

    def test_expired_enrollment_token_rejected(self):
        """Rejects enrollment tokens that have passed their expiration deadline."""
        org = self.tm.create_organization("Acme Corp", "acme.com")
        unit = self.tm.create_tenant_unit(org.org_id, "Office")
        fleet = self.tm.create_device_fleet(org.org_id, unit.unit_id, "Tablets")

        # Expired token (ttl = -10 seconds)
        expired_token = self.tm.generate_enrollment_token(org.org_id, unit.unit_id, fleet.fleet_id, ttl_seconds=-10)
        res = self.tm.validate_and_consume_enrollment(expired_token)
        self.assertIsNone(res)


if __name__ == "__main__":
    unittest.main()
