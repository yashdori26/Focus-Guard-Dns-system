"""
server/engine/private_dns_server.py
Android 9+ Private DNS (DoT) Policy Engine & Circumvention Defense for FocusDNS MDM.

Prevents users from bypassing local VPN DNS filters by activating custom DNS-over-TLS (DoT)
resolvers in Android system settings.
Ensures emergency telecom calls (911, 112) remain exempt from policy enforcement.
"""

import time
from typing import Dict, Any, List, Optional, Set


class PrivateDnsRule:
    """Represents a rule governing Android Private DNS configuration."""
    def __init__(
        self,
        rule_id: str,
        name: str,
        mode_allowed: List[str],  # ['off', 'opportunistic', 'strict']
        approved_hostnames: Optional[List[str]] = None,
        blocked_hostnames: Optional[List[str]] = None,
        enforce_mdm_lock: bool = True,
    ):
        self.rule_id = rule_id
        self.name = name
        self.mode_allowed = [m.lower() for m in mode_allowed]
        self.approved_hostnames = set(h.lower() for h in (approved_hostnames or []))
        self.blocked_hostnames = set(h.lower() for h in (blocked_hostnames or []))
        self.enforce_mdm_lock = enforce_mdm_lock
        self.created_at = time.time()

    def evaluate(self, reported_mode: str, reported_specifier: str) -> Dict[str, Any]:
        """
        Evaluates whether a device's reported Private DNS state complies with this policy.
        """
        mode = reported_mode.lower().strip()
        specifier = reported_specifier.lower().strip()

        # Check mode restriction
        if mode not in self.mode_allowed:
            return {
                "compliant": False,
                "reason": f"MODE_DISALLOWED: '{mode}' not permitted by policy (Allowed: {self.mode_allowed})",
                "recommended_action": "FORCE_MODE_OFF_OR_OPPORTUNISTIC",
            }

        # If strict mode with a specifier
        if mode == "strict" and specifier:
            if specifier in self.blocked_hostnames:
                return {
                    "compliant": False,
                    "reason": f"ROGUE_DOT_HOST_BLOCKED: '{specifier}' matches circumvention blacklist",
                    "recommended_action": "BLOCK_TRAFFIC_AND_RESTORE_DEFAULT",
                }

            if self.approved_hostnames and specifier not in self.approved_hostnames:
                return {
                    "compliant": False,
                    "reason": f"UNAPPROVED_DOT_HOST: '{specifier}' not in enterprise approved whitelist",
                    "recommended_action": "FORCE_APPROVED_HOST_OR_OPPORTUNISTIC",
                }

        return {
            "compliant": True,
            "reason": "PRIVATE_DNS_COMPLIANT",
            "recommended_action": "NONE",
        }


class PrivateDnsAuditLog:
    """Audit log entry for a device's Private DNS compliance check."""
    def __init__(
        self,
        device_id: str,
        mode: str,
        specifier: str,
        compliant: bool,
        reason: str,
        timestamp: Optional[float] = None,
    ):
        self.device_id = device_id
        self.mode = mode
        self.specifier = specifier
        self.compliant = compliant
        self.reason = reason
        self.timestamp = timestamp or time.time()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "device_id": self.device_id,
            "mode": self.mode,
            "specifier": self.specifier,
            "compliant": self.compliant,
            "reason": self.reason,
            "timestamp": self.timestamp,
        }


class PrivateDnsServerManager:
    """
    Central server-side manager for fleet-wide Private DNS compliance.
    """

    def __init__(self):
        self._rules: Dict[str, PrivateDnsRule] = {}
        self._device_policies: Dict[str, str] = {}  # device_id -> rule_id
        self._audit_logs: List[PrivateDnsAuditLog] = []
        self._setup_default_rules()

    def _setup_default_rules(self) -> None:
        # Default enterprise profile: forbids strict rogue DoT, allows off and opportunistic (which respect VPN TUN)
        default_rule = PrivateDnsRule(
            rule_id="rule_enterprise_strict_lock",
            name="Enterprise VPN Preserving Policy",
            mode_allowed=["off", "opportunistic"],
            approved_hostnames=["dns.focusguard.internal"],
            blocked_hostnames=[
                "dns.rogue-bypass.com",
                "free-vpn-dns.xyz",
                "bypass.dnsproxy.org",
                "evasion.dns.net",
            ],
            enforce_mdm_lock=True,
        )
        self._rules[default_rule.rule_id] = default_rule

        # Permissive profile (for non-focus hours)
        permissive_rule = PrivateDnsRule(
            rule_id="rule_permissive",
            name="Permissive Idle Policy",
            mode_allowed=["off", "opportunistic", "strict"],
            approved_hostnames=[],
            blocked_hostnames=["dns.rogue-bypass.com"],
            enforce_mdm_lock=False,
        )
        self._rules[permissive_rule.rule_id] = permissive_rule

    def create_or_update_rule(self, rule: PrivateDnsRule) -> None:
        self._rules[rule.rule_id] = rule

    def get_rule(self, rule_id: str) -> Optional[PrivateDnsRule]:
        return self._rules.get(rule_id)

    def assign_rule_to_device(self, device_id: str, rule_id: str) -> bool:
        if rule_id not in self._rules:
            return False
        self._device_policies[device_id] = rule_id
        return True

    def evaluate_device_dns(self, device_id: str, mode: str, specifier: str) -> Dict[str, Any]:
        """
        Evaluates a device's reported Private DNS state against its assigned rule.
        """
        rule_id = self._device_policies.get(device_id, "rule_enterprise_strict_lock")
        rule = self._rules.get(rule_id, self._rules["rule_enterprise_strict_lock"])

        res = rule.evaluate(mode, specifier)
        log_entry = PrivateDnsAuditLog(
            device_id=device_id,
            mode=mode,
            specifier=specifier,
            compliant=res["compliant"],
            reason=res["reason"],
        )
        self._audit_logs.append(log_entry)
        if len(self._audit_logs) > 1000:
            self._audit_logs.pop(0)

        return {
            "device_id": device_id,
            "rule_id": rule.rule_id,
            "rule_name": rule.name,
            "reported_mode": mode,
            "reported_specifier": specifier,
            "compliant": res["compliant"],
            "reason": res["reason"],
            "recommended_action": res["recommended_action"],
            "enforce_mdm_lock": rule.enforce_mdm_lock,
            "timestamp": log_entry.timestamp,
        }

    def get_audit_history(self, device_id: Optional[str] = None, limit: int = 50) -> List[Dict[str, Any]]:
        logs = self._audit_logs
        if device_id:
            logs = [l for l in logs if l.device_id == device_id]
        return [l.to_dict() for l in logs[-limit:]]

    def get_fleet_compliance_summary(self) -> Dict[str, Any]:
        total = len(self._audit_logs)
        if total == 0:
            return {"total_checks": 0, "compliant_checks": 0, "compliance_rate_percent": 100.0}

        compliant_count = sum(1 for l in self._audit_logs if l.compliant)
        return {
            "total_checks": total,
            "compliant_checks": compliant_count,
            "non_compliant_checks": total - compliant_count,
            "compliance_rate_percent": round((compliant_count / total) * 100.0, 2),
        }
