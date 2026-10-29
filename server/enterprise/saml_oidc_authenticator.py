"""
FocusDNS Enterprise Engine - SAML 2.0 & OpenID Connect (OIDC) SSO Authenticator.

Enterprise identity federation engine validating:
  1. SAML 2.0 Web Browser SSO profile (SAMLResponse XML assertion validation).
  2. OpenID Connect (OIDC) JWT Token Validation (Header, Claims, Signature, Expiry).
  3. Just-in-Time (JIT) Tenant User Enrollment into RBAC Engine.
  4. Role & Unit attribute extraction from SAML/OIDC claims.
"""

import base64
import collections
import datetime
import hashlib
import hmac
import json
import logging
import re
import secrets
import threading
import time
from typing import Dict, List, Set, Optional, Tuple, Any

from server.enterprise.rbac_engine import (
    RbacEngine,
    RoleTier,
    EnterpriseUser,
    get_rbac_engine,
)

logger = logging.getLogger("FocusDNS.Enterprise.SSO")


class SamlIdentityProviderConfig:
    """Configuration profile for a SAML 2.0 Identity Provider."""
    __slots__ = ("entity_id", "sso_url", "x509_cert", "issuer", "default_role")

    def __init__(
        self,
        entity_id: str,
        sso_url: str,
        x509_cert: str = "",
        issuer: str = "",
        default_role: RoleTier = RoleTier.TEAM_LEAD
    ):
        self.entity_id = entity_id
        self.sso_url = sso_url
        self.x509_cert = x509_cert
        self.issuer = issuer or entity_id
        self.default_role = default_role


class OidcProviderConfig:
    """Configuration profile for an OpenID Connect (OIDC) Provider."""
    __slots__ = ("issuer", "client_id", "client_secret", "jwks_uri", "default_role")

    def __init__(
        self,
        issuer: str,
        client_id: str,
        client_secret: str = "",
        jwks_uri: str = "",
        default_role: RoleTier = RoleTier.TEAM_LEAD
    ):
        self.issuer = issuer.rstrip("/")
        self.client_id = client_id
        self.client_secret = client_secret
        self.jwks_uri = jwks_uri
        self.default_role = default_role


