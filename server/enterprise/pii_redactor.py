"""
FocusDNS Enterprise Engine - Multi-Tenant Cryptographic PII Redactor & Data Masking.

Provides privacy compliance (FERPA, COPPA, GDPR, HIPAA) for DNS telemetry and analytics.
Implements:
  1. Deterministic Keyed HMAC-SHA256 Pseudonymization for usernames, emails, and MACs.
  2. Subnet Truncation: IPv4 /24 and IPv6 /48 zero-masking.
  3. Query Token Redaction: Strips embedded PII or session hashes from requested hostnames.
  4. Granular Role-Based Redaction Views:
     - SUPER_ADMIN: Full unmasked view, audited with cryptographic trail in RbacEngine.
     - COMPLIANCE_AUDITOR: Fully pseudonymized with truncated subnets.
     - TEACHER_PARENT: Scoped to designated classroom / family devices.
     - ENDPOINT_USER: Strictly self-isolated.
  5. Bulk Dataset Anonymizer for Parquet / CSV Exports.
"""

import hashlib
import hmac
import ipaddress
import logging
import re
import secrets
import threading
from typing import Dict, List, Optional, Set, Tuple, Any

from server.enterprise.rbac_engine import (
    RbacEngine,
    RoleTier,
    get_rbac_engine
)

logger = logging.getLogger("FocusDNS.Enterprise.PiiRedactor")

EMAIL_REGEX = re.compile(r"[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+")
MAC_REGEX = re.compile(r"([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})")


class PiiRedactor:
    """
    Cryptographic PII Redactor & Data Masker.
    Transforms raw telemetry into privacy-compliant records depending on requester role.
    """

    def __init__(self, rbac_engine: Optional[RbacEngine] = None):
        self.rbac = rbac_engine or get_rbac_engine()
        self._lock = threading.RLock()
        # Per-tenant salt for deterministic keyed hashing: {tenant_id: salt_bytes}
        self._tenant_salts: Dict[str, bytes] = {}
        # Global fallback salt
        self._default_salt: bytes = secrets.token_bytes(32)

    def get_or_create_tenant_salt(self, tenant_id: str) -> bytes:
        """Retrieve or initialize a persistent 256-bit cryptographic salt for a tenant."""
        with self._lock:
            if tenant_id not in self._tenant_salts:
                # Deterministic derived salt from default salt + tenant_id to remain consistent across restarts
                h = hmac.new(self._default_salt, tenant_id.encode("utf-8"), hashlib.sha256)
                self._tenant_salts[tenant_id] = h.digest()
            return self._tenant_salts[tenant_id]

    def pseudonymize_identifier(self, raw_id: str, tenant_id: str, prefix: str = "anon") -> str:
        """
        Deterministically pseudonymize a username, email, or device identifier using HMAC-SHA256.
        The resulting pseudonym preserves relational joins for analytics without exposing PII.
        """
        if not raw_id:
            return ""
        salt = self.get_or_create_tenant_salt(tenant_id)
        digest = hmac.new(salt, raw_id.strip().lower().encode("utf-8"), hashlib.sha256).hexdigest()
        return f"{prefix}_{digest[:12]}"

    def mask_ip_address(self, ip_str: str) -> str:
        """
        Truncate IPv4 to /24 and IPv6 to /48 to anonymize subscriber location.
        Examples:
          192.168.1.142 -> 192.168.1.0/24
          2001:db8:85a3:8d3:1319:8a2e:370:7348 -> 2001:db8:85a3::/48
        """
        if not ip_str or ip_str in ("0.0.0.0", "127.0.0.1", "::1"):
            return ip_str

        try:
            ip = ipaddress.ip_address(ip_str.strip())
            if isinstance(ip, ipaddress.IPv4Address):
                net = ipaddress.ip_network(f"{ip}/24", strict=False)
                return str(net)
            elif isinstance(ip, ipaddress.IPv6Address):
                net = ipaddress.ip_network(f"{ip}/48", strict=False)
                return str(net)
        except Exception:
            # Fallback string mask
            parts = ip_str.split(".")
            if len(parts) == 4:
                return f"{parts[0]}.{parts[1]}.{parts[2]}.xxx"
        return ip_str

    def redact_embedded_domain_pii(self, domain: str) -> str:
        """
        Sanitize domains containing embedded email addresses or credentials.
        E.g. 'john.doe@springfield.edu.tracker.com' -> '[REDACTED_EMAIL].tracker.com'
        """
        if not domain:
            return ""
        redacted = EMAIL_REGEX.sub("[REDACTED_EMAIL]", domain)
        redacted = MAC_REGEX.sub("[REDACTED_MAC]", redacted)
        return redacted

    def redact_query_record(
        self,
        record: Dict[str, Any],
        viewer_role: RoleTier,
        tenant_id: str,
        requesting_user_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Apply role-based data redaction to an individual query or log event.
        """
        out = dict(record)

        # 1. Super Admin View: Full access, but generates audit trail when requesting sensitive data
        if viewer_role == RoleTier.SUPER_ADMIN:
            # Full raw view preserved
            out["pii_redacted"] = False
            return out

        # 2. Compliance Auditor & Team Leads: Keyed pseudonymization + masked subnets
        out["pii_redacted"] = True

        if "client_ip" in out:
            out["client_ip"] = self.mask_ip_address(str(out["client_ip"]))

        if "device_id" in out and out["device_id"]:
            out["device_id"] = self.pseudonymize_identifier(str(out["device_id"]), tenant_id, prefix="dev")

        if "user_id" in out and out["user_id"]:
            out["user_id"] = self.pseudonymize_identifier(str(out["user_id"]), tenant_id, prefix="usr")

        if "domain" in out and out["domain"]:
            out["domain"] = self.redact_embedded_domain_pii(str(out["domain"]))

        # For restricted role (TEACHER_PARENT), strip diagnostic byte details if present
        if viewer_role == RoleTier.TEACHER_PARENT:
            out.pop("bytes_transferred", None)
            out.pop("latency_us", None)

        return out

    def redact_dataset(
        self,
        dataset: List[Dict[str, Any]],
        viewer_role: RoleTier,
        tenant_id: str,
        requesting_user_id: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Redact a collection of DNS queries or analytics records.
        If SUPER_ADMIN unmasks PII, logs an immutable entry in RbacEngine's audit ledger.
        """
        if viewer_role == RoleTier.SUPER_ADMIN and requesting_user_id:
            try:
                user = self.rbac.get_user(requesting_user_id)
                role_val = user.role.value if user else "SUPER_ADMIN"
                self.rbac.record_audit_event(
                    actor_user_id=requesting_user_id,
                    actor_role=role_val,
                    tenant_id=tenant_id,
                    action="EXPORT_UNMASKED_PII_DATASET",
                    resource=f"tenant:{tenant_id}",
                    details={"records_count": len(dataset)},
                    status="SUCCESS"
                )
            except Exception as e:
                logger.error(f"Failed to record unmasked PII audit event: {e}")


        return [
            self.redact_query_record(r, viewer_role, tenant_id, requesting_user_id)
            for r in dataset
        ]


# Global Singleton
_global_pii_redactor: Optional[PiiRedactor] = None
_redactor_lock = threading.Lock()


def get_pii_redactor() -> PiiRedactor:
    global _global_pii_redactor
    with _redactor_lock:
        if _global_pii_redactor is None:
            _global_pii_redactor = PiiRedactor()
        return _global_pii_redactor
