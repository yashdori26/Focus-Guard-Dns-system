"""
FocusDNS AI Engine - Dynamic Multi-Category DNS Policy Router.

Enforces real-time Deep Focus category profiles, dynamic distraction blocking,
and security policies on unindexed internet traffic using the local on-device
DomainCategorizer.

Inviolable Constraints:
  1. Life Safety Exemption: Emergency domains (911.gov, 112.gov, push.apple.com,
     update.microsoft.com, play.googleapis.com) are hardcoded EXEMPT and NEVER blocked.
  2. Conditional Whitelisting Law: Whitelist additions are permitted when idle
     (is_locked=False and countdown=0); strictly forbidden and raises
     PermissionError("ERROR_ACCESS_DENIED (5)") when locked or during countdown.
  3. Zero Cloud Dependency: Evaluates 100% locally with high-speed in-memory LRU caching.
"""

import time
import threading
from typing import Dict, List, Set, Optional, Tuple, Any

from server.ai.category_lexicon import (
    ALL_CATEGORIES,
    CAT_GAMING, CAT_SOCIAL, CAT_ADULT, CAT_PRODUCTIVITY,
    CAT_SHOPPING, CAT_STREAMING, CAT_CRYPTO_GAMBLING, CAT_MALWARE, CAT_UNCATEGORIZED
)
from server.ai.domain_categorizer import DomainCategorizer, CategoryVerdict

# Hardcoded Life Safety Exemptions
LIFE_SAFETY_DOMAINS: Set[str] = {
    "911.gov",
    "112.gov",
    "push.apple.com",
    "update.microsoft.com",
    "play.googleapis.com"
}

# Policy Actions
ACTION_ALLOW = "ALLOW"
ACTION_BLOCK = "BLOCK"
ACTION_EXEMPT = "EXEMPT"


class CategoryPolicyProfile:
    """Configuration profile defining category block rules and confidence thresholds."""

    def __init__(
        self,
        name: str,
        blocked_categories: Optional[Set[str]] = None,
        allowed_categories: Optional[Set[str]] = None,
        min_confidence: float = 0.22,
        block_uncategorized: bool = False,
        strict_mode: bool = False,
        description: str = ""
    ):
        self.name = name
        self.blocked_categories: Set[str] = set(blocked_categories) if blocked_categories else set()
        self.allowed_categories: Set[str] = set(allowed_categories) if allowed_categories else set()
        self.min_confidence = min_confidence
        self.block_uncategorized = block_uncategorized
        self.strict_mode = strict_mode
        self.description = description

    def is_category_blocked(self, category: str, confidence: float) -> bool:
        """Determines if a category is blocked under this profile."""
        if category in self.allowed_categories:
            return False

        if category == CAT_UNCATEGORIZED:
            return self.block_uncategorized

        if category in self.blocked_categories:
            return confidence >= self.min_confidence

        return False

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "blocked_categories": sorted(list(self.blocked_categories)),
            "allowed_categories": sorted(list(self.allowed_categories)),
            "min_confidence": self.min_confidence,
            "block_uncategorized": self.block_uncategorized,
            "strict_mode": self.strict_mode,
            "description": self.description
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "CategoryPolicyProfile":
        return cls(
            name=data.get("name", "custom"),
            blocked_categories=set(data.get("blocked_categories", [])),
            allowed_categories=set(data.get("allowed_categories", [])),
            min_confidence=float(data.get("min_confidence", 0.22)),
            block_uncategorized=bool(data.get("block_uncategorized", False)),
            strict_mode=bool(data.get("strict_mode", False)),
            description=data.get("description", "")
        )


# Standard Predefined Profiles
PROFILE_FOCUS_WORK = CategoryPolicyProfile(
    name="focus_work",
    blocked_categories={
        CAT_GAMING, CAT_SOCIAL, CAT_ADULT, CAT_CRYPTO_GAMBLING, CAT_STREAMING
    },
    allowed_categories={CAT_PRODUCTIVITY},
    min_confidence=0.22,
    block_uncategorized=False,
    description="Maximum productivity: blocks games, social media, adult, streaming & gambling."
)

