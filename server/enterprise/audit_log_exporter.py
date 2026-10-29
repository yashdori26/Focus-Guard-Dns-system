"""
FocusDNS Enterprise Engine - CEF & JSONL Audit Exporter with Integrity Verifier.

Exports tamper-evident audit logs to SIEM systems using:
  1. ArcSight Common Event Format (CEF):
     CEF:Version|Device Vendor|Device Product|Device Version|Signature ID|Name|Severity|Extension
  2. JSON Lines (JSONL) with embedded cryptographic SHA-256 seal proofs.
  3. Standalone Verification Engine validating genesis-to-head hash continuity.
"""

import hashlib
import hmac
import json
import logging
from typing import Dict, List, Set, Optional, Tuple, Any

from server.enterprise.rbac_engine import AuditLogEntry, RbacEngine

logger = logging.getLogger("FocusDNS.Enterprise.AuditExporter")


class AuditLogExporter:
    """Exports cryptographic audit trails to industry standard formats."""

    @staticmethod
    def format_cef(entry: Dict[str, Any]) -> str:
        """
        Formats an audit log entry into Common Event Format (CEF).
        Format: CEF:0|FocusDNS|Enterprise|7.0.0|action|action|severity|extensions
        """
        severity_map = {
            "SUCCESS": "3",
            "FAILURE": "7",
            "BLOCKED_BY_STRICT_MODE": "9"
        }
        status = entry.get("status", "SUCCESS")
        cef_severity = severity_map.get(status, "5")

        action = entry.get("action", "UNKNOWN_ACTION")
        actor = entry.get("actor_user_id", "unknown")
        tenant = entry.get("tenant_id", "global")
        resource = entry.get("resource", "unknown")

        ext = (
            f"suser={actor} cs1Label=TenantId cs1={tenant} "
            f"cs2Label=Resource cs2={resource} cs3Label=EntryHash cs3={entry.get('entry_hash', '')} "
            f"msg={status}"
        )
        return f"CEF:0|FocusDNS|EnterprisePlatform|7.0.0|{action}|{action}|{cef_severity}|{ext}"

    @staticmethod
    def export_cef_stream(entries: List[Dict[str, Any]]) -> str:
        """Returns newline-delimited CEF records."""
        lines = [AuditLogExporter.format_cef(e) for e in entries]
        return "\n".join(lines)

    @staticmethod
    def export_jsonl_stream(entries: List[Dict[str, Any]]) -> str:
        """Returns newline-delimited JSON objects with integrity hashes."""
        lines = [json.dumps(e, sort_keys=True) for e in entries]
        return "\n".join(lines)

    @staticmethod
    def verify_exported_chain(
        entries: List[Dict[str, Any]],
        secret_key: str = "FocusDNS-Audit-Anchor-Secret"
    ) -> Tuple[bool, Optional[str]]:
        """
        Independent auditor function validating an exported JSON/CEF audit file
        from genesis block to latest head.
        """
        genesis_hash = "0000000000000000000000000000000000000000000000000000000000000000"
        expected_prev = genesis_hash

        for idx, entry in enumerate(entries):
            prev = entry.get("previous_hash")
            curr_hash = entry.get("entry_hash")

            if prev != expected_prev:
                return False, f"Broken chain link at index {idx} (ID: {entry.get('entry_id')}): expected {expected_prev}, got {prev}"

            # Recompute HMAC SHA-256
            payload = (
                f"{entry.get('entry_id')}:{entry.get('timestamp')}:{entry.get('actor_user_id')}:"
                f"{entry.get('actor_role')}:{entry.get('tenant_id')}:{entry.get('action')}:"
                f"{entry.get('resource')}:{json.dumps(entry.get('details', {}), sort_keys=True)}:"
                f"{entry.get('status')}:{prev}"
            )
            computed = hmac.new(secret_key.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).hexdigest()

            if curr_hash != computed:
                return False, f"Tampered hash signature at index {idx} (ID: {entry.get('entry_id')})"

            expected_prev = curr_hash

        return True, None
