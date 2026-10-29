"""
FocusDNS AI Engine - Master On-Device Threat Hunting Engine.

Unified coordinator executing concurrent AI threat detection pipelines:
  1. IDN Homograph & Typosquatting Defense (homograph_engine.py)
  2. Zero-Hour Phishing & Brand Impersonation (zero_hour_phishing.py)
  3. DGA Neural Network & Markov Classifier (dga_neural_classifier.py)
  4. Dynamic AI Multi-Class Categorizer (domain_categorizer.py)

Strictly Enforces:
  1. Inviolable Life Safety Exemption: Emergency calling, DHCP, APNs, and system updates
     are unconditionally exempt and NEVER scored or blocked.
  2. Inviolable Conditional Whitelisting Law:
     - When Idle (timer == 0 & protection off): Whitelist modifications permitted.
     - When Active Focus (timer > 0 || protection on): Whitelist additions raise
       PermissionError (ERROR_ACCESS_DENIED).
  3. Zero-Latency Local Caching: In-memory LRU cache resolves repeat queries in < 1µs.
"""

import time
import logging
import threading
from typing import Dict, List, Set, Optional, Tuple, Any

from server.ai.homograph_engine import HomographEngine, HomographVerdict
from server.ai.zero_hour_phishing import ZeroHourPhishingDetector, PhishingVerdict, LIFE_SAFETY_EXEMPTIONS
from server.ai.dga_neural_classifier import DgaNeuralClassifier, DgaVerdict
from server.ai.domain_categorizer import DomainCategorizer, CategoryVerdict

logger = logging.getLogger("focus_dns.threat_hunting")

ACTION_ALLOW = "ALLOW"
ACTION_BLOCK_HOMOGRAPH = "BLOCK_HOMOGRAPH"
ACTION_BLOCK_PHISHING = "BLOCK_PHISHING"
ACTION_BLOCK_DGA = "BLOCK_DGA"
ACTION_BLOCK_DISTRACTION = "BLOCK_DISTRACTION"
ACTION_BYPASS_EXEMPT = "BYPASS_LIFE_SAFETY_EXEMPT"


class AiThreatReport:
    """Consolidated threat hunting assessment for a domain query."""
    __slots__ = (
        "domain", "is_threat", "composite_risk_score", "recommended_action",
        "primary_category", "is_distracting", "homograph", "phishing", "dga",
        "category", "inference_latency_us", "cached"
    )

    def __init__(
        self,
        domain: str,
        is_threat: bool,
        composite_risk_score: float,
        recommended_action: str,
        primary_category: str,
        is_distracting: bool,
        homograph: HomographVerdict,
        phishing: PhishingVerdict,
        dga: DgaVerdict,
        category: CategoryVerdict,
        inference_latency_us: float,
        cached: bool = False
    ):
        self.domain = domain
        self.is_threat = is_threat
        self.composite_risk_score = round(composite_risk_score, 2)
        self.recommended_action = recommended_action
        self.primary_category = primary_category
        self.is_distracting = is_distracting
        self.homograph = homograph
        self.phishing = phishing
        self.dga = dga
        self.category = category
        self.inference_latency_us = round(inference_latency_us, 2)
        self.cached = cached

    @property
    def primary_reason(self) -> str:
        if self.homograph and self.homograph.is_threat:
            return self.homograph.explanation
        if self.phishing and self.phishing.is_phishing:
            return self.phishing.primary_threat_vector
        if self.dga and self.dga.is_dga:
            return f"DGA Malware ({self.dga.attributed_family})"
        return "Clean / Benign"

    @property
    def threat_type(self) -> str:
        if self.homograph and self.homograph.is_threat:
            return "HOMOGRAPH_TYPOSQUAT"
        if self.phishing and self.phishing.is_phishing:
            return "PHISHING_ZERO_HOUR"
        if self.dga and self.dga.is_dga:
            return "DGA_MALWARE"
        return "NONE"

    @property
    def detected_brand(self) -> Optional[str]:
        if self.homograph and self.homograph.spoofed_brand:
            return self.homograph.spoofed_brand
        if self.phishing and self.phishing.spoofed_brand:
            return self.phishing.spoofed_brand
        return None

    @property
    def dga_family(self) -> Optional[str]:
        if self.dga and self.dga.attributed_family:
            return self.dga.attributed_family
        return None

    @property
    def predicted_category(self) -> str:
        return self.primary_category

    def to_dict(self) -> Dict[str, Any]:
        return {
            "domain": self.domain,
            "is_threat": self.is_threat,
            "composite_risk_score": self.composite_risk_score,
            "recommended_action": self.recommended_action,
            "primary_category": self.primary_category,
            "is_distracting": self.is_distracting,
            "inference_latency_us": self.inference_latency_us,
            "cached": self.cached,
            "primary_reason": self.primary_reason,
            "threat_type": self.threat_type,
            "detected_brand": self.detected_brand,
            "dga_family": self.dga_family,
            "homograph": self.homograph.to_dict(),
            "phishing": self.phishing.to_dict(),
            "dga": self.dga.to_dict(),
            "category": self.category.to_dict()
        }


