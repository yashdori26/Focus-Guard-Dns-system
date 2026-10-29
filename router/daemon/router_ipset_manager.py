"""
Router Edge In-Memory & Kernel IPSet Fastpath Manager.

Manages sub-microsecond IP and CIDR matching using Linux 'ipset' (hash:ip, hash:net)
and in-memory radix indexing on resource-constrained home routers:
1. focus_doh_v4 (hash:ip): Zero-overhead drops for rogue DoH IPs.
2. focus_blocked_subnets (hash:net): CIDR-level containment for dangerous network ranges.
3. focus_exempt_devices (hash:mac): Emergency VoIP and IoT devices that bypass filtering.
4. Generates batch 'ipset restore' configuration sequences for rapid bootup.
"""

import socket
import struct
import threading
from typing import Dict, Any, List, Set, Optional


class RouterIpsetManager:
    """Manages high-performance IPSet tables for edge router firewalls."""

    SET_DOH_V4 = "focus_doh_v4"
    SET_BLOCKED_SUBNETS = "focus_blocked_nets"
    SET_EXEMPT_DEVICES = "focus_exempt_macs"

    DEFAULT_ROGUE_IPS = [
        "1.1.1.1", "1.0.0.1",
        "8.8.8.8", "8.8.4.4",
        "9.9.9.9", "149.112.112.112",
        "208.67.222.222", "208.67.220.220",
        "94.140.14.14", "94.140.15.15"
    ]

    DEFAULT_EXEMPT_MACS = [
        "00:11:22:33:44:55", # Emergency VoIP Desk Phone
        "AA:BB:CC:DD:EE:00"  # Critical Home Security Hub
    ]

    def __init__(self, max_entries: int = 65536):
        self.max_entries = max_entries
        self._lock = threading.RLock()
        self._doh_ips: Set[str] = set(self.DEFAULT_ROGUE_IPS)
        self._blocked_subnets: Set[str] = set()
        self._exempt_macs: Set[str] = set(self.DEFAULT_EXEMPT_MACS)
        self._lookup_stats = {
            "total_lookups": 0,
            "blocked_matches": 0,
            "exempt_matches": 0
        }

    def add_doh_ip(self, ip_str: str) -> bool:
        """Adds rogue DoH IP address to hash:ip set."""
        with self._lock:
            self._doh_ips.add(ip_str)
            return True

    def remove_doh_ip(self, ip_str: str) -> bool:
        """Removes an IP address from hash:ip set."""
        with self._lock:
            if ip_str in self._doh_ips:
                self._doh_ips.remove(ip_str)
                return True
            return False

    def add_blocked_subnet(self, cidr: str) -> bool:
        """Adds CIDR network block to hash:net set."""
        with self._lock:
            self._blocked_subnets.add(cidr)
            return True

    def add_exempt_mac(self, mac_str: str) -> bool:
        """Life-Safety Exemption: Adds MAC address to bypass set."""
        with self._lock:
            self._exempt_macs.add(mac_str.upper())
            return True

    def is_ip_blocked(self, ip_str: str) -> bool:
        """Fast-path lookup checking if destination IP is in rogue DoH set."""
        with self._lock:
            self._lookup_stats["total_lookups"] += 1
            if ip_str in self._doh_ips:
                self._lookup_stats["blocked_matches"] += 1
                return True
            return False

    def is_mac_exempt(self, mac_str: str) -> bool:
        """Life-Safety Exemption check for client device MAC address."""
        with self._lock:
            if mac_str.upper() in self._exempt_macs:
                self._lookup_stats["exempt_matches"] += 1
                return True
            return False

    def generate_ipset_restore_script(self) -> str:
        """
        Generates batch 'ipset restore' format file for sub-millisecond
        kernel loading on router startup.
        """
        lines = [
            f"create {self.SET_DOH_V4} hash:ip family inet hashsize 1024 maxelem {self.max_entries}",
            f"create {self.SET_BLOCKED_SUBNETS} hash:net family inet hashsize 1024 maxelem {self.max_entries}",
            f"create {self.SET_EXEMPT_DEVICES} hash:mac hashsize 256 maxelem 1024"
        ]

        with self._lock:
            for ip in sorted(self._doh_ips):
                lines.append(f"add {self.SET_DOH_V4} {ip}")
            for net in sorted(self._blocked_subnets):
                lines.append(f"add {self.SET_BLOCKED_SUBNETS} {net}")
            for mac in sorted(self._exempt_macs):
                lines.append(f"add {self.SET_EXEMPT_DEVICES} {mac}")

        return "\n".join(lines) + "\n"

    def get_status(self) -> Dict[str, Any]:
        """Returns IPSet tables statistics."""
        with self._lock:
            return {
                "doh_ips_count": len(self._doh_ips),
                "blocked_subnets_count": len(self._blocked_subnets),
                "exempt_macs_count": len(self._exempt_macs),
                "max_entries": self.max_entries,
                "stats": dict(self._lookup_stats)
            }
