"""
FocusDNS Enterprise Engine - SCIM 2.0 Directory Sync & SAML/OIDC SSO Unit Tests.

Tests:
  1. RFC 7644 SCIM 2.0 /ServiceProviderConfig and /Users provisioning.
  2. IdP Group-to-Role mappings (FocusDNS-Teachers -> TEACHER_PARENT).
  3. Immediate Session Revocation Law: Disabling a user purges all active JWT sessions.
  4. SCIM 2.0 User deprovisioning (DELETE /Users/{id}).
  5. SAML 2.0 XML assertion validation with JIT enrollment.
  6. OpenID Connect (OIDC) JWT validation (claims, audience, expiration, HMAC signature).
"""

import base64
import hashlib
import hmac
import json
import time
import unittest

from server.enterprise.rbac_engine import RbacEngine, RoleTier
from server.enterprise.scim_directory_sync import (
    ScimDirectorySyncEngine,
    SCIM_USER_SCHEMA,
    SCIM_GROUP_SCHEMA,
)
from server.enterprise.saml_oidc_authenticator import (
    SamlOidcAuthenticator,
    SamlIdentityProviderConfig,
    OidcProviderConfig,
)


class TestScimDirectorySync(unittest.TestCase):
    """Verifies RFC 7643 / RFC 7644 SCIM 2.0 Identity Server operations."""

    def setUp(self):
        self.rbac = RbacEngine()
        self.scim = ScimDirectorySyncEngine(rbac_engine=self.rbac, default_org_id="org_test")

    def test_service_provider_config(self):
        config = self.scim.get_service_provider_config()
        self.assertIn("schemas", config)
        self.assertTrue(config["patch"]["supported"])
        self.assertFalse(config["bulk"]["supported"])
        self.assertTrue(config["filter"]["supported"])

    def test_create_and_get_user(self):
        payload = {
            "schemas": [SCIM_USER_SCHEMA],
            "userName": "alice.teacher@springfield.k12.us",
            "displayName": "Alice Teacher",
            "emails": [{"value": "alice.teacher@springfield.k12.us", "primary": True}],
            "active": True,
            "groups": [{"display": "FocusDNS-Teachers"}],
        }

        status, res = self.scim.create_user(payload)
        self.assertEqual(status, 201)
        user_id = res["id"]
        self.assertTrue(user_id.startswith("usr_"))
        self.assertEqual(res["userName"], "alice.teacher@springfield.k12.us")

        # Verify user was enrolled in RBAC Engine with mapped TEACHER_PARENT role
        rbac_user = self.rbac.get_user(user_id)
        self.assertIsNotNone(rbac_user)
        self.assertEqual(rbac_user.role, RoleTier.TEACHER_PARENT)
        self.assertIn("unit_teachers", rbac_user.sub_tenant_ids)

        # Retrieve user via SCIM GET
        fetched = self.scim.get_user(user_id)
        self.assertIsNotNone(fetched)
        self.assertEqual(fetched["id"], user_id)

    def test_duplicate_user_conflict(self):
        payload = {
            "schemas": [SCIM_USER_SCHEMA],
            "userName": "bob@springfield.k12.us",
            "emails": [{"value": "bob@springfield.k12.us", "primary": True}],
        }
        status1, _ = self.scim.create_user(payload)
        self.assertEqual(status1, 201)

        # Duplicate email returns 409
        status2, res2 = self.scim.create_user(payload)
        self.assertEqual(status2, 409)

    def test_list_users_pagination(self):
        for i in range(5):
            self.scim.create_user({
                "userName": f"user{i}@test.com",
                "emails": [{"value": f"user{i}@test.com", "primary": True}],
            })

        list_res = self.scim.list_users(start_index=1, count=3)
        self.assertEqual(list_res["totalResults"], 5)
        self.assertEqual(list_res["startIndex"], 1)
        self.assertEqual(list_res["itemsPerPage"], 3)
        self.assertEqual(len(list_res["Resources"]), 3)

    def test_patch_user_active_false_revokes_sessions(self):
        # 1. Create User
        _, user_res = self.scim.create_user({
            "userName": "revokeme@test.com",
            "emails": [{"value": "revokeme@test.com", "primary": True}],
        })
        user_id = user_res["id"]

        # 2. Simulate Active Login Session in RBAC Engine
        token = self.rbac.create_session_token(self.rbac.get_user(user_id))
        self.assertIn(token, self.rbac._active_sessions)

        # 3. Apply SCIM PATCH active: false
        patch_payload = {
            "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
            "Operations": [
                {
                    "op": "replace",
                    "path": "active",
                    "value": False
                }
            ]
        }
        status, updated = self.scim.patch_user(user_id, patch_payload)
        self.assertEqual(status, 200)
        self.assertFalse(updated["active"])

        # 4. Immediate Session Revocation Check: Token must be purged!
        self.assertNotIn(token, self.rbac._active_sessions)
        self.assertIsNone(self.rbac.verify_session_token(token))

    def test_delete_user_deprovisions_account(self):
        _, user_res = self.scim.create_user({
            "userName": "todelete@test.com",
            "emails": [{"value": "todelete@test.com", "primary": True}],
        })
        user_id = user_res["id"]

        status, _ = self.scim.delete_user(user_id)
        self.assertEqual(status, 204)
        self.assertIsNone(self.scim.get_user(user_id))

    def test_create_group_updates_member_roles(self):
        # Create unprivileged user
        _, user_res = self.scim.create_user({
            "userName": "auditor@test.com",
            "emails": [{"value": "auditor@test.com", "primary": True}],
        })
        user_id = user_res["id"]
        rbac_user = self.rbac.get_user(user_id)
        self.assertEqual(rbac_user.role, RoleTier.TEAM_LEAD)

        # Create SCIM Group mapped to FocusDNS-Auditors
        group_payload = {
            "schemas": [SCIM_GROUP_SCHEMA],
            "displayName": "FocusDNS-Auditors",
            "members": [{"value": user_id, "display": "auditor@test.com"}],
        }
        status, _ = self.scim.create_group(group_payload)
        self.assertEqual(status, 201)

        # Member role should now be upgraded to COMPLIANCE_AUDITOR
        self.assertEqual(rbac_user.role, RoleTier.COMPLIANCE_AUDITOR)


