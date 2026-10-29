"""
FocusDNS Engine - On-Device AI Threat Hunting Pipeline Hook
Seamlessly integrates the sub-microsecond AI threat hunting engine, DGA neural
classifier, and Unicode TR39 homograph detector into the main DNS resolution pipeline.
Enforces hardcoded Life-Safety exemptions and the Conditional Whitelisting Law.
"""

import logging
import threading
import time
from typing import Dict, Any, Optional, Tuple, Set

from server.ai.threat_hunting_engine import ThreatHuntingEngine, ThreatVerdict
from server.ai.zero_hour_phishing import LIFE_SAFETY_EXEMPTIONS

logger = logging.getLogger("FocusDNS.AI.PipelineHook")


class AIInterceptVerdict:
    """Represents the real-time AI decision on a DNS query."""

    def __init__(
        self,
        domain: str,
        is_threat: bool,
        action: str,  # "ALLOW", "BLOCK", "SINKHOLE", "FLAG_SUSPICIOUS"
        risk_score: float,
        reason: str,
        threat_type: str,
        detected_brand: Optional[str] = None,
        dga_family: Optional[str] = None,
        category: str = "Unclassified",
        latency_us: float = 0.0,
    ):
        self.domain = domain
        self.is_threat = is_threat
        self.action = action
        self.risk_score = risk_score
        self.reason = reason
        self.threat_type = threat_type
        self.detected_brand = detected_brand
        self.dga_family = dga_family
        self.category = category
        self.latency_us = latency_us

    def to_dict(self) -> Dict[str, Any]:
        return {
            "domain": self.domain,
            "is_threat": self.is_threat,
            "action": self.action,
            "risk_score": self.risk_score,
            "reason": self.reason,
            "threat_type": self.threat_type,
            "detected_brand": self.detected_brand,
            "dga_family": self.dga_family,
            "category": self.category,
            "latency_us": round(self.latency_us, 2),
        }


