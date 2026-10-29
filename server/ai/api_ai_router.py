"""
FocusDNS AI Engine - Threat Hunting REST API Router
Exposes high-performance RESTful endpoints for zero-day phishing, IDN homograph,
DGA neural classification, and dynamic category routing.
Enforces the Conditional Whitelisting Law and Life Safety exemptions across all endpoints.
"""

import json
import logging
import time
from typing import Dict, Any, Optional, Tuple, List

from server.ai.threat_hunting_engine import (
    ThreatHuntingEngine,
    ThreatVerdict,
    get_global_threat_engine,
)
from server.ai.homograph_engine import HomographEngine
from server.ai.dga_neural_classifier import DGANeuralClassifier
from server.ai.domain_categorizer import DomainCategorizer
from server.ai.zero_hour_phishing import ZeroHourPhishingDetector, LIFE_SAFETY_EXEMPTIONS
from server.ai.model_checkpoint_manager import ModelCheckpointManager

logger = logging.getLogger("FocusDNS.AI.ApiRouter")


class AIApiDispatcher:
    """
    Handles routing and execution of /api/v1/ai/* HTTP requests.
    Compatible with BaseHTTPRequestHandler or standalone HTTP servers.
    """

    def __init__(
        self,
        engine: Optional[ThreatHuntingEngine] = None,
        checkpoint_dir: str = "/tmp/focusdns/ai_models",
    ):
        self.engine = engine or get_global_threat_engine()
        self.homograph_engine = HomographEngine()
        self.dga_classifier = DGANeuralClassifier()
        self.categorizer = DomainCategorizer()
        self.phishing_detector = ZeroHourPhishingDetector()
        self.checkpoint_manager = ModelCheckpointManager(checkpoint_dir=checkpoint_dir)

    def handle_get(self, path: str, params: Dict[str, List[str]]) -> Optional[Tuple[int, Dict[str, Any]]]:
        """
        Dispatches GET requests for AI endpoints.
        Returns (status_code, response_dict) or None if path not matched.
        """
        clean_path = path.rstrip("/")

        # 1. Telemetry & Performance Metrics
        if clean_path in ("/api/v1/ai/telemetry", "/api/ai/telemetry"):
            metrics = self.engine.get_telemetry()
            return 200, {
                "success": True,
                "timestamp": int(time.time()),
                "metrics": metrics,
            }

        # 2. Model Checkpoint & Runtime Status
        if clean_path in ("/api/v1/ai/models/status", "/api/ai/models/status"):
            return 200, {
                "success": True,
                "timestamp": int(time.time()),
                "status": {
                    "engine_state": "ACTIVE",
                    "focus_locked": self.engine.is_locked(),
                    "cache_entries": len(self.engine._cache),
                    "models": {
                        "dga_neural_classifier": {
                            "version": self.checkpoint_manager.get_version("dga_mlp") or "1.0-embedded",
                            "architecture": "MLP (16 -> 32 -> 16 -> 1)",
                            "parameters": 1057,
                        },
                        "homograph_detector": {
                            "version": "1.0-tr39",
                            "standard": "Unicode TR39 Confusables",
                            "protected_brands": 35,
                        },
                        "zero_hour_phishing": {
                            "version": "1.0-heuristic-entropy",
                            "life_safety_exemptions": len(LIFE_SAFETY_EXEMPTIONS),
                        },
                        "domain_categorizer": {
                            "version": "1.0-tfidf-softmax",
                            "categories": 8,
                        },
                    },
                },
            }

        # 3. Life-Safety Exemption Roster
        if clean_path in ("/api/v1/ai/exemptions", "/api/ai/exemptions"):
            return 200, {
                "success": True,
                "exemptions": list(sorted(LIFE_SAFETY_EXEMPTIONS)),
                "policy": "UNCONDITIONAL_PASS",
            }

        # 4. Whitelist Inspection
        if clean_path in ("/api/v1/ai/whitelist", "/api/ai/whitelist"):
            return 200, {
                "success": True,
                "whitelist": list(sorted(self.engine._whitelist)),
                "is_locked": self.engine.is_locked(),
            }

        return None

    def handle_post(
        self, path: str, payload: Dict[str, Any]
    ) -> Optional[Tuple[int, Dict[str, Any]]]:
        """
        Dispatches POST requests for AI endpoints.
        Returns (status_code, response_dict) or None if path not matched.
        """
        clean_path = path.rstrip("/")

        # 1. Single Domain Threat Hunting: /api/v1/ai/hunt
        if clean_path in ("/api/v1/ai/hunt", "/api/ai/hunt"):
            domain = payload.get("domain", "").strip()
            if not domain:
                return 400, {"success": False, "error": "Missing required field: 'domain'"}

            verdict: ThreatVerdict = self.engine.analyze(domain)
            return 200, {
                "success": True,
                "verdict": verdict.to_dict(),
            }

        # 2. Batch Domain Threat Hunting: /api/v1/ai/hunt-batch
        if clean_path in ("/api/v1/ai/hunt-batch", "/api/ai/hunt-batch"):
            domains = payload.get("domains", [])
            if not isinstance(domains, list):
                return 400, {"success": False, "error": "'domains' must be a JSON array"}
            if len(domains) > 1000:
                return 400, {"success": False, "error": "Batch size cannot exceed 1000 domains"}

            results = []
            for d in domains:
                if isinstance(d, str) and d.strip():
                    v = self.engine.analyze(d.strip())
                    results.append(v.to_dict())

            return 200, {
                "success": True,
                "count": len(results),
                "results": results,
            }

        # 3. IDN Homograph & Typosquatting Check: /api/v1/ai/homograph-check
        if clean_path in ("/api/v1/ai/homograph-check", "/api/ai/homograph-check"):
            domain = payload.get("domain", "").strip()
            if not domain:
                return 400, {"success": False, "error": "Missing required field: 'domain'"}

            h_res = self.homograph_engine.analyze(domain)
            return 200, {
                "success": True,
                "result": h_res.to_dict(),
            }

        # 4. DGA Neural Classifier: /api/v1/ai/dga-classify
        if clean_path in ("/api/v1/ai/dga-classify", "/api/ai/dga-classify"):
            domain = payload.get("domain", "").strip()
            if not domain:
                return 400, {"success": False, "error": "Missing required field: 'domain'"}

            dga_res = self.dga_classifier.classify(domain)
            return 200, {
                "success": True,
                "result": dga_res.to_dict(),
            }

        # 5. Multi-Class Domain Categorization: /api/v1/ai/categorize
        if clean_path in ("/api/v1/ai/categorize", "/api/ai/categorize"):
            domain = payload.get("domain", "").strip()
            if not domain:
                return 400, {"success": False, "error": "Missing required field: 'domain'"}

            cat_res = self.categorizer.predict(domain)
            return 200, {
                "success": True,
                "result": cat_res.to_dict(),
            }

        # 6. Zero-Hour Phishing Analysis: /api/v1/ai/phishing-check
        if clean_path in ("/api/v1/ai/phishing-check", "/api/ai/phishing-check"):
            domain = payload.get("domain", "").strip()
            if not domain:
                return 400, {"success": False, "error": "Missing required field: 'domain'"}

            phish_res = self.phishing_detector.analyze(domain)
            return 200, {
                "success": True,
                "result": phish_res.to_dict(),
            }

        # 7. Focus Lock Control: /api/v1/ai/lock
        if clean_path in ("/api/v1/ai/lock", "/api/ai/lock"):
            duration = int(payload.get("duration_seconds", 1800))
            self.engine.set_focus_lock(active=True, remaining_seconds=duration)
            return 200, {
                "success": True,
                "message": f"Focus lock activated for {duration} seconds.",
                "locked": True,
                "remaining_seconds": duration,
            }

        # 8. Focus Unlock Control: /api/v1/ai/unlock
        if clean_path in ("/api/v1/ai/unlock", "/api/ai/unlock"):
            # Enforce that unlock only succeeds if authorized or force flag provided
            force = payload.get("force", False)
            if self.engine.is_locked() and not force:
                return 403, {
                    "success": False,
                    "error": "Cannot unlock while active timer is running without override authorization.",
                }
            self.engine.set_focus_lock(active=False, remaining_seconds=0)
            return 200, {
                "success": True,
                "message": "Focus lock successfully disabled. Idle mode active.",
                "locked": False,
            }

        # 9. Whitelist Addition with Conditional Whitelisting Law Enforcement: /api/v1/ai/whitelist
        if clean_path in ("/api/v1/ai/whitelist", "/api/ai/whitelist"):
            domain = payload.get("domain", "").strip()
            requester = payload.get("requester", "admin")
            if not domain:
                return 400, {"success": False, "error": "Missing required field: 'domain'"}

            try:
                # ThreatHuntingEngine raises PermissionError if locked
                self.engine.add_whitelist(domain, requester=requester)
                return 200, {
                    "success": True,
                    "message": f"Domain '{domain}' successfully added to whitelist.",
                    "domain": domain,
                }
            except PermissionError as pe:
                logger.warning(f"Whitelist attempt rejected: {pe}")
                return 403, {
                    "success": False,
                    "error": str(pe),
                    "code": "ERROR_ACCESS_DENIED",
                    "errno": 5,
                }

        # 10. Whitelist Removal: /api/v1/ai/whitelist/remove
        if clean_path in ("/api/v1/ai/whitelist/remove", "/api/ai/whitelist/remove"):
            domain = payload.get("domain", "").strip()
            requester = payload.get("requester", "admin")
            if not domain:
                return 400, {"success": False, "error": "Missing required field: 'domain'"}

            try:
                self.engine.remove_whitelist(domain, requester=requester)
                return 200, {
                    "success": True,
                    "message": f"Domain '{domain}' removed from whitelist.",
                }
            except PermissionError as pe:
                return 403, {
                    "success": False,
                    "error": str(pe),
                    "code": "ERROR_ACCESS_DENIED",
                    "errno": 5,
                }

        # 11. Cache Flush: /api/v1/ai/cache/flush
        if clean_path in ("/api/v1/ai/cache/flush", "/api/ai/cache/flush"):
            flushed = self.engine.flush_cache()
            return 200, {
                "success": True,
                "flushed_entries": flushed,
            }

        return None
