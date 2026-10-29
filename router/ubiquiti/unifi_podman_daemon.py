"""
FocusGuard Ubiquiti UniFi OS & EdgeOS Podman Daemon Supervisor.

Orchestrates the containerized FocusGuard DNS proxy on Ubiquiti gateways:
  - UniFi Dream Machine (UDM, UDM-Pro, UDM-SE)
  - UniFi Next-Gen Gateway (UXG-Pro, UXG-Lite)
  - UniFi Cloud Gateway (UCG-Ultra, UCG-Max)
  - EdgeRouter (EdgeOS / VyOS)

Key Principles:
  1. Fail-Safe Guarantee: Automated watchdog monitors container health; if the container
     fails 3 consecutive health checks, iptables redirects are flushed and upstream fallback
     DNS is activated so smart home devices (IoT, Apple TVs, thermostats) never freeze.
  2. Conditional Uninstallation Law:
     - When Idle (timer == 0 and protection off): Clean container teardown and on_boot.d removal.
     - When Active Focus (timer > 0 or protection on): Teardown raises PermissionError (ERROR_ACCESS_DENIED).
  3. Life Safety Exemption: Emergency calling, DHCP (ports 67/68), and UniFi OS web admin
     (ports 80, 443, 8443) are permanently hardcoded exempt from interception.
"""

import os
import sys
import time
import socket
import logging
import threading
import subprocess
from typing import Dict, List, Optional, Any

logger = logging.getLogger("focus_dns.unifi_podman")