class AIPipelineHook:
    """
    Sub-microsecond DNS interception hook for on-device AI threat hunting.
    Acts as an intelligent security filter placed between local rule checks
    and upstream forwarders.
    """

    def __init__(
        self,
        threat_engine: Optional[ThreatHuntingEngine] = None,
        enabled: bool = True,
        block_threshold: float = 65.0,
        sinkhole_ip: str = "0.0.0.0",
    ):
        self.threat_engine = threat_engine or ThreatHuntingEngine()
        self.enabled = enabled
        self.block_threshold = block_threshold
        self.sinkhole_ip = sinkhole_ip

        # Thread-safe metrics
        self._lock = threading.RLock()
        self._total_queries = 0
        self._total_threats_blocked = 0
        self._homographs_blocked = 0
        self._dga_blocked = 0
        self._phishing_blocked = 0
        self._exemptions_passed = 0
        self._total_latency_us = 0.0

        # Life safety hardcoded set
        self.exemptions: Set[str] = set(LIFE_SAFETY_EXEMPTIONS)

    def is_life_safety_exempt(self, domain: str) -> bool:
        """
        Hardcoded absolute bypass: Emergency services, Apple APNs,
        Windows Update, Google Play Services.
        """
        clean = domain.lower().strip().rstrip(".")
        if clean in self.exemptions:
            return True
        for exempt in self.exemptions:
            if clean.endswith("." + exempt):
                return True
        return False

    def intercept_query(
        self,
        domain: str,
        client_ip: str = "127.0.0.1",
        qtype: str = "A",
    ) -> AIInterceptVerdict:
        """
        Evaluates a DNS query through the on-device AI models.
        Returns AIInterceptVerdict indicating whether to allow, block, or sinkhole.
        """
        t0 = time.perf_counter()
        clean_domain = domain.lower().strip().rstrip(".")

        # 1. Hardcoded Life-Safety Exemption Fast-Path
        if self.is_life_safety_exempt(clean_domain):
            elapsed_us = (time.perf_counter() - t0) * 1_000_000
            with self._lock:
                self._total_queries += 1
                self._exemptions_passed += 1
                self._total_latency_us += elapsed_us
            return AIInterceptVerdict(
                domain=clean_domain,
                is_threat=False,
                action="ALLOW",
                risk_score=0.0,
                reason="Life-Safety Exemption: Emergency/Critical Infrastructure",
                threat_type="NONE",
                latency_us=elapsed_us,
            )

        # 2. If AI engine is disabled, pass through
        if not self.enabled:
            elapsed_us = (time.perf_counter() - t0) * 1_000_000
            return AIInterceptVerdict(
                domain=clean_domain,
                is_threat=False,
                action="ALLOW",
                risk_score=0.0,
                reason="AI Hook Disabled",
                threat_type="NONE",
                latency_us=elapsed_us,
            )

        # 3. Perform AI Threat Hunt Analysis
        verdict: ThreatVerdict = self.threat_engine.analyze(clean_domain)
        elapsed_us = (time.perf_counter() - t0) * 1_000_000

        # Determine action
        is_threat = verdict.is_threat or verdict.composite_risk_score >= self.block_threshold
        action = "BLOCK" if is_threat else "ALLOW"

        # Update metrics
        with self._lock:
            self._total_queries += 1
            self._total_latency_us += elapsed_us
            if is_threat:
                self._total_threats_blocked += 1
                if verdict.threat_type == "HOMOGRAPH_TYPOSQUAT":
                    self._homographs_blocked += 1
                elif verdict.threat_type == "DGA_MALWARE":
                    self._dga_blocked += 1
                elif verdict.threat_type in ("PHISHING_ZERO_HOUR", "PHISHING_HEURISTIC"):
                    self._phishing_blocked += 1

        return AIInterceptVerdict(
            domain=clean_domain,
            is_threat=is_threat,
            action=action,
            risk_score=verdict.composite_risk_score,
            reason=verdict.primary_reason,
            threat_type=verdict.threat_type,
            detected_brand=verdict.detected_brand,
            dga_family=verdict.dga_family,
            category=verdict.predicted_category,
            latency_us=elapsed_us,
        )

    def add_whitelist_entry(self, domain: str, requester: str = "admin") -> bool:
        """
        Enforces Conditional Whitelisting Law:
        Allowed with zero friction when idle.
        Strictly raises PermissionError when active focus mode or countdown timer > 0.
        """
        clean = domain.lower().strip().rstrip(".")
        # Delegates directly to ThreatHuntingEngine which enforces the law
        return self.threat_engine.add_whitelist(clean, requester)

    def set_focus_lock(self, active: bool, remaining_seconds: int = 0):
        """Sets active focus lockdown state."""
        self.threat_engine.set_focus_lock(active, remaining_seconds)

    def get_metrics(self) -> Dict[str, Any]:
        """Returns real-time telemetry metrics of the AI pipeline hook."""
        with self._lock:
            avg_latency = (
                (self._total_latency_us / self._total_queries)
                if self._total_queries > 0
                else 0.0
            )
            return {
                "total_queries_analyzed": self._total_queries,
                "total_threats_blocked": self._total_threats_blocked,
                "homographs_blocked": self._homographs_blocked,
                "dga_blocked": self._dga_blocked,
                "phishing_blocked": self._phishing_blocked,
                "exemptions_passed": self._exemptions_passed,
                "avg_inference_latency_us": round(avg_latency, 2),
                "is_active_focus_locked": self.threat_engine.is_locked(),
                "cache_size": len(self.threat_engine._cache),
            }

    def reset_metrics(self):
        """Resets telemetry counters."""
        with self._lock:
            self._total_queries = 0
            self._total_threats_blocked = 0
            self._homographs_blocked = 0
            self._dga_blocked = 0
            self._phishing_blocked = 0
            self._exemptions_passed = 0
            self._total_latency_us = 0.0


def register_ai_threat_hook(pipeline, hook: Optional[AIPipelineHook] = None) -> AIPipelineHook:
    """
    Registers AIPipelineHook into a UnifiedDNSProcessingPipeline instance.
    Attaches the hook to pipeline.ai_hook attribute.
    """
    if hook is None:
        hook = AIPipelineHook()
    pipeline.ai_hook = hook
    logger.info("AIPipelineHook successfully registered to DNS processing pipeline.")
    return hook
