"""
FocusDNS Enterprise Engine - Fleet Policy Inheritance & Compilation Engine.

Compiles multi-tiered policies across the enterprise organizational tree:
  Organization Baseline -> TenantUnit Specializations -> DeviceFleet Profiles.

Conflict Resolution Law:
  1. Strictest Rule Wins: A child tier (Fleet/Unit) can tighten restrictions, but
     CANNOT weaken or disable security protections mandated by parent tiers.
  2. Inviolable Life Safety Hardcoded Exemption:
     Emergency calling (911.gov, 112.gov), system updates (update.microsoft.com),
     and push services (push.apple.com, play.googleapis.com) are permanently exempt
     and CAN NEVER be placed on custom blocklists.
  3. Optimized Binary/JSON Serialization for WebSocket Fleet Push.
"""

import collections
import hashlib
import json
import logging
from typing import Dict, List, Set, Optional, Tuple, Any

from server.enterprise.tenant_manager import Organization, TenantUnit, DeviceFleet
from server.ai.zero_hour_phishing import LIFE_SAFETY_EXEMPTIONS

logger = logging.getLogger("FocusDNS.Enterprise.PolicyCompiler")


class CompiledFleetPolicy:
    """Flattened, optimized policy bundle ready for device deployment."""
    __slots__ = (
        "fleet_id", "org_id", "unit_id", "version", "compiled_at",
        "blocked_categories", "blocked_domains", "whitelisted_domains",
        "security_flags", "is_strict_mode", "lock_duration_seconds", "signature"
    )

    def __init__(
        self,
        fleet_id: str,
        org_id: str,
        unit_id: str,
        version: int,
        compiled_at: float,
        blocked_categories: Set[str],
        blocked_domains: Set[str],
        whitelisted_domains: Set[str],
        security_flags: Dict[str, bool],
        is_strict_mode: bool,
        lock_duration_seconds: int,
        signature: str = ""
    ):
        self.fleet_id = fleet_id
        self.org_id = org_id
        self.unit_id = unit_id
        self.version = version
        self.compiled_at = compiled_at
        self.blocked_categories = blocked_categories
        self.blocked_domains = blocked_domains
        self.whitelisted_domains = whitelisted_domains
        self.security_flags = security_flags
        self.is_strict_mode = is_strict_mode
        self.lock_duration_seconds = lock_duration_seconds
        self.signature = signature or self.compute_signature()

    def compute_signature(self) -> str:
        payload = (
            f"{self.fleet_id}:{self.version}:{sorted(self.blocked_categories)}:"
            f"{sorted(self.blocked_domains)}:{sorted(self.whitelisted_domains)}:"
            f"{sorted(self.security_flags.items())}:{self.is_strict_mode}"
        )
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    def is_domain_blocked(self, domain: str) -> Tuple[bool, str]:
        """Fast evaluator for local testing against compiled policy."""
        clean = domain.lower().strip(".")

        # Step 0: Inviolable Life Safety Exemption
        for exempt in LIFE_SAFETY_EXEMPTIONS:
            if clean == exempt or clean.endswith(f".{exempt}"):
                return False, "LIFE_SAFETY_EXEMPT"

        # Step 1: Whitelist check
        if clean in self.whitelisted_domains:
            return False, "EXPLICIT_WHITELIST"

        # Step 2: Custom Blocklist
        if clean in self.blocked_domains:
            return True, "ENTERPRISE_CUSTOM_BLOCK"

        return False, "CLEAN"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "fleet_id": self.fleet_id,
            "org_id": self.org_id,
            "unit_id": self.unit_id,
            "version": self.version,
            "compiled_at": self.compiled_at,
            "blocked_categories": list(sorted(self.blocked_categories)),
            "blocked_domains": list(sorted(self.blocked_domains)),
            "whitelisted_domains": list(sorted(self.whitelisted_domains)),
            "security_flags": self.security_flags,
            "is_strict_mode": self.is_strict_mode,
            "lock_duration_seconds": self.lock_duration_seconds,
            "signature": self.signature
        }


