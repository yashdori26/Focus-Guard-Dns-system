"""
FocusDNS AI Engine - Synthetic DGA Threat Feed Generator & Sinkhole Exporter.

Generates real-time, dated, and multi-family synthetic malware C2 threat feeds
across 20+ documented DGA malware families for proactive sinkholing, offline testing,
and integration into standard DNS daemons (BIND RPZ, Unbound, Dnsmasq, Hostfiles).

Inviolable Constraints:
  1. Life Safety Exemption: Emergency domains (911.gov, 112.gov, push.apple.com,
     update.microsoft.com, play.googleapis.com) are NEVER exported or sinkholed.
  2. Conditional Whitelisting Law: Whitelist additions are permitted when idle;
     strictly forbidden and raises PermissionError("ERROR_ACCESS_DENIED (5)")
     when locked or when countdown timer > 0.
  3. Zero Cloud Dependency: Fully autonomous on-device generation and parsing.
"""

import json
import time
import math
from typing import Dict, List, Set, Optional, Tuple, Any

from server.ai.dga_families import (
    DGA_FAMILIES, DgaGenerator, DgaFamilyProfile
)
from server.ai.fast_tokenizer import FastTokenizer

# Hardcoded Life Safety Exemptions
LIFE_SAFETY_DOMAINS: Set[str] = {
    "911.gov",
    "112.gov",
    "push.apple.com",
    "update.microsoft.com",
    "play.googleapis.com"
}


class DgaFeedEntry:
    """Represents a single generated synthetic DGA domain with threat attribution."""
    __slots__ = (
        "domain", "family", "dga_type", "entropy", "vowel_ratio",
        "seed", "timestamp", "sinkhole_action"
    )

    def __init__(
        self,
        domain: str,
        family: str,
        dga_type: str,
        entropy: float,
        vowel_ratio: float,
        seed: int,
        timestamp: Optional[float] = None,
        sinkhole_action: str = "NXDOMAIN"
    ):
        self.domain = domain.lower().strip()
        self.family = family
        self.dga_type = dga_type
        self.entropy = round(entropy, 4)
        self.vowel_ratio = round(vowel_ratio, 4)
        self.seed = seed
        self.timestamp = timestamp or time.time()
        self.sinkhole_action = sinkhole_action

    def to_dict(self) -> Dict[str, Any]:
        return {
            "domain": self.domain,
            "family": self.family,
            "dga_type": self.dga_type,
            "entropy": self.entropy,
            "vowel_ratio": self.vowel_ratio,
            "seed": self.seed,
            "timestamp": self.timestamp,
            "sinkhole_action": self.sinkhole_action
        }


