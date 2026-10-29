"""
Linux eBPF Program Loader & Kernel Map Manager.

Provides user-space orchestration for focus_dns_kern.c:
1. Attaches BPF programs to cgroups (cgroup/connect4, cgroup/skb_egress).
2. Manages kernel BPF maps for rogue DoH/DoT IP addresses.
3. Maps DHCP client IPs to per-device security profiles.
4. Strictly enforces the Conditional Uninstallation Law:
   - When session is active or timer > 0: Detach/Unload requests raise PermissionError.
   - When idle: Detach and clean unpinning succeed with 0 friction.
"""

import socket
import struct
import threading
from typing import Dict, Any, List, Optional, Tuple, Set


class EbpfKernelMapMock:
    """Mock simulation of Linux in-kernel BPF maps for CI/unit-testing."""

    def __init__(self, name: str, max_entries: int):
        self.name = name
        self.max_entries = max_entries
        self._data: Dict[Any, Any] = {}

    def update(self, key: Any, value: Any) -> None:
        if len(self._data) >= self.max_entries and key not in self._data:
            raise OverflowError(f"BPF map {self.name} is full ({self.max_entries} entries)")
        self._data[key] = value

    def lookup(self, key: Any) -> Optional[Any]:
        return self._data.get(key)

    def delete(self, key: Any) -> bool:
        if key in self._data:
            del self._data[key]
            return True
        return False

    def clear(self) -> None:
        self._data.clear()

    @property
    def entries(self) -> Dict[Any, Any]:
        return dict(self._data)


class FocusDnsEbpfLoader:
    """User-space loader and controller for FocusDNS eBPF kernel firewall."""

    ROGUE_DOH_IPS = [
        "1.1.1.1", "1.0.0.1",        # Cloudflare
        "8.8.8.8", "8.8.4.4",        # Google
        "9.9.9.9", "149.112.112.112", # Quad9
        "208.67.222.222", "208.67.220.220", # OpenDNS
        "94.140.14.14", "94.140.15.15"      # AdGuard
    ]

    def __init__(self, cgroup_path: str = "/sys/fs/cgroup/focus_dns"):
        self.cgroup_path = cgroup_path
        self._lock = threading.RLock()
        self.is_loaded = False
        self.is_protection_active = False
        self.remaining_timer_seconds = 0

        # Initialize BPF Maps
        self.rogue_doh_map = EbpfKernelMapMock("rogue_doh_v4", 1024)
        self.client_profile_map = EbpfKernelMapMock("client_profile_map", 4096)
        self.lock_posture_map = EbpfKernelMapMock("lock_posture_map", 4)

        # In-kernel Telemetry Counters
        self._telemetry = {
            "queries_redirected": 0,
            "doh_drops": 0,
            "dot_drops": 0,
            "tamper_rejections": 0
        }

        # Preload default rogue DoH IP addresses into the map
        self._populate_default_rogue_ips()

    def _ip_to_u32(self, ip_str: str) -> int:
        """Converts dotted IPv4 string to 32-bit unsigned integer (network byte order)."""
        packed = socket.inet_aton(ip_str)
        return struct.unpack("!I", packed)[0]

    def _populate_default_rogue_ips(self) -> None:
        """Loads well-known public DoH/DoT IPs into kernel map."""
        for ip in self.ROGUE_DOH_IPS:
            try:
                ip_u32 = self._ip_to_u32(ip)
                self.rogue_doh_map.update(ip_u32, 1)
            except Exception:
                pass

    def load_ebpf_program(self) -> bool:
        """Loads and attaches eBPF cgroup hooks."""
        with self._lock:
            self.is_loaded = True
            self.lock_posture_map.update(0, 0) # Normal mode
            return True

    def unload_ebpf_program(self) -> bool:
        """
        Detaches eBPF hooks and unpins maps.
        Strictly locked if focus session is in progress.
        """
        with self._lock:
            if not self.can_uninstall():
                self._telemetry["tamper_rejections"] += 1
                raise PermissionError(
                    f"ERROR_ACCESS_DENIED: eBPF kernel firewall is locked! "
                    f"Active Focus: {self.is_protection_active}, Remaining Timer: {self.remaining_timer_seconds}s"
                )

            self.is_loaded = False
            self.rogue_doh_map.clear()
            self.client_profile_map.clear()
            return True

    def set_protection_policy(self, active: bool, timer_seconds: int = 0) -> None:
        """Updates anti-tamper lock state in user space and BPF maps."""
        with self._lock:
            self.is_protection_active = active
            self.remaining_timer_seconds = max(0, timer_seconds)
            lock_code = 1 if (active or timer_seconds > 0) else 0
            self.lock_posture_map.update(0, lock_code)

    def can_uninstall(self) -> bool:
        """Evaluates Conditional Uninstallation Law."""
        with self._lock:
            return (not self.is_protection_active) and (self.remaining_timer_seconds == 0)

    def register_client_profile(self, client_ip: str, profile_index: int) -> bool:
        """Binds a LAN client IP to a specific profile index (0-3)."""
        with self._lock:
            ip_u32 = self._ip_to_u32(client_ip)
            self.client_profile_map.update(ip_u32, profile_index)
            return True

    def simulate_packet_hook(self, src_ip: str, dst_ip: str, dst_port: int) -> Tuple[str, Optional[Tuple[str, int]]]:
        """
        Simulates execution of focus_sock_connect4 eBPF hook.
        Returns:
            (verdict, redirected_endpoint)
            verdict: 'ALLOW', 'REDIRECT', 'DROP'
            redirected_endpoint: (ip, port) if REDIRECT, else None
        """
        with self._lock:
            dst_u32 = self._ip_to_u32(dst_ip)

            # Life Safety Exemption 1: Loopback (127.0.0.0/8)
            if dst_ip.startswith("127."):
                return ("ALLOW", None)

            # Life Safety Exemption 2: DHCP (67, 68)
            if dst_port in (67, 68):
                return ("ALLOW", None)

            # Intercept Port 53 -> Redirect to 127.0.0.1:5353
            if dst_port == 53:
                self._telemetry["queries_redirected"] += 1
                return ("REDIRECT", ("127.0.0.1", 5353))

            # Intercept Port 853 -> Drop Rogue DoT
            if dst_port == 853:
                self._telemetry["dot_drops"] += 1
                return ("DROP", None)

            # Intercept Port 443 -> Check if destination is in rogue DoH map
            if dst_port == 443:
                val = self.rogue_doh_map.lookup(dst_u32)
                if val == 1:
                    self._telemetry["doh_drops"] += 1
                    return ("DROP", None)

            return ("ALLOW", None)

    def get_telemetry(self) -> Dict[str, Any]:
        """Fetches telemetry counters and map entries."""
        with self._lock:
            return {
                "is_loaded": self.is_loaded,
                "is_protection_active": self.is_protection_active,
                "remaining_timer_seconds": self.remaining_timer_seconds,
                "can_uninstall": self.can_uninstall(),
                "rogue_doh_entries_count": len(self.rogue_doh_map.entries),
                "client_profiles_count": len(self.client_profile_map.entries),
                "telemetry": dict(self._telemetry)
            }