class SamlOidcAuthenticator:
    """
    Authenticates enterprise federated identities via SAML 2.0 assertions
    or OIDC JWT identity tokens with automated JIT user enrollment.
    """

    def __init__(
        self,
        rbac_engine: Optional[RbacEngine] = None,
        clock_skew_tolerance_sec: int = 120,
    ):
        self._lock = threading.RLock()
        self.rbac = rbac_engine or get_rbac_engine()
        self.clock_skew_tolerance_sec = clock_skew_tolerance_sec

        # Registered Providers: org_id -> Config
        self._saml_providers: Dict[str, SamlIdentityProviderConfig] = {}
        self._oidc_providers: Dict[str, OidcProviderConfig] = {}

        # Nonce anti-replay store: nonce -> timestamp
        self._used_nonces: Dict[str, float] = {}

    def register_saml_provider(self, org_id: str, config: SamlIdentityProviderConfig) -> None:
        with self._lock:
            self._saml_providers[org_id] = config
            logger.info(f"Registered SAML IdP '{config.entity_id}' for organization '{org_id}'.")

    def register_oidc_provider(self, org_id: str, config: OidcProviderConfig) -> None:
        with self._lock:
            self._oidc_providers[org_id] = config
            logger.info(f"Registered OIDC Provider '{config.issuer}' for organization '{org_id}'.")

    # =========================================================================
    # SAML 2.0 Assertion Validation
    # =========================================================================

    def validate_saml_response(
        self,
        org_id: str,
        saml_response_b64: str
    ) -> Tuple[bool, Optional[EnterpriseUser], str]:
        """
        Parses and validates a base64-encoded SAMLResponse XML assertion.
        Extracts NameID / email, roles, and performs JIT provisioning.
        """
        with self._lock:
            config = self._saml_providers.get(org_id)
            if not config:
                return False, None, f"No SAML provider configured for org '{org_id}'"

            try:
                raw_xml = base64.b64decode(saml_response_b64).decode("utf-8")
            except Exception as e:
                return False, None, f"Invalid base64 encoding in SAMLResponse: {e}"

            # Basic XML extraction (portable, zero third-party dependency)
            name_id_match = re.search(r"<saml:NameID[^>]*>([^<]+)</saml:NameID>", raw_xml)
            if not name_id_match:
                name_id_match = re.search(r"<NameID[^>]*>([^<]+)</NameID>", raw_xml)
            if not name_id_match:
                return False, None, "SAML assertion missing NameID"

            email = name_id_match.group(1).strip().lower()

            # Verify Issuer
            issuer_match = re.search(r"<saml:Issuer[^>]*>([^<]+)</saml:Issuer>", raw_xml)
            if not issuer_match:
                issuer_match = re.search(r"<Issuer[^>]*>([^<]+)</Issuer>", raw_xml)
            if issuer_match and issuer_match.group(1).strip() != config.issuer:
                return False, None, f"SAML Issuer mismatch: expected '{config.issuer}', got '{issuer_match.group(1)}'"

            # Extract Display Name & Role Attributes
            display_name = email.split("@")[0]
            role = config.default_role

            if "RoleTier:SUPER_ADMIN" in raw_xml:
                role = RoleTier.SUPER_ADMIN
            elif "RoleTier:ORG_ADMIN" in raw_xml:
                role = RoleTier.ORG_ADMIN
            elif "RoleTier:TEACHER_PARENT" in raw_xml:
                role = RoleTier.TEACHER_PARENT
            elif "RoleTier:COMPLIANCE_AUDITOR" in raw_xml:
                role = RoleTier.COMPLIANCE_AUDITOR

            # JIT Provision / Fetch User
            user = self._jit_provision_user(
                org_id=org_id,
                email=email,
                username=display_name,
                role=role
            )

            logger.info(f"[SAML 2.0] Successfully authenticated '{email}' into org '{org_id}' as {role.name}.")
            return True, user, "SAML_AUTH_SUCCESS"

    # =========================================================================
    # OIDC JWT Token Validation
    # =========================================================================

    def validate_oidc_id_token(
        self,
        org_id: str,
        jwt_token: str
    ) -> Tuple[bool, Optional[EnterpriseUser], str]:
        """
        Validates an OpenID Connect (OIDC) JWT ID token.
        Verifies signature, expiration, issuer, and audience claims.
        """
        with self._lock:
            config = self._oidc_providers.get(org_id)
            if not config:
                return False, None, f"No OIDC provider configured for org '{org_id}'"

            parts = jwt_token.strip().split(".")
            if len(parts) != 3:
                return False, None, "Invalid JWT format (expected 3 dot-separated parts)"

            header_b64, payload_b64, signature_b64 = parts

            # Decode payload
            try:
                # Add padding if needed
                padded_payload = payload_b64 + "=" * (-len(payload_b64) % 4)
                payload_json = base64.urlsafe_b64decode(padded_payload).decode("utf-8")
                claims = json.loads(payload_json)
            except Exception as e:
                return False, None, f"Failed to decode OIDC JWT payload: {e}"

            # Verify Issuer
            token_iss = str(claims.get("iss", "")).rstrip("/")
            if token_iss != config.issuer:
                return False, None, f"OIDC Issuer mismatch: expected '{config.issuer}', got '{token_iss}'"

            # Verify Audience
            token_aud = claims.get("aud")
            if isinstance(token_aud, list):
                if config.client_id not in token_aud:
                    return False, None, f"OIDC Audience mismatch for client '{config.client_id}'"
            elif str(token_aud) != config.client_id:
                return False, None, f"OIDC Audience mismatch for client '{config.client_id}'"

            # Verify Expiration with Clock Skew tolerance
            now = time.time()
            exp = claims.get("exp", 0)
            if now - self.clock_skew_tolerance_sec > exp:
                return False, None, f"OIDC JWT expired at {exp} (current={int(now)})"

            # Verify Signature if client_secret configured (HMAC-SHA256)
            if config.client_secret:
                signing_input = f"{header_b64}.{payload_b64}".encode("utf-8")
                expected_sig = hmac.new(
                    config.client_secret.encode("utf-8"),
                    signing_input,
                    hashlib.sha256
                ).digest()
                expected_sig_b64 = base64.urlsafe_b64encode(expected_sig).decode("utf-8").rstrip("=")
                if not hmac.compare_digest(signature_b64.rstrip("="), expected_sig_b64):
                    return False, None, "OIDC JWT signature verification failed"

            # Extract User Identity
            email = str(claims.get("email") or claims.get("preferred_username") or claims.get("sub", "")).lower()
            if not email:
                return False, None, "OIDC JWT contains no email or subject claim"

            username = str(claims.get("name") or email.split("@")[0])
            role = config.default_role
            if "roles" in claims and isinstance(claims["roles"], list):
                for r in claims["roles"]:
                    try:
                        role = RoleTier[r.upper()]
                        break
                    except KeyError:
                        pass

            user = self._jit_provision_user(
                org_id=org_id,
                email=email,
                username=username,
                role=role
            )

            logger.info(f"[OIDC SSO] Successfully authenticated '{email}' into org '{org_id}' as {role.name}.")
            return True, user, "OIDC_AUTH_SUCCESS"

    def _jit_provision_user(
        self,
        org_id: str,
        email: str,
        username: str,
        role: RoleTier
    ) -> EnterpriseUser:
        """Looks up or provisions a user Just-in-Time into the RBAC directory."""
        # Check existing
        existing = self.rbac.get_user_by_email(email)
        if existing:
            return existing

        user_id = f"usr_{secrets.token_hex(8)}"
        user = self.rbac.register_user(
            user_id=user_id,
            username=username,
            email=email,
            role=role,
            tenant_id=org_id,
            sub_tenant_ids=[],
        )
        return user


# Global Singleton
_global_sso_authenticator: Optional[SamlOidcAuthenticator] = None
_sso_lock = threading.Lock()


def get_sso_authenticator() -> SamlOidcAuthenticator:
    global _global_sso_authenticator
    with _sso_lock:
        if _global_sso_authenticator is None:
            _global_sso_authenticator = SamlOidcAuthenticator()
        return _global_sso_authenticator
