"""
FocusDNS Router Gateway - Edge AI Threat Interceptor
Provides real-time on-router zero-day threat hunting, IDN homograph defense,
and DGA classification for all home LAN clients (Smart TVs, consoles, laptops, mobile).
Enforces Life Safety Exemptions and the Conditional Whitelisting Law at the gateway boundary.
"""

import collections
import logging
import threading
import time
from typing import Dict, List, Set, Optional, Tuple, Any

from server.ai.threat_hunting_engine import ThreatHuntingEngine, ThreatVerdict, get_global_threat_engine
from server.ai.zero_hour_phishing import LIFE_SAFETY_EXEMPTIONS

logger = logging.getLogger("FocusDNS.Router.AIInterceptor")


class EdgeDeviceThreatRecord:
    """Telemetry record for a threat caught from a LAN device."""
    __slots__ = (
        "timestamp", "client_ip", "client_mac", "device_name",
        "domain", "threat_type", "risk_score", "action", "reason"
    )

    def __init__(
        self,
        client_ip: str,
        client_mac: str,
        device_name: str,
        domain: str,
        threat_type: str,
        risk_score: float,
        action: str,
        reason: str,
        timestamp: Optional[float] = None
    ):
        self.timestamp = timestamp or time.time()
        self.client_ip = client_ip
        self.client_mac = client_mac
        self.device_name = device_name
        self.domain = domain
        self.threat_type = threat_type
        self.risk_score = round(risk_score, 2)
        self.action = action
        self.reason = reason

    def to_dict(self) -> Dict[str, Any]:
        return {
            "timestamp": int(self.timestamp),
            "client_ip": self.client_ip,
            "client_mac": self.client_mac,
            "device_name": self.device_name,
            "domain": self.domain,
            "threat_type": self.threat_type,
            "risk_score": self.risk_score,
            "action": self.action,
            "reason": self.reason,
        }