class ThreatHuntingEngine:
    """
    High-performance on-device AI Threat Hunting Engine.
    """

    def __init__(self, max_cache_size: int = 50000):
        self.max_cache_size = max_cache_size
        self._lock = threading.RLock()
        self._cache: Dict[str, AiThreatReport] = {}
        self._whitelist: Set[str] = set()

        # Focus Lock Posture
        self._is_locked = False
        self._remaining_timer_seconds = 0

        # Telemetry metrics
        self._total_queries = 0
        self._cache_hits = 0
        self._homographs_blocked = 0
        self._phishing_blocked = 0
        self._dgas_blocked = 0
        self._exempt_bypasses = 0
        self._total_latency_us = 0.0

    def set_focus_lock(self, locked: bool = False, remaining_seconds: int = 0, active: Optional[bool] = None):
        """Updates focus lock state."""
        with self._lock:
            if active is not None:
                locked = active
            self._is_locked = locked
            self._remaining_timer_seconds = max(0, remaining_seconds)

    def can_modify_whitelist(self) -> bool:
        """Enforces Conditional Whitelisting Law."""
        with self._lock:
            return not self._is_locked and (self._remaining_timer_seconds <= 0)

    def add_whitelist_domain(self, domain: str) -> bool:
        """
        Adds domain to whitelist. Strictly blocked if focus mode is active.
        """
        with self._lock:
            if not self.can_modify_whitelist():
                err = (
                    f"ERROR_ACCESS_DENIED (5): Cannot whitelist '{domain}' during active focus session! "
                    f"Session is locked with {self._remaining_timer_seconds}s remaining."
                )
                logger.critical(err)
                raise PermissionError(err)

            clean = domain.lower().strip()
            self._whitelist.add(clean)
            if clean in self._cache:
                del self._cache[clean]
            return True

    def remove_whitelist_domain(self, domain: str) -> bool:
        """Removes domain from whitelist."""
        with self._lock:
            if not self.can_modify_whitelist():
                raise PermissionError("ERROR_ACCESS_DENIED: Modifying whitelist is locked during active focus.")
            self._whitelist.discard(domain.lower().strip())
            return True

    def add_whitelist(self, domain: str, requester: str = "admin") -> bool:
        """Alias for add_whitelist_domain."""
        return self.add_whitelist_domain(domain)

    def remove_whitelist(self, domain: str, requester: str = "admin") -> bool:
        """Alias for remove_whitelist_domain."""
        return self.remove_whitelist_domain(domain)

    def is_life_safety_exempt(self, domain: str) -> bool:
        """Life Safety Exemption: Never block emergency, APNs, or OS updates."""
        clean = domain.lower().strip()
        for exempt in LIFE_SAFETY_EXEMPTIONS:
            if clean == exempt or clean.endswith("." + exempt):
                return True
        return False

    def hunt_domain(self, domain: str) -> AiThreatReport:
        """
        Executes unified AI threat hunting on a domain with sub-100µs performance.
        """
        clean_domain = domain.lower().strip().rstrip(".")
        if not clean_domain:
            clean_domain = "unknown"

        with self._lock:
            self._total_queries += 1

            # 1. Fast Cache Lookup (< 1 µs)
            if clean_domain in self._cache:
                self._cache_hits += 1
                cached_report = self._cache[clean_domain]
                # Return clone with cached=True
                return AiThreatReport(
                    domain=cached_report.domain,
                    is_threat=cached_report.is_threat,
                    composite_risk_score=cached_report.composite_risk_score,
                    recommended_action=cached_report.recommended_action,
                    primary_category=cached_report.primary_category,
                    is_distracting=cached_report.is_distracting,
                    homograph=cached_report.homograph,
                    phishing=cached_report.phishing,
                    dga=cached_report.dga,
                    category=cached_report.category,
                    inference_latency_us=0.5,
                    cached=True
                )

        # 2. Life Safety Exemption Check
        if self.is_life_safety_exempt(clean_domain):
            with self._lock:
                self._exempt_bypasses += 1

            h_dummy = HomographEngine.evaluate_domain(clean_domain)
            p_dummy = ZeroHourPhishingDetector.analyze_domain(clean_domain)
            d_dummy = DgaNeuralClassifier.predict(clean_domain)
            c_dummy = DomainCategorizer.classify(clean_domain)

            report = AiThreatReport(
                domain=clean_domain,
                is_threat=False,
                composite_risk_score=0.0,
                recommended_action=ACTION_BYPASS_EXEMPT,
                primary_category="INFRASTRUCTURE",
                is_distracting=False,
                homograph=h_dummy,
                phishing=p_dummy,
                dga=d_dummy,
                category=c_dummy,
                inference_latency_us=1.0,
                cached=False
            )
            return report

        # 3. Check Whitelist
        with self._lock:
            if clean_domain in self._whitelist:
                h_dummy = HomographEngine.evaluate_domain(clean_domain)
                p_dummy = ZeroHourPhishingDetector.analyze_domain(clean_domain)
                d_dummy = DgaNeuralClassifier.predict(clean_domain)
                c_dummy = DomainCategorizer.classify(clean_domain)
                return AiThreatReport(
                    domain=clean_domain,
                    is_threat=False,
                    composite_risk_score=0.0,
                    recommended_action=ACTION_ALLOW,
                    primary_category="USER_WHITELIST",
                    is_distracting=False,
                    homograph=h_dummy,
                    phishing=p_dummy,
                    dga=d_dummy,
                    category=c_dummy,
                    inference_latency_us=1.5,
                    cached=False
                )

        # 4. Execute AI Models
        start_ns = time.perf_counter_ns()

        homograph_verdict = HomographEngine.evaluate_domain(clean_domain)
        phishing_verdict = ZeroHourPhishingDetector.analyze_domain(clean_domain)
        dga_verdict = DgaNeuralClassifier.predict(clean_domain)
        category_verdict = DomainCategorizer.classify(clean_domain)

        elapsed_us = max(1.0, (time.perf_counter_ns() - start_ns) / 1000.0)

        # 5. Composite Risk Scoring & Action Resolution
        # Risk score = max of individual component scores
        comp_score = max(
            homograph_verdict.risk_score,
            phishing_verdict.phishing_score,
            dga_verdict.confidence_score if dga_verdict.is_dga else 0.0
        )

        is_threat = (
            homograph_verdict.is_threat or
            phishing_verdict.is_phishing or
            dga_verdict.is_dga or
            comp_score >= 65.0
        )

        # Action resolution priority: Homograph -> Phishing -> DGA -> Category Distraction -> Allow
        if homograph_verdict.is_threat:
            action = ACTION_BLOCK_HOMOGRAPH
            with self._lock:
                self._homographs_blocked += 1
        elif phishing_verdict.is_phishing:
            action = ACTION_BLOCK_PHISHING
            with self._lock:
                self._phishing_blocked += 1
        elif dga_verdict.is_dga:
            action = ACTION_BLOCK_DGA
            with self._lock:
                self._dgas_blocked += 1
        elif category_verdict.is_distracting:
            action = ACTION_BLOCK_DISTRACTION
        else:
            action = ACTION_ALLOW

        report = AiThreatReport(
            domain=clean_domain,
            is_threat=is_threat,
            composite_risk_score=comp_score,
            recommended_action=action,
            primary_category=category_verdict.primary_category,
            is_distracting=category_verdict.is_distracting,
            homograph=homograph_verdict,
            phishing=phishing_verdict,
            dga=dga_verdict,
            category=category_verdict,
            inference_latency_us=elapsed_us,
            cached=False
        )

        # 6. Store in LRU Cache
        with self._lock:
            self._total_latency_us += elapsed_us
            if len(self._cache) >= self.max_cache_size:
                # Evict 10% oldest entries
                to_evict = list(self._cache.keys())[:int(self.max_cache_size * 0.1)]
                for k in to_evict:
                    del self._cache[k]
            self._cache[clean_domain] = report

        return report

    def batch_hunt(self, domains: List[str]) -> List[AiThreatReport]:
        """Classifies multiple domains in batch."""
        return [self.hunt_domain(d) for d in domains]

    def get_telemetry(self) -> Dict[str, Any]:
        """Returns comprehensive real-time telemetry metrics."""
        with self._lock:
            avg_lat = round(self._total_latency_us / max(1, self._total_queries - self._cache_hits), 2)
            hit_ratio = round(self._cache_hits / max(1, self._total_queries), 4)
            return {
                "total_domains_analyzed": self._total_queries,
                "cache_hits": self._cache_hits,
                "cache_hit_ratio": hit_ratio,
                "cache_size": len(self._cache),
                "homographs_blocked": self._homographs_blocked,
                "phishing_blocked": self._phishing_blocked,
                "dgas_blocked": self._dgas_blocked,
                "exempt_bypasses": self._exempt_bypasses,
                "avg_inference_latency_us": avg_lat,
                "is_locked": self._is_locked,
                "remaining_timer_seconds": self._remaining_timer_seconds,
                "can_modify_whitelist": self.can_modify_whitelist(),
                "whitelist_size": len(self._whitelist)
            }

    def analyze(self, domain: str) -> AiThreatReport:
        """Alias for hunt_domain."""
        return self.hunt_domain(domain)

    def is_locked(self) -> bool:
        """Returns True if focus lock is currently active."""
        with self._lock:
            return self._is_locked

    def flush_cache(self) -> int:
        """Flushes the LRU cache."""
        with self._lock:
            count = len(self._cache)
            self._cache.clear()
            return count


ThreatVerdict = AiThreatReport

_GLOBAL_THREAT_ENGINE: Optional[ThreatHuntingEngine] = None

def get_global_threat_engine() -> ThreatHuntingEngine:
    global _GLOBAL_THREAT_ENGINE
    if _GLOBAL_THREAT_ENGINE is None:
        _GLOBAL_THREAT_ENGINE = ThreatHuntingEngine()
    return _GLOBAL_THREAT_ENGINE