class DgaFeedGenerator:
    """
    Orchestrates synthetic DGA threat feed generation, threat filtering,
    life safety verification, and multi-format export.
    """

    def __init__(self):
        self._is_locked: bool = False
        self._countdown_seconds: int = 0
        self._whitelist_exceptions: Set[str] = set()

    # --------------------------------------------------------------------------
    # Lock State & Conditional Whitelisting Law
    # --------------------------------------------------------------------------

    def set_lock_state(self, is_locked: bool, countdown_seconds: int = 0) -> None:
        """Sets the active protection lock and timer."""
        self._is_locked = is_locked
        self._countdown_seconds = max(0, countdown_seconds)

    @property
    def is_locked(self) -> bool:
        return self._is_locked or self._countdown_seconds > 0

    def add_whitelist_exception(self, domain: str) -> bool:
        """
        Whitelists a domain so it is NEVER included in threat sinkhole feeds.
        Permitted when idle; raises PermissionError if locked.
        """
        clean = domain.lower().strip().rstrip(".")
        if not clean:
            return False

        if self.is_locked:
            raise PermissionError(
                "ERROR_ACCESS_DENIED (5): Conditional Whitelisting Law prevents "
                "adding whitelist exceptions while active focus lock or timer is running."
            )

        self._whitelist_exceptions.add(clean)
        return True

    def remove_whitelist_exception(self, domain: str) -> bool:
        """Removes a domain from whitelist exceptions."""
        clean = domain.lower().strip().rstrip(".")
        if self.is_locked:
            raise PermissionError(
                "ERROR_ACCESS_DENIED (5): Conditional Whitelisting Law prevents "
                "removing whitelist exceptions while locked."
            )

        if clean in self._whitelist_exceptions:
            self._whitelist_exceptions.remove(clean)
            return True
        return False

    def get_whitelist_exceptions(self) -> List[str]:
        return sorted(list(self._whitelist_exceptions))

    # --------------------------------------------------------------------------
    # Safety Verification
    # --------------------------------------------------------------------------

    @classmethod
    def is_life_safety_exempt(cls, domain: str) -> bool:
        """Inviolable check: emergency services and platform OS updates are never sinkholed."""
        clean = domain.lower().strip().rstrip(".")
        if clean in LIFE_SAFETY_DOMAINS:
            return True
        for exempt in LIFE_SAFETY_DOMAINS:
            if clean.endswith("." + exempt):
                return True
        return False

    def _is_domain_allowed(self, domain: str) -> bool:
        """Returns True if domain is allowed (exempt or whitelisted), meaning it should NOT be in feed."""
        if self.is_life_safety_exempt(domain):
            return True
        clean = domain.lower().strip().rstrip(".")
        if clean in self._whitelist_exceptions:
            return True
        for w in self._whitelist_exceptions:
            if clean.endswith("." + w):
                return True
        return False

    # --------------------------------------------------------------------------
    # Feed Generation
    # --------------------------------------------------------------------------

    def generate_feed_for_family(
        self,
        family_name: str,
        count: int = 50,
        base_seed: int = 12345
    ) -> List[DgaFeedEntry]:
        """Generates a batch of synthetic DGA domains for a single malware family."""
        clean_family = family_name.lower().strip()
        profile = DGA_FAMILIES.get(clean_family, DGA_FAMILIES.get("conficker"))
        if not profile:
            return []

        entries: List[DgaFeedEntry] = []
        seen_domains: Set[str] = set()

        for idx in range(count):
            seed = base_seed + idx * 7919  # Large prime stride
            candidate = DgaGenerator.generate_domain(clean_family, seed=seed)

            # Safety check: discard if exempt or whitelisted
            if self._is_domain_allowed(candidate):
                continue

            if candidate in seen_domains:
                continue
            seen_domains.add(candidate)

            # Calculate lexical features
            _tok = FastTokenizer()
            entropy = _tok.shannon_entropy(candidate)
            vowel_ratio, _, _ = _tok.vowel_consonant_ratio(candidate)

            entry = DgaFeedEntry(
                domain=candidate,
                family=profile.name,
                dga_type=profile.type,
                entropy=entropy,
                vowel_ratio=vowel_ratio,
                seed=seed,
                sinkhole_action="NXDOMAIN"
            )
            entries.append(entry)

        return entries

    def generate_multi_family_feed(
        self,
        families: Optional[List[str]] = None,
        count_per_family: int = 20,
        base_seed: int = 424242
    ) -> List[DgaFeedEntry]:
        """Generates a diverse multi-family threat feed across all specified or supported families."""
        target_families = families if families else list(DGA_FAMILIES.keys())
        all_entries: List[DgaFeedEntry] = []

        for idx, fam in enumerate(target_families):
            family_seed = base_seed + idx * 65537
            family_entries = self.generate_feed_for_family(
                fam,
                count=count_per_family,
                base_seed=family_seed
            )
            all_entries.extend(family_entries)

        return all_entries

    # --------------------------------------------------------------------------
    # Export Formats
    # --------------------------------------------------------------------------

    @classmethod
    def export_hosts_format(
        cls,
        entries: List[DgaFeedEntry],
        sinkhole_ip: str = "0.0.0.0",
        header_comment: str = "FocusDNS AI Synthetic DGA Blocklist"
    ) -> str:
        """Exports entries into standard /etc/hosts format."""
        lines = [
            f"# ====================================================================",
            f"# {header_comment}",
            f"# Generated Entries: {len(entries)}",
            f"# Format: standard hosts file (0.0.0.0 sinkhole)",
            f"# ====================================================================",
            ""
        ]
        for e in entries:
            lines.append(f"{sinkhole_ip} {e.domain}  # [{e.family}]")
        return "\n".join(lines) + "\n"

    @classmethod
    def export_bind_rpz(
        cls,
        entries: List[DgaFeedEntry],
        zone_origin: str = "rpz.focusguard.internal",
        ttl: int = 300
    ) -> str:
        """Exports entries into standard BIND 9 RPZ (Response Policy Zone) format."""
        lines = [
            f"; FocusDNS AI - BIND 9 Response Policy Zone (RPZ)",
            f"$TTL {ttl}",
            f"@ IN SOA localhost. root.localhost. ({int(time.time())} 3600 600 86400 300)",
            f"@ IN NS localhost.",
            f"; Blocked DGA Domains ({len(entries)} entries)",
            ""
        ]
        for e in entries:
            # RPZ CNAME . triggers NXDOMAIN response
            lines.append(f"{e.domain}.{zone_origin}. CNAME .")
            lines.append(f"*.{e.domain}.{zone_origin}. CNAME .")
        return "\n".join(lines) + "\n"

    @classmethod
    def export_unbound_format(
        cls,
        entries: List[DgaFeedEntry],
        action: str = "always_refuse"
    ) -> str:
        """Exports entries into Unbound server configuration format."""
        lines = [
            "# FocusDNS AI - Unbound Local-Zone Blackhole Configuration",
            f"# Total entries: {len(entries)}",
            "server:"
        ]
        for e in entries:
            lines.append(f'    local-zone: "{e.domain}" {action}')
        return "\n".join(lines) + "\n"

    @classmethod
    def export_dnsmasq_format(
        cls,
        entries: List[DgaFeedEntry],
        sinkhole_ip: str = "0.0.0.0"
    ) -> str:
        """Exports entries into Dnsmasq / OpenWrt format."""
        lines = [
            "# FocusDNS AI - Dnsmasq Address Sinkhole Configuration",
            f"# Total entries: {len(entries)}"
        ]
        for e in entries:
            lines.append(f"address=/{e.domain}/{sinkhole_ip}")
        return "\n".join(lines) + "\n"

    @classmethod
    def export_json_feed(
        cls,
        entries: List[DgaFeedEntry],
        metadata: Optional[Dict[str, Any]] = None
    ) -> str:
        """Exports entries into structured JSON telemetry feed."""
        payload = {
            "version": "1.0.0",
            "timestamp": time.time(),
            "total_entries": len(entries),
            "metadata": metadata or {},
            "entries": [e.to_dict() for e in entries]
        }
        return json.dumps(payload, indent=2)
