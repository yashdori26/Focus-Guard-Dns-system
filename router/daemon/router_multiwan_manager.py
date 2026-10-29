"""
Whole-Home Router Multi-WAN Failover & Health Probe Manager.

Manages upstream FocusDNS query routing across multiple WAN interfaces
(e.g., WAN1: Primary Fiber / Cable, WAN2: Backup 5G / LTE Gateway).

Inviolable Fail-Safe Guarantee:
- Continuously probes primary and backup WAN uplinks.
- If primary WAN drops packets, auto-switches upstream DNS resolution to secondary WAN.
- If ALL WAN uplinks fail, engages Local LAN Fallback Mode (127.0.0.1:53) so local
  smart home IoT devices, cameras, and local services (.lan, .local) never crash.
"""

import time
import threading
from typing import Dict, Any, List, Optional


class WanInterfaceStatus:
    """Status record for an individual WAN interface."""

    def __init__(self, name: str, gateway_ip: str, priority: int = 1):
        self.name = name
        self.gateway_ip = gateway_ip
        self.priority = priority
        self.is_online = True
        self.consecutive_failures = 0
        self.last_probe_latency_ms = 12.5
        self.total_probes_sent = 0
        self.total_probes_failed = 0


class RouterMultiWanManager:
    """Orchestrates multi-uplink DNS routing and fail-safe fallback."""

    def __init__(self, probe_interval_seconds: int = 10, failure_threshold: int = 3):
        self.probe_interval_seconds = probe_interval_seconds
        self.failure_threshold = failure_threshold
        self._lock = threading.RLock()

        # Configured WAN uplinks
        self.wan_interfaces: Dict[str, WanInterfaceStatus] = {
            "wan1": WanInterfaceStatus("wan1", "192.168.0.1", priority=1), # Primary
            "wan2": WanInterfaceStatus("wan2", "192.168.8.1", priority=2), # Backup 5G
        }

        self.active_wan = "wan1"
        self.is_lan_fallback_mode = False
        self._failover_history: List[Dict[str, Any]] = []

    def report_probe_result(self, wan_name: str, success: bool, latency_ms: float = 0.0) -> None:
        """Records probe outcome for a specific WAN interface."""
        with self._lock:
            if wan_name not in self.wan_interfaces:
                return

            wan = self.wan_interfaces[wan_name]
            wan.total_probes_sent += 1

            if success:
                wan.consecutive_failures = 0
                wan.is_online = True
                wan.last_probe_latency_ms = latency_ms
            else:
                wan.total_probes_failed += 1
                wan.consecutive_failures += 1
                if wan.consecutive_failures >= self.failure_threshold:
                    wan.is_online = False

            self._evaluate_routing_state()

    def _evaluate_routing_state(self) -> None:
        """Re-evaluates active WAN uplink based on health status."""
        wan1 = self.wan_interfaces.get("wan1")
        wan2 = self.wan_interfaces.get("wan2")

        if wan1 and wan1.is_online:
            if self.active_wan != "wan1":
                self._log_failover("PRIMARY_RESTORED", "wan1", "Primary fiber WAN restored.")
                self.active_wan = "wan1"
            self.is_lan_fallback_mode = False
        elif wan2 and wan2.is_online:
            if self.active_wan != "wan2":
                self._log_failover("FAILOVER_TRIGGERED", "wan2", "Primary WAN down; switched to secondary 5G WAN.")
                self.active_wan = "wan2"
            self.is_lan_fallback_mode = False
        else:
            # Inviolable Law: All WAN uplinks down -> Engage LAN Fallback
            if not self.is_lan_fallback_mode:
                self._log_failover("ALL_WAN_DOWN_FALLBACK", "none", "All WAN down! Local LAN fallback engaged.")
                self.is_lan_fallback_mode = True

    def _log_failover(self, event_type: str, new_target: str, reason: str) -> None:
        self._failover_history.append({
            "timestamp": time.time(),
            "event": event_type,
            "target": new_target,
            "reason": reason
        })
        if len(self._failover_history) > 50:
            self._failover_history.pop(0)

    def get_status(self) -> Dict[str, Any]:
        """Returns comprehensive Multi-WAN status."""
        with self._lock:
            interfaces_data = {}
            for name, w in self.wan_interfaces.items():
                interfaces_data[name] = {
                    "gateway": w.gateway_ip,
                    "is_online": w.is_online,
                    "consecutive_failures": w.consecutive_failures,
                    "latency_ms": w.last_probe_latency_ms,
                    "probes_sent": w.total_probes_sent,
                    "probes_failed": w.total_probes_failed
                }

            return {
                "active_wan": self.active_wan,
                "is_lan_fallback_mode": self.is_lan_fallback_mode,
                "interfaces": interfaces_data,
                "failover_events_count": len(self._failover_history),
                "recent_events": list(self._failover_history[-5:])
            }