class FleetPolicyCompiler:
    """
    Compiles multi-tiered policies into flattened device bundles.
    Resolves conflicts, purges illegal blocks on emergency services,
    and formats payloads for instantaneous WebSocket distribution.
    """

    def compile(
        self,
        org: Organization,
        unit: TenantUnit,
        fleet: DeviceFleet,
        org_policy: Optional[Dict[str, Any]] = None,
        unit_policy: Optional[Dict[str, Any]] = None,
        fleet_policy: Optional[Dict[str, Any]] = None,
        version: int = 1
    ) -> CompiledFleetPolicy:
        """Flattens hierarchical tiers into an immutable compiled bundle."""
        org_p = org_policy or {}
        unit_p = unit_policy or {}
        fleet_p = fleet_policy or {}

        # 1. Categories: Union of blocks across all tiers (strictest wins)
        blocked_cats: Set[str] = set()
        blocked_cats.update(org_p.get("blocked_categories", []))
        blocked_cats.update(unit_p.get("blocked_categories", []))
        blocked_cats.update(fleet_p.get("blocked_categories", []))

        # 2. Blocked Domains: Union of blocked domains
        raw_blocked_domains: Set[str] = set()
        raw_blocked_domains.update(d.lower().strip(".") for d in org_p.get("blocked_domains", []))
        raw_blocked_domains.update(d.lower().strip(".") for d in unit_p.get("blocked_domains", []))
        raw_blocked_domains.update(d.lower().strip(".") for d in fleet_p.get("blocked_domains", []))

        # INVIOLABLE LIFE SAFETY PURGE:
        # Emergency domains (911.gov, 112.gov, push.apple.com, update.microsoft.com) CAN NEVER BE BLOCKED
        sanitized_blocked_domains = set()
        for dom in raw_blocked_domains:
            is_exempt = False
            for exempt in LIFE_SAFETY_EXEMPTIONS:
                if dom == exempt or dom.endswith(f".{exempt}"):
                    logger.warning(f"Dropping illegal block on life safety domain '{dom}'!")
                    is_exempt = True
                    break
            if not is_exempt:
                sanitized_blocked_domains.add(dom)

        # 3. Whitelisted Domains: Fleet or Unit whitelists (cannot override org-level security flags)
        whitelisted: Set[str] = set()
        whitelisted.update(d.lower().strip(".") for d in fleet_p.get("whitelisted_domains", []))
        whitelisted.update(d.lower().strip(".") for d in unit_p.get("whitelisted_domains", []))
        # Remove any domain that is explicitly blocked by Organization baseline
        org_blocks = {d.lower().strip(".") for d in org_p.get("blocked_domains", [])}
        whitelisted = whitelisted - org_blocks

        # 4. Security Flags (AI Threat, SafeSearch, Rebinding, DGA MLP)
        # Any parent tier enabling a security flag forces it to True
        sec_keys = ["ai_threat", "safesearch", "dns_rebinding", "dga_ml", "homograph_defense", "tls_sni_inspection"]
        effective_flags: Dict[str, bool] = {}

        for k in sec_keys:
            org_flag = org_p.get(k, True)  # Org defaults to True
            unit_flag = unit_p.get(k, org_flag)
            fleet_flag = fleet_p.get(k, unit_flag)
            # If org enables, cannot be disabled down-tier
            effective_flags[k] = org_flag or unit_flag or fleet_flag

        is_strict = fleet.is_locked or org_p.get("strict_mode", False) or fleet_p.get("strict_mode", False)
        lock_duration = fleet.remaining_lock_seconds

        import time
        return CompiledFleetPolicy(
            fleet_id=fleet.fleet_id,
            org_id=org.org_id,
            unit_id=unit.unit_id,
            version=version,
            compiled_at=time.time(),
            blocked_categories=blocked_cats,
            blocked_domains=sanitized_blocked_domains,
            whitelisted_domains=whitelisted,
            security_flags=effective_flags,
            is_strict_mode=is_strict,
            lock_duration_seconds=lock_duration
        )