class RouterAiInterceptor:
    """
    Gateway-level threat hunting interceptor running on router hardware.
    Inspects DNS packets forwarded by router dnsmasq / unbound / systemd-resolved.
    """

    def __init__(
        self,
        engine: Optional[ThreatHuntingEngine] = None,
        max_log_entries: int = 1000,
        sinkhole_ipv4: str = "0.0.0.0",
        sinkhole_ipv6: str = "::"
    ):
        self.engine = engine or get_global_threat_engine()
        self.sinkhole_ipv4 = sinkhole_ipv4
        self.sinkhole_ipv6 = sinkhole_ipv6
        self._lock = threading.RLock()

        # Circular buffer for live threat telemetry
        self._threat_log: collections.deque = collections.deque(maxlen=max_log_entries)

        # Device mapping: MAC -> Device Name
        self._known_devices: Dict[str, str] = {
            "D8:9E:3F:44:55:66": "Sarah's iPad Mini",
            "AA:BB:CC:11:22:33": "Living Room LG Smart TV",
            "F0:18:98:77:88:99": "Work MacBook Pro",
            "00:1A:2B:3C:4D:5E": "PlayStation 5",
            "11:22:33:44:55:66": "Guest Pixel 8",
        }

        # Operational metrics
        self._total_queries_intercepted = 0
        self._total_threats_blocked = 0
        self._homographs_blocked = 0
        self._dga_blocked = 0
        self._phishing_blocked = 0
        self._life_safety_passed = 0
        self._total_latency_us = 0.0

    def register_device(self, mac_address: str, device_name: str):
        """Associates LAN MAC address with human-readable device name."""
        with self._lock:
            self._known_devices[mac_address.upper().strip()] = device_name.strip()

    def get_device_name(self, mac_address: str) -> str:
        """Resolves MAC address to device label."""
        with self._lock:
            return self._known_devices.get(mac_address.upper().strip(), f"Device-{mac_address}")

    def intercept_packet(
        self,
        domain: str,
        client_ip: str,
        client_mac: str = "00:00:00:00:00:00",
        qtype: str = "A"
    ) -> Tuple[bool, str, Dict[str, Any]]:
        """
        Intercepts and evaluates domain query on router gateway.
        Returns: (should_block, resolved_or_sinkhole_ip, telemetry_dict)
        """
        t0 = time.perf_counter()
        clean_domain = domain.lower().strip().rstrip(".")
        device_name = self.get_device_name(client_mac)

        # 1. Life Safety Exemption Absolute Fast-Path
        if self._is_life_safety_exempt(clean_domain):
            elapsed_us = (time.perf_counter() - t0) * 1_000_000
            with self._lock:
                self._total_queries_intercepted += 1
                self._life_safety_passed += 1
                self._total_latency_us += elapsed_us
            return False, "", {
                "action": "ALLOW",
                "reason": "Life Safety Exemption: Emergency/Critical Infrastructure",
                "risk_score": 0.0,
                "latency_us": round(elapsed_us, 2)
            }

        # 2. On-Device AI Threat Hunting Analysis
        verdict: ThreatVerdict = self.engine.hunt_domain(clean_domain)
        elapsed_us = (time.perf_counter() - t0) * 1_000_000

        with self._lock:
            self._total_queries_intercepted += 1
            self._total_latency_us += elapsed_us

        if verdict.is_threat:
            sinkhole = self.sinkhole_ipv6 if qtype == "AAAA" else self.sinkhole_ipv4
            record = EdgeDeviceThreatRecord(
                client_ip=client_ip,
                client_mac=client_mac,
                device_name=device_name,
                domain=clean_domain,
                threat_type=verdict.threat_type,
                risk_score=verdict.composite_risk_score,
                action=verdict.recommended_action,
                reason=verdict.primary_reason,
            )

            with self._lock:
                self._total_threats_blocked += 1
                if verdict.threat_type == "HOMOGRAPH_TYPOSQUAT":
                    self._homographs_blocked += 1
                elif verdict.threat_type == "DGA_MALWARE":
                    self._dga_blocked += 1
                elif "PHISHING" in verdict.threat_type:
                    self._phishing_blocked += 1
                self._threat_log.append(record)

            logger.warning(
                f"[ROUTER AI BLOCK] {device_name} ({client_ip}) attempted resolving threat "
                f"'{clean_domain}' ({verdict.threat_type}, score: {verdict.composite_risk_score:.1f})"
            )

            return True, sinkhole, {
                "action": "BLOCK",
                "reason": verdict.primary_reason,
                "threat_type": verdict.threat_type,
                "risk_score": verdict.composite_risk_score,
                "detected_brand": verdict.detected_brand,
                "dga_family": verdict.dga_family,
                "category": verdict.primary_category,
                "latency_us": round(elapsed_us, 2),
                "device_name": device_name,
            }

        # Benign Domain -> Allow
        return False, "", {
            "action": "ALLOW",
            "reason": "AI Classified Benign",
            "risk_score": verdict.composite_risk_score,
            "category": verdict.primary_category,
            "is_distracting": verdict.is_distracting,
            "latency_us": round(elapsed_us, 2),
            "device_name": device_name,
        }

    def _is_life_safety_exempt(self, domain: str) -> bool:
        """Life safety exemption check."""
        for exempt in LIFE_SAFETY_EXEMPTIONS:
            if domain == exempt or domain.endswith("." + exempt):
                return True
        return False

    def add_router_whitelist(self, domain: str, requester_device: str = "Admin-Console") -> bool:
        """
        Enforces Conditional Whitelisting Law on Router:
        Allowed with zero friction when router is idle.
        Strictly raises PermissionError (ERROR_ACCESS_DENIED) during active focus or timer > 0.
        """
        return self.engine.add_whitelist(domain, requester=requester_device)

    def remove_router_whitelist(self, domain: str, requester_device: str = "Admin-Console") -> bool:
        """Removes domain from router whitelist."""
        return self.engine.remove_whitelist(domain, requester=requester_device)

    def set_router_lock(self, locked: bool, duration_seconds: int = 0):
        """Sets router focus lock posture."""
        self.engine.set_focus_lock(locked=locked, remaining_seconds=duration_seconds)

    def get_latest_threat_logs(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Returns recent threats caught across all router LAN clients."""
        with self._lock:
            logs = list(self._threat_log)
            recent = logs[-limit:]
            recent.reverse()
            return [rec.to_dict() for rec in recent]

    def get_router_ai_metrics(self) -> Dict[str, Any]:
        """Returns router threat interception metrics."""
        with self._lock:
            avg_latency = (
                (self._total_latency_us / self._total_queries_intercepted)
                if self._total_queries_intercepted > 0
                else 0.0
            )
            return {
                "total_queries_intercepted": self._total_queries_intercepted,
                "total_threats_blocked": self._total_threats_blocked,
                "homographs_blocked": self._homographs_blocked,
                "dga_blocked": self._dga_blocked,
                "phishing_blocked": self._phishing_blocked,
                "life_safety_passed": self._life_safety_passed,
                "avg_interception_latency_us": round(avg_latency, 2),
                "is_router_locked": self.engine.is_locked(),
                "managed_lan_devices": len(self._known_devices),
                "logged_threat_events": len(self._threat_log),
            }