PROFILE_FOCUS_STUDY = CategoryPolicyProfile(
    name="focus_study",
    blocked_categories={
        CAT_GAMING, CAT_SOCIAL, CAT_ADULT, CAT_CRYPTO_GAMBLING, CAT_SHOPPING
    },
    allowed_categories={CAT_PRODUCTIVITY},
    min_confidence=0.22,
    block_uncategorized=False,
    description="Study session: blocks games, social, adult, shopping & gambling."
)

PROFILE_CHILD_SAFE = CategoryPolicyProfile(
    name="child_safe",
    blocked_categories={
        CAT_ADULT, CAT_CRYPTO_GAMBLING, CAT_MALWARE
    },
    min_confidence=0.20,
    block_uncategorized=False,
    description="Family friendly: strictly blocks adult, gambling, and malicious domains."
)

PROFILE_STRICT_SECURITY = CategoryPolicyProfile(
    name="strict_security",
    blocked_categories={
        CAT_MALWARE, CAT_CRYPTO_GAMBLING
    },
    min_confidence=0.18,
    block_uncategorized=False,
    description="Security hardened: blocks all AI-detected malware C2 and gambling portals."
)


class CategoryPolicyDecision:
    """Evaluation decision returned for a given DNS query."""
    __slots__ = (
        "action", "domain", "category", "confidence", "reason",
        "is_exempt", "is_whitelisted", "profile_name", "timestamp"
    )

    def __init__(
        self,
        action: str,
        domain: str,
        category: str,
        confidence: float,
        reason: str,
        is_exempt: bool = False,
        is_whitelisted: bool = False,
        profile_name: str = "",
        timestamp: Optional[float] = None
    ):
        self.action = action
        self.domain = domain
        self.category = category
        self.confidence = round(confidence, 4)
        self.reason = reason
        self.is_exempt = is_exempt
        self.is_whitelisted = is_whitelisted
        self.profile_name = profile_name
        self.timestamp = timestamp or time.time()

    @property
    def is_blocked(self) -> bool:
        return self.action == ACTION_BLOCK

    def to_dict(self) -> Dict[str, Any]:
        return {
            "action": self.action,
            "domain": self.domain,
            "category": self.category,
            "confidence": self.confidence,
            "reason": self.reason,
            "is_exempt": self.is_exempt,
            "is_whitelisted": self.is_whitelisted,
            "profile_name": self.profile_name,
            "timestamp": self.timestamp
        }


