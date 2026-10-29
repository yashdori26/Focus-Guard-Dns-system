"""
Unit Test Suite for FocusDNS Enterprise - Hierarchical RBAC & Audit Hash Chaining.
Validates role tiers, permission boundaries, strict mode / conditional whitelisting,
cryptographic session tokens, and tamper-evident SHA-256 audit ledger.
"""

import time
import unittest
from server.enterprise.rbac_engine import (
    RbacEngine,
    RoleTier,
    Permission,
    EnterpriseUser,
    AuditLogEntry
)


class TestEnterpriseRbac(unittest.TestCase):

    def setUp(self):
        self.rbac = RbacEngine(secret_key="Test-Enterprise-Secret-Key-32Bytes")

    def test_default_super_admin_authentication(self):
        """Verifies default Super Admin can log in and receives signed token."""
        res = self.rbac.authenticate("superadmin", "admin123")
        self.assertIsNotNone(res)
        user, token = res  # type: ignore
        self.assertEqual(user.role, RoleTier.SUPER_ADMIN)
        self.assertEqual(user.tenant_id, "global")

        verified = self.rbac.verify_session_token(token)
        self.assertIsNotNone(verified)
        self.assertEqual(verified.user_id, user.user_id)

    def test_invalid_credentials_rejected(self):
        """Rejects bad credentials and records audit failure."""
        res = self.rbac.authenticate("superadmin", "wrong_password")
        self.assertIsNone(res)

        trail = self.rbac.get_audit_trail(limit=5)
        self.assertTrue(any(e["action"] == "AUTH_LOGIN_FAIL" for e in trail))

    def test_hierarchical_role_permissions(self):
        """Enforces granular permissions across role tiers."""
        # 1. Compliance Auditor (Strictly Read-Only)
        auditor = self.rbac.register_user(
            username="auditor_jane",
            email="jane@auditor.org",
            password="secure_password",
            role=RoleTier.COMPLIANCE_AUDITOR,
            tenant_id="org_acme"
        )
        self.assertTrue(self.rbac.authorize(auditor, Permission.VIEW_ANALYTICS, "org_acme"))
        self.assertTrue(self.rbac.authorize(auditor, Permission.EXPORT_COMPLIANCE, "org_acme"))
        self.assertTrue(self.rbac.authorize(auditor, Permission.AUDIT_LOG_READ, "org_acme"))
        # DENIED mutations
        self.assertFalse(self.rbac.authorize(auditor, Permission.UPDATE_POLICY, "org_acme"))
        self.assertFalse(self.rbac.authorize(auditor, Permission.MANAGE_FLEET, "org_acme"))
        self.assertFalse(self.rbac.authorize(auditor, Permission.OVERRIDE_FOCUS, "org_acme"))

        # 2. Team Lead
        team_lead = self.rbac.register_user(
            username="lead_bob",
            email="bob@acme.org",
            password="secure_password",
            role=RoleTier.TEAM_LEAD,
            tenant_id="org_acme",
            sub_tenant_ids=["unit_sales"]
        )
        self.assertTrue(self.rbac.authorize(team_lead, Permission.VIEW_ANALYTICS, "org_acme", "unit_sales"))
        self.assertTrue(self.rbac.authorize(team_lead, Permission.MANAGE_FLEET, "org_acme", "unit_sales"))
        self.assertFalse(self.rbac.authorize(team_lead, Permission.MANAGE_FLEET, "org_acme", "unit_engineering"))
        self.assertFalse(self.rbac.authorize(team_lead, Permission.MANAGE_USERS, "org_acme"))

    def test_multi_tenant_isolation_boundary(self):
        """Users from Org A cannot access Org B resources."""
        user_a = self.rbac.register_user(
            username="alice_a",
            email="alice@tenant-a.com",
            password="passwordA",
            role=RoleTier.ORG_ADMIN,
            tenant_id="org_alpha"
        )
        self.assertTrue(self.rbac.authorize(user_a, Permission.VIEW_ANALYTICS, "org_alpha"))
        # Cross-tenant access strictly denied
        self.assertFalse(self.rbac.authorize(user_a, Permission.VIEW_ANALYTICS, "org_beta"))

    def test_inviolable_conditional_whitelisting_law(self):
        """
        Confirms even Super-Admins cannot whitelist domains during locked focus sessions.
        Strictly raises PermissionError: ERROR_ACCESS_DENIED (5).
        """
        super_admin, _ = self.rbac.authenticate("superadmin", "admin123")  # type: ignore

        # 1. When Active Focus is Locked (timer > 0)
        with self.assertRaises(PermissionError) as ctx:
            self.rbac.check_whitelist_mutation(
                user=super_admin,
                target_tenant_id="org_acme",
                is_locked=True,
                countdown_seconds=1800
            )
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))
        self.assertIn("1800s remaining", str(ctx.exception))

        # 2. When Idle (is_locked=False & countdown=0): No exception
        try:
            self.rbac.check_whitelist_mutation(
                user=super_admin,
                target_tenant_id="org_acme",
                is_locked=False,
                countdown_seconds=0
            )
        except PermissionError:
            self.fail("check_whitelist_mutation raised PermissionError while idle!")

    def test_tamper_evident_sha256_audit_chain(self):
        """Verifies cryptographic hash chaining and tamper detection."""
        # Record series of administrative actions
        self.rbac.record_audit_event("usr_1", "ADMIN", "org_1", "CREATE_FLEET", "fleet/1", {"name": "cart_a"})
        self.rbac.record_audit_event("usr_2", "ADMIN", "org_1", "LOCK_FLEET", "fleet/1", {"duration": 3600})
        self.rbac.record_audit_event("usr_3", "ADMIN", "org_1", "UPDATE_POLICY", "fleet/1", {"ai_threat": True})

        # 1. Unbroken chain passes verification
        is_valid, err = self.rbac.verify_audit_chain()
        self.assertTrue(is_valid)
        self.assertIsNone(err)

        # 2. Maliciously modify a record in the chain
        self.rbac._audit_chain[1].details = {"duration": 0}  # Tamper with recorded lock duration

        # 3. Verification must detect tampered record
        is_valid_after_tamper, err_msg = self.rbac.verify_audit_chain()
        self.assertFalse(is_valid_after_tamper)
        self.assertIn("Tampered entry", str(err_msg))

    def test_session_token_tampering_and_expiry(self):
        """Rejects forged or expired session tokens."""
        user, token = self.rbac.authenticate("superadmin", "admin123")  # type: ignore

        # Forge token payload
        parts = token.rsplit(".", 1)
        forged_token = parts[0] + "xyz." + parts[1]
        self.assertIsNone(self.rbac.verify_session_token(forged_token))

        # Expired token
        expired_token = self.rbac.create_session_token(user, ttl_seconds=-10)
        self.assertIsNone(self.rbac.verify_session_token(expired_token))


if __name__ == "__main__":
    unittest.main()
