"""
Unit Test Suite for FocusDNS Enterprise - Fleet Policy Compiler.
Validates multi-tiered inheritance, strictest-rule conflict resolution,
inviolable life safety domain preservation, and bundle signatures.
"""

import time
import unittest
from server.enterprise.tenant_manager import Organization, TenantUnit, DeviceFleet
from server.enterprise.fleet_policy_compiler import FleetPolicyCompiler, CompiledFleetPolicy


class TestEnterprisePolicyCompiler(unittest.TestCase):

    def setUp(self):
        self.compiler = FleetPolicyCompiler()
        self.org = Organization("org_enterprise", "Global Enterprise", "enterprise.com")
        self.unit = TenantUnit("unit_finance", self.org.org_id, "Finance Dept")
        self.fleet = DeviceFleet("flt_accounting", self.unit.unit_id, self.org.org_id, "Accounting Laptops")

    def test_multi_tier_category_inheritance_strictest_wins(self):
        """Child fleet inherits blocks from Organization and Tenant Unit."""
        org_policy = {"blocked_categories": ["GAMBLING", "ADULT"]}
        unit_policy = {"blocked_categories": ["SOCIAL_MEDIA"]}
        fleet_policy = {"blocked_categories": ["GAMING"]}

        compiled = self.compiler.compile(
            self.org, self.unit, self.fleet,
            org_policy=org_policy,
            unit_policy=unit_policy,
            fleet_policy=fleet_policy
        )

        expected_cats = {"GAMBLING", "ADULT", "SOCIAL_MEDIA", "GAMING"}
        self.assertEqual(compiled.blocked_categories, expected_cats)

    def test_inviolable_life_safety_purge(self):
        """
        Compiler strictly purges emergency services and system updates
        if mistakenly included in custom blocklists.
        """
        dangerous_policy = {
            "blocked_domains": [
                "malware-portal.xyz",
                "911.gov",                # Emergency calling (Must be purged!)
                "112.gov",                # Emergency calling (Must be purged!)
                "update.microsoft.com",   # Windows Update (Must be purged!)
                "push.apple.com"          # APNs Push (Must be purged!)
            ]
        }
        compiled = self.compiler.compile(
            self.org, self.unit, self.fleet,
            org_policy=dangerous_policy
        )

        # Only malware-portal.xyz should remain in blocked_domains
        self.assertIn("malware-portal.xyz", compiled.blocked_domains)
        self.assertNotIn("911.gov", compiled.blocked_domains)
        self.assertNotIn("112.gov", compiled.blocked_domains)
        self.assertNotIn("update.microsoft.com", compiled.blocked_domains)
        self.assertNotIn("push.apple.com", compiled.blocked_domains)

        # Direct evaluation check
        is_blocked, reason = compiled.is_domain_blocked("911.gov")
        self.assertFalse(is_blocked)
        self.assertEqual(reason, "LIFE_SAFETY_EXEMPT")

    def test_org_block_trumps_child_whitelist(self):
        """A fleet cannot whitelist a domain that is blocked at Organization level."""
        org_policy = {"blocked_domains": ["tiktok.com"]}
        fleet_policy = {"whitelisted_domains": ["tiktok.com", "legit-tool.com"]}

        compiled = self.compiler.compile(
            self.org, self.unit, self.fleet,
            org_policy=org_policy,
            fleet_policy=fleet_policy
        )
        self.assertNotIn("tiktok.com", compiled.whitelisted_domains)
        self.assertIn("legit-tool.com", compiled.whitelisted_domains)

    def test_compiled_bundle_signature(self):
        """Verifies deterministic SHA-256 signature calculation."""
        compiled = self.compiler.compile(self.org, self.unit, self.fleet)
        self.assertTrue(bool(compiled.signature))
        self.assertEqual(len(compiled.signature), 64)


if __name__ == "__main__":
    unittest.main()
