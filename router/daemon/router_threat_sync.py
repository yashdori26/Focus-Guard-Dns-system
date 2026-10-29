"""
FocusDNS Router Gateway - Threat Model Synchronization & Autonomous Health Watchdog
Handles offline-first autonomous AI threat hunting, atomic model checkpoint updates,
HMAC integrity verification, and runtime health diagnostics for edge routers.
"""

import hashlib
import hmac
import json
import logging
import math
import os
import shutil
import tempfile
import threading
import time
from typing import Dict, Any, Optional, Tuple, Callable

from server.ai.model_checkpoint_manager import ModelCheckpointManager, ModelCheckpointError
from server.ai.threat_hunting_engine import ThreatHuntingEngine, get_global_threat_engine

logger = logging.getLogger("FocusDNS.Router.ThreatSync")


class RouterThreatSyncAgent:
    """
    Synchronizes neural network weights and TR39 confusable definitions to edge routers.
    Operates 100% autonomously when disconnected from the WAN.
    """

    DEFAULT_SYNC_SECRET = b"FocusDNS-Router-Edge-Sync-Secret-Key-2026"

    def __init__(
        self,
        checkpoint_dir: str = "/tmp/focusdns/router_models",
        sync_secret: Optional[bytes] = None,
        threat_engine: Optional[ThreatHuntingEngine] = None
    ):
        self.checkpoint_dir = checkpoint_dir
        self.sync_secret = sync_secret or self.DEFAULT_SYNC_SECRET
        self.threat_engine = threat_engine or get_global_threat_engine()
        self.checkpoint_manager = ModelCheckpointManager(
            checkpoint_dir=self.checkpoint_dir,
            hmac_key=self.sync_secret
        )
        self._lock = threading.RLock()
        self._is_autonomous_mode = True
        self._last_successful_sync = 0.0
        self._sync_history: list = []
        self._health_status = "HEALTHY"

        os.makedirs(self.checkpoint_dir, exist_ok=True)

    def verify_update_payload(self, raw_bytes: bytes, signature_hex: str) -> bool:
        """Verifies HMAC-SHA256 signature of incoming edge sync package."""
        calc_hmac = hmac.new(self.sync_secret, raw_bytes, hashlib.sha256).hexdigest()
        return hmac.compare_digest(calc_hmac, signature_hex)

    def apply_model_update(
        self,
        model_name: str,
        version: str,
        weights_dict: Dict[str, Any],
        signature_hex: str
    ) -> bool:
        """
        Atomically updates on-router model weights after cryptographic verification.
        Validates model health before applying to prevent bricking router DNS.
        """
        with self._lock:
            payload_str = json.dumps(weights_dict, sort_keys=True)
            payload_bytes = payload_str.encode("utf-8")

            if not self.verify_update_payload(payload_bytes, signature_hex):
                logger.error(f"Sync rejected: Invalid HMAC signature for model '{model_name}'")
                raise PermissionError("ERROR_INTEGRITY_VIOLATION: HMAC verification failed")

            # Health validation pass: ensure weights contain no NaNs or Infinities
            if not self._validate_weights_sanity(weights_dict):
                logger.error(f"Sync rejected: Weights sanity check failed for '{model_name}'")
                raise ValueError("ERROR_INVALID_MODEL: Weights contained NaNs or abnormal magnitudes")

            # Save checkpoint atomically
            filepath = self.checkpoint_manager.save_checkpoint(
                model_name=model_name,
                version=version,
                weights_dict=weights_dict,
                metadata={"applied_by": "RouterThreatSyncAgent", "router_timestamp": time.time()}
            )

            self._last_successful_sync = time.time()
            self._sync_history.append({
                "model_name": model_name,
                "version": version,
                "timestamp": int(self._last_successful_sync),
                "filepath": filepath,
                "status": "SUCCESS"
            })
            if len(self._sync_history) > 100:
                self._sync_history.pop(0)

            logger.info(f"Model update '{model_name}' v{version} successfully installed on router.")
            return True

    def _validate_weights_sanity(self, weights: Dict[str, Any]) -> bool:
        """Inspects numeric values for NaNs, Infs, or unbounded explosions."""
        for k, val in weights.items():
            if isinstance(val, (int, float)):
                if not (math.isfinite(val) and -1e6 < val < 1e6):
                    return False
            elif isinstance(val, list):
                if not self._validate_list_sanity(val):
                    return False
            elif isinstance(val, dict):
                if not self._validate_weights_sanity(val):
                    return False
        return True

    def _validate_list_sanity(self, lst: list) -> bool:
        for item in lst:
            if isinstance(item, (int, float)):
                if not (math.isfinite(item) and -1e6 < item < 1e6):
                    return False
            elif isinstance(item, list):
                if not self._validate_list_sanity(item):
                    return False
        return True

    def run_health_diagnostic(self) -> Dict[str, Any]:
        """
        Executes end-to-end self-test of the on-router AI engine.
        Tests:
          1. TR39 Confusable Skeleton decomposition
          2. DGA Neural Classifier forward-pass
          3. Life-Safety Exemption bypass guarantee
        """
        with self._lock:
            diagnostic_results: Dict[str, Any] = {
                "timestamp": int(time.time()),
                "passed": True,
                "checks": {}
            }

            # 1. TR39 Confusable Test: Cyrillic 'а' in apple
            try:
                cyrillic_apple = "\u0430pple.com"
                rep = self.threat_engine.hunt_domain(cyrillic_apple)
                passed = rep.is_threat and rep.threat_type == "HOMOGRAPH_TYPOSQUAT"
                diagnostic_results["checks"]["homograph_tr39"] = {
                    "passed": passed,
                    "risk_score": rep.composite_risk_score
                }
                if not passed:
                    diagnostic_results["passed"] = False
            except Exception as e:
                diagnostic_results["checks"]["homograph_tr39"] = {"passed": False, "error": str(e)}
                diagnostic_results["passed"] = False

            # 2. DGA Neural Test
            try:
                dga_domain = "bcdfghjklmnpqrstvwxyz.org"
                rep = self.threat_engine.hunt_domain(dga_domain)
                passed = rep.is_threat and rep.threat_type == "DGA_MALWARE"
                diagnostic_results["checks"]["dga_neural_mlp"] = {
                    "passed": passed,
                    "risk_score": rep.composite_risk_score
                }
                if not passed:
                    diagnostic_results["passed"] = False
            except Exception as e:
                diagnostic_results["checks"]["dga_neural_mlp"] = {"passed": False, "error": str(e)}
                diagnostic_results["passed"] = False

            # 3. Life Safety Exemption Guarantee Test
            try:
                rep_911 = self.threat_engine.hunt_domain("911.gov")
                rep_apple = self.threat_engine.hunt_domain("push.apple.com")
                passed = (not rep_911.is_threat) and (not rep_apple.is_threat)
                diagnostic_results["checks"]["life_safety_exemptions"] = {
                    "passed": passed,
                    "911_risk": rep_911.composite_risk_score,
                    "apns_risk": rep_apple.composite_risk_score
                }
                if not passed:
                    diagnostic_results["passed"] = False
            except Exception as e:
                diagnostic_results["checks"]["life_safety_exemptions"] = {"passed": False, "error": str(e)}
                diagnostic_results["passed"] = False

            self._health_status = "HEALTHY" if diagnostic_results["passed"] else "DEGRADED"
            diagnostic_results["overall_health"] = self._health_status
            return diagnostic_results

    def get_sync_status(self) -> Dict[str, Any]:
        """Returns sync status telemetry."""
        with self._lock:
            return {
                "autonomous_mode": self._is_autonomous_mode,
                "overall_health": self._health_status,
                "last_successful_sync": int(self._last_successful_sync),
                "total_syncs_applied": len(self._sync_history),
                "recent_syncs": self._sync_history[-10:],
                "checkpoint_directory": self.checkpoint_dir,
            }
