"""
Master Whole-Home Router Orchestrator Daemon.

Unifies all modular edge router components into a single resilient system:
1. RouterStubDaemon: Local DNS caching stub and EDNS0 ECS profile injector.
2. MacProfileRouter: DHCP lease parsing and per-MAC policy mapping.
3. RouterDoqEngine: RFC 9250 DNS-over-QUIC encrypted client (0-RTT).
4. RouterDnssecValidator: ICANN root KSK cryptographic verification.
5. RouterMultiWanManager: Primary vs backup WAN failover & fail-safe fallback.
6. RouterSqmController: Linux CAKE traffic shaper with VoIP emergency priority.
7. RouterIpsetManager: Fast-path hash:ip and hash:mac lookup tables.

Enforces:
- Conditional Uninstallation Law: Teardown rejected if focus mode or timer active.
- Life-Safety Exemption: Emergency VoIP, DHCP, and loopback unconditionally bypass.
- Fail-Safe Guarantee: Reverts to LAN resolver (127.0.0.1:53) if WAN drops.
"""

import time
import threading
from typing import Dict, Any, List, Optional

from router.daemon.router_stub_daemon import RouterStubDaemon
from router.openwrt.mac_profile_router import MacProfileRouter
from router.daemon.router_doq_engine import RouterDoqEngine
from router.daemon.router_dnssec_validator import RouterDnssecValidator
from router.daemon.router_multiwan_manager import RouterMultiWanManager
from router.daemon.router_sqm_controller import RouterSqmController
from router.daemon.router_ipset_manager import RouterIpsetManager
from router.daemon.router_telemetry_reporter import RouterTelemetryReporter


class RouterMasterOrchestrator:
    """Master edge router coordinator managing all network subsystems."""

    def __init__(
        self,
        router_id: str = "rtr_home_master_gw",
        platform_type: str = "Unified-EdgeRouter",
        default_profile: str = "profile_home_primary"
    ):
        self.router_id = router_id
        self.platform_type = platform_type
        self.default_profile = default_profile
        self._lock = threading.RLock()

        # Initialize Subsystems
        self.mac_router = MacProfileRouter(default_profile=default_profile)
        self.stub_daemon = RouterStubDaemon(mac_router=self.mac_router)
        self.doq_engine = RouterDoqEngine()
        self.dnssec_validator = RouterDnssecValidator()
        self.multiwan = RouterMultiWanManager()
        self.sqm = RouterSqmController()
        self.ipset_mgr = RouterIpsetManager()
        self.telemetry = RouterTelemetryReporter(
            stub_daemon=self.stub_daemon,
            mac_router=self.mac_router
        )

        self.is_running = False
        self.is_locked = False
        self.remaining_timer_seconds = 0
        self.start_timestamp = time.time()

    def start(self) -> bool:
        """Starts all router edge daemons and monitoring loops."""
        with self._lock:
            if self.is_running:
                return True
            self.stub_daemon.start()
            self.is_running = True
            self.start_timestamp = time.time()
            return True

    def stop(self) -> bool:
        """Stops router subsystems (strictly subject to Conditional Uninstallation)."""
        with self._lock:
            if not self.can_uninstall():
                raise PermissionError(
                    f"ERROR_ACCESS_DENIED: RouterMasterOrchestrator cannot be stopped while focus is locked "
                    f"({self.remaining_timer_seconds}s remaining)."
                )
            self.stub_daemon.stop()
            self.is_running = False
            return True

    def set_focus_lock(self, locked: bool, remaining_seconds: int = 0) -> None:
        """Sets conditional focus mode across all router subsystems."""
        with self._lock:
            self.is_locked = locked
            self.remaining_timer_seconds = max(0, remaining_seconds)
            self.stub_daemon.set_lock(locked, remaining_seconds)
            self.sqm.set_focus_mode(locked or remaining_seconds > 0)

    def can_uninstall(self) -> bool:
        """Evaluates Conditional Uninstallation Law."""
        with self._lock:
            return (not self.is_locked) and (self.remaining_timer_seconds == 0)

    def process_incoming_query(self, client_ip: str, client_mac: str, raw_dns_query: bytes) -> Optional[bytes]:
        """
        Coordinates full DNS request lifecycle through edge stack:
        1. Checks MAC exemption (Life Safety)
        2. Resolves client profile
        3. Consults in-memory cache
        4. Upstream resolution via DoQ (or UDP fallback)
        5. Validates DNSSEC
        6. Updates LRU cache and returns response
        """
        # Life Safety Exemption Check
        if self.ipset_mgr.is_mac_exempt(client_mac):
            # Bypass directly to fallback LAN resolver
            return self.stub_daemon._forward_upstream(raw_dns_query, "profile_bypass_exempt")

        assigned_profile = self.mac_router.resolve_profile_for_mac(client_mac)

        # Cache check via stub daemon
        cached = self.stub_daemon._lookup_cache(raw_dns_query, assigned_profile)
        if cached:
            return cached

        # Upstream resolution: Try DoQ first if active
        response = self.doq_engine.resolve_doq(raw_dns_query)
        if not response:
            # Fallback to standard UDP stub forwarding
            response = self.stub_daemon._forward_upstream(raw_dns_query, assigned_profile)

        if response:
            # Cryptographic DNSSEC verification
            status, verified = self.dnssec_validator.validate_dns_packet(response, domain=".")
            if status == "BOGUS":
                # Forged response detected; do not cache, drop query
                return None

            self.stub_daemon._store_cache(raw_dns_query, assigned_profile, verified)
            return verified

        return None

    def get_unified_status(self) -> Dict[str, Any]:
        """Compiles comprehensive health report across all router subsystems."""
        with self._lock:
            return {
                "router_id": self.router_id,
                "platform": self.platform_type,
                "is_running": self.is_running,
                "uptime_seconds": int(time.time() - self.start_timestamp),
                "is_locked": self.is_locked,
                "remaining_timer_seconds": self.remaining_timer_seconds,
                "can_uninstall": self.can_uninstall(),
                "active_profile": self.default_profile,
                "subsystems": {
                    "stub_daemon": self.stub_daemon.get_metrics(),
                    "doq_engine": self.doq_engine.get_telemetry(),
                    "dnssec_validator": self.dnssec_validator.get_stats(),
                    "multiwan": self.multiwan.get_status(),
                    "sqm": self.sqm.get_status(),
                    "ipset": self.ipset_mgr.get_status(),
                    "connected_devices": len(self.mac_router.get_all_devices())
                }
            }