class AiCategoryPolicyEngine:
    """
    Evaluates DNS queries against the active category profile, life-safety rules,
    and conditional whitelist state.
    """

    def __init__(
        self,
        profile: Optional[CategoryPolicyProfile] = None,
        cache_capacity: int = 10000,
        cache_ttl_seconds: int = 3600
    ):
        self._profile: CategoryPolicyProfile = profile or PROFILE_FOCUS_WORK
        self._cache_capacity = cache_capacity
        self._cache_ttl = cache_ttl_seconds

        # Lock state and Whitelist (Guarded by Conditional Whitelisting Law)
        self._is_locked: bool = False
        self._countdown_seconds: int = 0
        self._whitelist: Set[str] = set()

        # Thread synchronization
        self._lock = threading.RLock()

        # LRU decision cache: domain -> (decision, expire_at)
        self._cache: Dict[str, Tuple[CategoryPolicyDecision, float]] = {}

        # Telemetry metrics
        self._total_evaluations: int = 0
        self._blocked_evaluations: int = 0
        self._allowed_evaluations: int = 0
        self._exempt_evaluations: int = 0
        self._cache_hits: int = 0
        self._category_blocks: Dict[str, int] = {cat: 0 for cat in ALL_CATEGORIES}
        self._category_blocks[CAT_UNCATEGORIZED] = 0

    # --------------------------------------------------------------------------
    # Profile & Mode Management
    # --------------------------------------------------------------------------

    @property
    def active_profile(self) -> CategoryPolicyProfile:
        with self._lock:
            return self._profile

    def set_profile(self, profile: CategoryPolicyProfile) -> None:
        """Sets the active category profile and flushes decision cache."""
        with self._lock:
            self._profile = profile
            self._cache.clear()

    def set_lock_state(self, is_locked: bool, countdown_seconds: int = 0) -> None:
        """Sets protection lock state and countdown timer."""
        with self._lock:
            self._is_locked = is_locked
            self._countdown_seconds = max(0, countdown_seconds)

    @property
    def is_locked(self) -> bool:
        with self._lock:
            return self._is_locked or self._countdown_seconds > 0

    # --------------------------------------------------------------------------
    # Conditional Whitelisting Law
    # --------------------------------------------------------------------------

    def add_whitelist(self, domain: str) -> bool:
        """
        Adds domain to category whitelist.
        Permitted when idle; strictly forbidden if locked or timer > 0.
        """
        clean = domain.lower().strip().rstrip(".")
        if not clean:
            return False

        with self._lock:
            if self.is_locked:
                raise PermissionError(
                    "ERROR_ACCESS_DENIED (5): Conditional Whitelisting Law prevents "
                    "adding whitelist entries during an active focus lock or timer."
                )

            self._whitelist.add(clean)
            self._cache.pop(clean, None)
            return True

    def remove_whitelist(self, domain: str) -> bool:
        """Removes domain from category whitelist."""
        clean = domain.lower().strip().rstrip(".")
        with self._lock:
            if self.is_locked:
                raise PermissionError(
                    "ERROR_ACCESS_DENIED (5): Conditional Whitelisting Law prevents "
                    "removing whitelist entries during an active focus lock or timer."
                )

            if clean in self._whitelist:
                self._whitelist.remove(clean)
                self._cache.pop(clean, None)
                return True
            return False

    def get_whitelist(self) -> List[str]:
        """Returns sorted list of whitelisted domains."""
        with self._lock:
            return sorted(list(self._whitelist))

    def clear_whitelist(self) -> None:
        """Clears whitelist if not locked."""
        with self._lock:
            if self.is_locked:
                raise PermissionError(
                    "ERROR_ACCESS_DENIED (5): Conditional Whitelisting Law prevents "
                    "clearing the whitelist during an active focus lock."
                )
            self._whitelist.clear()
            self._cache.clear()

    # --------------------------------------------------------------------------
    # Life Safety Exemption Check
    # --------------------------------------------------------------------------

    @classmethod
    def is_life_safety_exempt(cls, domain: str) -> bool:
        """
        Checks if domain is an inviolable life-safety or critical platform service.
        Hardcoded and never blocked under any circumstances.
        """
        clean = domain.lower().strip().rstrip(".")
        if clean in LIFE_SAFETY_DOMAINS:
            return True

        for exempt in LIFE_SAFETY_DOMAINS:
            if clean.endswith("." + exempt):
                return True
        return False

    # --------------------------------------------------------------------------
    # Evaluation Engine
    # --------------------------------------------------------------------------

    def evaluate(self, domain: str) -> CategoryPolicyDecision:
        """
        Evaluates a domain name against life-safety rules, whitelists,
        and dynamic category policy.
        """
        clean = domain.lower().strip().rstrip(".")
        now = time.time()

        with self._lock:
            self._total_evaluations += 1

            # 1. Fast Cache Lookup
            if clean in self._cache:
                decision, expire_at = self._cache[clean]
                if now < expire_at:
                    self._cache_hits += 1
                    return decision
                else:
                    del self._cache[clean]

            # 2. Check Life Safety Exemption (Inviolable Priority #1)
            if self.is_life_safety_exempt(clean):
                self._exempt_evaluations += 1
                self._allowed_evaluations += 1
                decision = CategoryPolicyDecision(
                    action=ACTION_EXEMPT,
                    domain=clean,
                    category="LIFE_SAFETY_EXEMPTION",
                    confidence=1.0,
                    reason="Inviolable life-safety or critical platform service (hardcoded exempt).",
                    is_exempt=True,
                    is_whitelisted=False,
                    profile_name=self._profile.name,
                    timestamp=now
                )
                self._cache_decision(clean, decision, now)
                return decision

            # 3. Check User Whitelist
            if clean in self._whitelist or any(clean.endswith("." + w) for w in self._whitelist):
                self._allowed_evaluations += 1
                decision = CategoryPolicyDecision(
                    action=ACTION_ALLOW,
                    domain=clean,
                    category="WHITELISTED",
                    confidence=1.0,
                    reason="Explicitly allowed by user category whitelist.",
                    is_exempt=False,
                    is_whitelisted=True,
                    profile_name=self._profile.name,
                    timestamp=now
                )
                self._cache_decision(clean, decision, now)
                return decision

            # 4. Classify Domain with On-Device AI Categorizer
            verdict: CategoryVerdict = DomainCategorizer.classify(clean)
            cat = verdict.primary_category
            conf = verdict.confidence

            # 5. Determine Policy Action
            is_blocked = self._profile.is_category_blocked(cat, conf)

            if is_blocked:
                self._blocked_evaluations += 1
                self._category_blocks[cat] = self._category_blocks.get(cat, 0) + 1
                reason = (
                    f"Category '{cat}' is blocked by active profile '{self._profile.name}' "
                    f"({conf * 100:.1f}% confidence >= {self._profile.min_confidence * 100:.1f}%)."
                )
                action = ACTION_BLOCK
            else:
                self._allowed_evaluations += 1
                reason = f"Category '{cat}' is permitted under active profile '{self._profile.name}'."
                action = ACTION_ALLOW

            decision = CategoryPolicyDecision(
                action=action,
                domain=clean,
                category=cat,
                confidence=conf,
                reason=reason,
                is_exempt=False,
                is_whitelisted=False,
                profile_name=self._profile.name,
                timestamp=now
            )

            self._cache_decision(clean, decision, now)
            return decision

    def _cache_decision(self, domain: str, decision: CategoryPolicyDecision, now: float) -> None:
        """Evicts oldest entries if at capacity, then caches result."""
        if len(self._cache) >= self._cache_capacity:
            # Evict first 100 keys
            keys_to_remove = list(self._cache.keys())[:100]
            for k in keys_to_remove:
                self._cache.pop(k, None)

        self._cache[domain] = (decision, now + self._cache_ttl)

    # --------------------------------------------------------------------------
    # Telemetry & Diagnostics
    # --------------------------------------------------------------------------

    def get_telemetry(self) -> Dict[str, Any]:
        """Returns snapshot of category policy routing telemetry."""
        with self._lock:
            return {
                "active_profile": self._profile.name,
                "is_locked": self.is_locked,
                "countdown_seconds": self._countdown_seconds,
                "whitelist_count": len(self._whitelist),
                "total_evaluations": self._total_evaluations,
                "blocked_evaluations": self._blocked_evaluations,
                "allowed_evaluations": self._allowed_evaluations,
                "exempt_evaluations": self._exempt_evaluations,
                "cache_hits": self._cache_hits,
                "cache_size": len(self._cache),
                "category_blocks": dict(self._category_blocks)
            }

    def reset_telemetry(self) -> None:
        """Resets telemetry counters."""
        with self._lock:
            self._total_evaluations = 0
            self._blocked_evaluations = 0
            self._allowed_evaluations = 0
            self._exempt_evaluations = 0
            self._cache_hits = 0
            for k in self._category_blocks:
                self._category_blocks[k] = 0