class TestSamlOidcAuthenticator(unittest.TestCase):
    """Verifies SAML 2.0 and OpenID Connect identity assertion validation."""

    def setUp(self):
        self.rbac = RbacEngine()
        self.sso = SamlOidcAuthenticator(rbac_engine=self.rbac)

    def test_saml_validation_and_jit_enrollment(self):
        # Register SAML Provider
        config = SamlIdentityProviderConfig(
            entity_id="https://idp.okta.com/exk9481a",
            sso_url="https://idp.okta.com/app/sso",
            issuer="https://idp.okta.com/exk9481a",
            default_role=RoleTier.TEACHER_PARENT,
        )
        self.sso.register_saml_provider("org_springfield", config)

        # Craft SAMLResponse XML
        saml_xml = (
            '<samlp:Response xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol">'
            '  <saml:Assertion xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion">'
            '    <saml:Issuer>https://idp.okta.com/exk9481a</saml:Issuer>'
            '    <saml:Subject>'
            '      <saml:NameID>principal.skinner@springfield.k12.us</saml:NameID>'
            '    </saml:Subject>'
            '    <saml:AttributeStatement>'
            '      <saml:Attribute Name="Role">RoleTier:ORG_ADMIN</saml:Attribute>'
            '    </saml:AttributeStatement>'
            '  </saml:Assertion>'
            '</samlp:Response>'
        )
        b64_response = base64.b64encode(saml_xml.encode("utf-8")).decode("utf-8")

        success, user, reason = self.sso.validate_saml_response("org_springfield", b64_response)
        self.assertTrue(success)
        self.assertIsNotNone(user)
        self.assertEqual(user.email, "principal.skinner@springfield.k12.us")
        self.assertEqual(user.role, RoleTier.ORG_ADMIN)

    def test_saml_issuer_mismatch(self):
        config = SamlIdentityProviderConfig(
            entity_id="https://idp.entra.microsoft.com/tenant1",
            sso_url="https://idp.entra.microsoft.com/sso",
            issuer="https://idp.entra.microsoft.com/tenant1",
        )
        self.sso.register_saml_provider("org_entra", config)

        saml_xml = (
            '<samlp:Response>'
            '  <saml:Issuer>https://evil-idp.attacker.com</saml:Issuer>'
            '  <saml:NameID>spoofed@org.com</saml:NameID>'
            '</samlp:Response>'
        )
        b64_response = base64.b64encode(saml_xml.encode("utf-8")).decode("utf-8")

        success, user, reason = self.sso.validate_saml_response("org_entra", b64_response)
        self.assertFalse(success)
        self.assertIsNone(user)
        self.assertIn("Issuer mismatch", reason)

    def test_oidc_jwt_validation_and_jit_enrollment(self):
        client_secret = "super_secret_jwt_hmac_key_2026"
        config = OidcProviderConfig(
            issuer="https://accounts.google.com",
            client_id="fdns-client-app-991",
            client_secret=client_secret,
            default_role=RoleTier.TEAM_LEAD,
        )
        self.sso.register_oidc_provider("org_google", config)

        now = int(time.time())
        header = {"alg": "HS256", "typ": "JWT"}
        payload = {
            "iss": "https://accounts.google.com",
            "aud": "fdns-client-app-991",
            "sub": "google-user-10293",
            "email": "teacher.edna@springfield.k12.us",
            "name": "Edna Krabappel",
            "roles": ["TEACHER_PARENT"],
            "exp": now + 3600,
            "iat": now,
        }

        h_b64 = base64.urlsafe_b64encode(json.dumps(header).encode("utf-8")).decode("utf-8").rstrip("=")
        p_b64 = base64.urlsafe_b64encode(json.dumps(payload).encode("utf-8")).decode("utf-8").rstrip("=")
        sig = hmac.new(client_secret.encode("utf-8"), f"{h_b64}.{p_b64}".encode("utf-8"), hashlib.sha256).digest()
        sig_b64 = base64.urlsafe_b64encode(sig).decode("utf-8").rstrip("=")
        jwt_token = f"{h_b64}.{p_b64}.{sig_b64}"

        success, user, reason = self.sso.validate_oidc_id_token("org_google", jwt_token)
        self.assertTrue(success)
        self.assertIsNotNone(user)
        self.assertEqual(user.email, "teacher.edna@springfield.k12.us")
        self.assertEqual(user.role, RoleTier.TEACHER_PARENT)

    def test_oidc_jwt_expired(self):
        client_secret = "secret"
        config = OidcProviderConfig(
            issuer="https://accounts.google.com",
            client_id="client1",
            client_secret=client_secret,
        )
        self.sso.register_oidc_provider("org_test", config)

        # Expired 1 hour ago
        payload = {
            "iss": "https://accounts.google.com",
            "aud": "client1",
            "email": "expired@test.com",
            "exp": int(time.time()) - 3600,
        }
        h_b64 = base64.urlsafe_b64encode(b'{"alg":"HS256"}').decode("utf-8").rstrip("=")
        p_b64 = base64.urlsafe_b64encode(json.dumps(payload).encode("utf-8")).decode("utf-8").rstrip("=")
        sig = hmac.new(client_secret.encode("utf-8"), f"{h_b64}.{p_b64}".encode("utf-8"), hashlib.sha256).digest()
        sig_b64 = base64.urlsafe_b64encode(sig).decode("utf-8").rstrip("=")
        jwt_token = f"{h_b64}.{p_b64}.{sig_b64}"

        success, user, reason = self.sso.validate_oidc_id_token("org_test", jwt_token)
        self.assertFalse(success)
        self.assertIn("expired", reason.lower())


if __name__ == "__main__":
    unittest.main()