class UnifiPodmanDaemon:
    """
    Supervisor managing the FocusGuard DNS edge container via Podman on UniFi OS.
    Runs on gateway hardware or executes in mock mode during automated testing.
    """

    ON_BOOT_DIR = "/data/on_boot.d"
    SCRIPT_NAME = "10-focusguard-dns.sh"
    CONTAINER_NAME = "focusguard-edge-dns"
    IMAGE_NAME = "focusguard/router-edge:latest"

    def __init__(
        self,
        container_port: int = 5353,
        watchdog_interval_seconds: float = 10.0,
        max_consecutive_failures: int = 3,
        mock_mode: bool = False
    ):
        self.container_port = container_port
        self.watchdog_interval_seconds = watchdog_interval_seconds
        self.max_consecutive_failures = max_consecutive_failures
        self.mock_mode = mock_mode

        self._lock = threading.RLock()
        self._active_focus_mode = False
        self._countdown_timer_seconds = 0
        self._is_running = False
        self._consecutive_failures = 0
        self._is_fallback_active = False
        self._watchdog_thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()

        # Telemetry metrics
        self._total_probes = 0
        self._successful_probes = 0
        self._restart_count = 0
        self._monitored_devices: Dict[str, str] = {}  # MAC -> Profile ID

    def set_focus_posture(self, is_active: bool, timer_seconds: int = 0):
        """Updates focus guard lock state."""
        with self._lock:
            self._active_focus_mode = is_active
            self._countdown_timer_seconds = max(0, timer_seconds)

    def can_uninstall(self) -> bool:
        """Enforces Conditional Uninstallation Law."""
        with self._lock:
            return not self._active_focus_mode and (self._countdown_timer_seconds <= 0)

    def generate_on_boot_script(self, profile_id: str = "profile_home_primary") -> str:
        """
        Compiles the shell script placed in /data/on_boot.d/10-focusguard-dns.sh
        ensuring FocusGuard survives UniFi OS firmware upgrades and reboots.
        """
        return f"""#!/bin/sh
# FocusGuard UniFi OS On-Boot Supervisor
# Auto-generated on {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}

set -e

CONTAINER_NAME="{self.CONTAINER_NAME}"
IMAGE="{self.IMAGE_NAME}"
PROXY_PORT={self.container_port}
PROFILE_ID="{profile_id}"

logger -t FocusGuard "Initializing FocusGuard Edge DNS Container on UniFi OS..."

# Ensure podman network exists
if ! podman network exists focusguard-net 2>/dev/null; then
    podman network create --subnet 10.99.0.0/24 focusguard-net
fi

# Stop existing container if present
podman stop "$CONTAINER_NAME" 2>/dev/null || true
podman rm "$CONTAINER_NAME" 2>/dev/null || true

# Launch FocusGuard Edge Daemon
podman run -d \\
    --name "$CONTAINER_NAME" \\
    --restart=always \\
    --net=host \\
    --cap-add=NET_ADMIN \\
    --cap-add=NET_RAW \\
    -e PROFILE_ID="$PROFILE_ID" \\
    -e PROXY_PORT="$PROXY_PORT" \\
    -v /run/focusguard:/run/focusguard:rw \\
    "$IMAGE"

# Configure iptables PREROUTING redirect for LAN traffic (excluding gateway itself)
iptables -t nat -N FOCUSGUARD_DNS 2>/dev/null || iptables -t nat -F FOCUSGUARD_DNS
iptables -t nat -C PREROUTING -p udp --dport 53 -j FOCUSGUARD_DNS 2>/dev/null || \\
    iptables -t nat -A PREROUTING -p udp --dport 53 -j FOCUSGUARD_DNS
iptables -t nat -C PREROUTING -p tcp --dport 53 -j FOCUSGUARD_DNS 2>/dev/null || \\
    iptables -t nat -A PREROUTING -p tcp --dport 53 -j FOCUSGUARD_DNS

# Redirect UDP/TCP 53 to container port $PROXY_PORT
iptables -t nat -A FOCUSGUARD_DNS -p udp --dport 53 -j REDIRECT --to-ports $PROXY_PORT
iptables -t nat -A FOCUSGUARD_DNS -p tcp --dport 53 -j REDIRECT --to-ports $PROXY_PORT

# Block direct bypass via DoT (port 853)
iptables -N FOCUSGUARD_BLOCK_BYPASS 2>/dev/null || iptables -F FOCUSGUARD_BLOCK_BYPASS
iptables -C FORWARD -p tcp --dport 853 -j FOCUSGUARD_BLOCK_BYPASS 2>/dev/null || \\
    iptables -A FORWARD -p tcp --dport 853 -j FOCUSGUARD_BLOCK_BYPASS
iptables -A FOCUSGUARD_BLOCK_BYPASS -p tcp --dport 853 -j REJECT --reject-with tcp-reset

logger -t FocusGuard "FocusGuard Edge DNS active. Protected profile: $PROFILE_ID"
"""

    def start(self, profile_id: str = "profile_home_primary") -> bool:
        """Starts the Podman container daemon and watchdog monitor."""
        with self._lock:
            if self._is_running:
                logger.warning("UniFi Podman daemon is already running.")
                return True

            logger.info("Starting UniFi Podman container supervisor (profile=%s)...", profile_id)
            if not self.mock_mode:
                # Real deployment: write on_boot.d script and invoke podman
                script_path = os.path.join(self.ON_BOOT_DIR, self.SCRIPT_NAME)
                try:
                    if os.path.isdir(self.ON_BOOT_DIR):
                        with open(script_path, "w") as f:
                            f.write(self.generate_on_boot_script(profile_id))
                        os.chmod(script_path, 0o755)
                        subprocess.run([script_path], check=True)
                except Exception as e:
                    logger.error("Failed to execute on_boot.d script: %s", e)
                    return False

            self._is_running = True
            self._is_fallback_active = False
            self._stop_event.clear()
            self._watchdog_thread = threading.Thread(target=self._watchdog_loop, daemon=True)
            self._watchdog_thread.start()
            return True

    def stop(self) -> bool:
        """Stops the daemon and watchdog."""
        with self._lock:
            if not self._is_running:
                return True

            self._stop_event.set()
            if self._watchdog_thread and self._watchdog_thread.is_alive():
                self._watchdog_thread.join(timeout=2.0)
            self._watchdog_thread = None
            self._is_running = False

            if not self.mock_mode:
                try:
                    subprocess.run(["podman", "stop", self.CONTAINER_NAME], check=False)
                except Exception:
                    pass
            logger.info("UniFi Podman daemon stopped.")
            return True

    def uninstall(self) -> bool:
        """
        Conditional Uninstallation Law:
        Clean removal permitted ONLY when Idle (not active & timer == 0).
        Raises PermissionError if active focus is engaged.
        """
        if not self.can_uninstall():
            err = (
                f"ERROR_ACCESS_DENIED (5): Cannot uninstall FocusGuard from UniFi gateway! "
                f"Active focus is locked with {self._countdown_timer_seconds}s remaining."
            )
            logger.critical(err)
            raise PermissionError(err)

        logger.info("Conditional Uninstallation check passed (Idle). Removing UniFi Podman container.")
        self.stop()

        if not self.mock_mode:
            script_path = os.path.join(self.ON_BOOT_DIR, self.SCRIPT_NAME)
            if os.path.exists(script_path):
                try:
                    os.remove(script_path)
                except Exception as e:
                    logger.warning("Could not delete on_boot script: %s", e)

            # Flush iptables rules
            try:
                subprocess.run(["iptables", "-t", "nat", "-D", "PREROUTING", "-p", "udp", "--dport", "53", "-j", "FOCUSGUARD_DNS"], check=False)
                subprocess.run(["iptables", "-t", "nat", "-D", "PREROUTING", "-p", "tcp", "--dport", "53", "-j", "FOCUSGUARD_DNS"], check=False)
                subprocess.run(["iptables", "-t", "nat", "-F", "FOCUSGUARD_DNS"], check=False)
                subprocess.run(["iptables", "-t", "nat", "-X", "FOCUSGUARD_DNS"], check=False)
            except Exception:
                pass

            try:
                subprocess.run(["podman", "rm", "-f", self.CONTAINER_NAME], check=False)
            except Exception:
                pass

        return True

    def _probe_container_health(self) -> bool:
        """Probes the local container DNS port to ensure resolution is working."""
        if self.mock_mode:
            return True

        sock = None
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(1.5)
            # Lightweight DNS query packet for 'gateway.healthcheck.focusguard' (A query)
            query = (
                b"\xaa\xbb"  # ID
                b"\x01\x00"  # Standard query
                b"\x00\x01\x00\x00\x00\x00\x00\x00"  # QDCOUNT=1
                b"\x07gateway\x0bhealthcheck\nfocusguard\x00"  # QNAME
                b"\x00\x01\x00\x01"  # QTYPE=A, QCLASS=IN
            )
            sock.sendto(query, ("127.0.0.1", self.container_port))
            data, _ = sock.recvfrom(512)
            return len(data) >= 12
        except Exception:
            return False
        finally:
            if sock:
                try:
                    sock.close()
                except Exception:
                    pass

    def _watchdog_loop(self):
        """Periodic supervisor loop checking health and enforcing fail-safe guarantee."""
        logger.info("UniFi container healthcheck watchdog started (interval=%.1fs)", self.watchdog_interval_seconds)
        while not self._stop_event.is_set():
            if self._stop_event.wait(timeout=self.watchdog_interval_seconds):
                break

            with self._lock:
                self._total_probes += 1
                healthy = self._probe_container_health()
                if healthy:
                    self._successful_probes += 1
                    self._consecutive_failures = 0
                    if self._is_fallback_active:
                        logger.info("Container recovered. Restoring FocusGuard DNS filtering.")
                        self._restore_filtering()
                else:
                    self._consecutive_failures += 1
                    logger.warning(
                        "Container probe failed (%d/%d consecutive failures)",
                        self._consecutive_failures,
                        self.max_consecutive_failures
                    )
                    if self._consecutive_failures >= self.max_consecutive_failures and not self._is_fallback_active:
                        logger.critical("Container unhealthy! Engaging router fail-safe fallback to prevent LAN freeze.")
                        self._engage_fail_safe_fallback()

    def _engage_fail_safe_fallback(self):
        """Failsafe guarantee: switches router to upstream DNS fallback so IoT devices never freeze."""
        self._is_fallback_active = True
        self._restart_count += 1
        if not self.mock_mode:
            # Temporarily bypass PREROUTING redirect
            try:
                subprocess.run(["iptables", "-t", "nat", "-F", "FOCUSGUARD_DNS"], check=False)
            except Exception:
                pass
            # Trigger container restart
            try:
                subprocess.run(["podman", "restart", self.CONTAINER_NAME], check=False)
            except Exception:
                pass

    def _restore_filtering(self):
        """Restores normal filtering after container recovery."""
        self._is_fallback_active = False
        if not self.mock_mode:
            try:
                subprocess.run(["iptables", "-t", "nat", "-A", "FOCUSGUARD_DNS", "-p", "udp", "--dport", "53", "-j", "REDIRECT", "--to-ports", str(self.container_port)], check=False)
                subprocess.run(["iptables", "-t", "nat", "-A", "FOCUSGUARD_DNS", "-p", "tcp", "--dport", "53", "-j", "REDIRECT", "--to-ports", str(self.container_port)], check=False)
            except Exception:
                pass

    def assign_device_profile(self, mac_address: str, profile_id: str):
        """Dynamically maps client device MAC address to a FocusGuard profile."""
        clean_mac = mac_address.lower().strip()
        with self._lock:
            self._monitored_devices[clean_mac] = profile_id
            logger.info("UniFi Gateway: assigned MAC %s to profile %s", clean_mac, profile_id)

    def get_status(self) -> Dict[str, Any]:
        """Returns comprehensive status dictionary for REST APIs and audits."""
        with self._lock:
            return {
                "container_name": self.CONTAINER_NAME,
                "is_running": self._is_running,
                "is_fallback_mode": self._is_fallback_active,
                "active_focus_mode": self._active_focus_mode,
                "remaining_timer_seconds": self._countdown_timer_seconds,
                "can_uninstall": self.can_uninstall(),
                "total_probes": self._total_probes,
                "successful_probes": self._successful_probes,
                "consecutive_failures": self._consecutive_failures,
                "restart_count": self._restart_count,
                "monitored_devices_count": len(self._monitored_devices),
                "container_port": self.container_port,
                "mock_mode": self.mock_mode
            }
