"""
FreeBSD / pfSense / OPNSense Packet Filter (PF) Synchronization Daemon.

Coordinates live pf tables (<focus_doh_bypass>, <focus_client_devices>)
and monitors /var/log/filter.log to track real-time bypass attempts.

Strictly enforces the Conditional Uninstallation Law:
- In Focus Mode: pfctl table flush or anchor deactivation commands raise PermissionError.
- In Idle Mode: Clean anchor detachment and table flushing are permitted.
"""

import re
import time
import threading
from typing import Dict, Any, List, Set, Optional, Tuple


class PfSyncDaemon:
    """Manages live pfctl tables and anchor lifecycle on pfSense & OPNSense."""

    DOH_TABLE_NAME = "focus_doh_bypass"
    DOT_PORT = 853

    DEFAULT_ROGUE_IPS = {
        "1.1.1.1", "1.0.0.1",
        "8.8.8.8", "8.8.4.4",
        "9.9.9.9", "149.112.112.112",
        "208.67.222.222", "208.67.220.220"
    }

    def __init__(self, anchor_name: str = "focus_dns"):
        self.anchor_name = anchor_name
        self._lock = threading.RLock()
        self.is_active = False
        self.is_locked = False
        self.remaining_timer_seconds = 0

        self._active_table_ips: Set[str] = set(self.DEFAULT_ROGUE_IPS)
        self._audit_records: List[Dict[str, Any]] = []
        self._blocked_packets_count = 0

    def start(self) -> bool:
        """Starts PF table synchronization."""
        with self._lock:
            self.is_active = True
            return True

    def stop(self) -> bool:
        """Stops daemon and flushes tables (respecting focus lock)."""
        with self._lock:
            if not self.can_uninstall():
                raise PermissionError(
                    f"ERROR_ACCESS_DENIED: Cannot deactivate pfSense PF rules while focus is active "
                    f"({self.remaining_timer_seconds}s remaining)."
                )
            self.is_active = False
            self._active_table_ips.clear()
            return True

    def set_lock(self, locked: bool, remaining_seconds: int = 0) -> None:
        """Sets conditional focus mode lock."""
        with self._lock:
            self.is_locked = locked
            self.remaining_timer_seconds = max(0, remaining_seconds)

    def can_uninstall(self) -> bool:
        """Evaluates Conditional Uninstallation Law."""
        with self._lock:
            return (not self.is_locked) and (self.remaining_timer_seconds == 0)

    def add_rogue_ip(self, ip_str: str) -> bool:
        """Adds rogue DoH IP to active PF table."""
        with self._lock:
            self._active_table_ips.add(ip_str)
            return True

    def remove_rogue_ip(self, ip_str: str) -> bool:
        """Removes an IP from active PF table."""
        with self._lock:
            if ip_str in self._active_table_ips:
                self._active_table_ips.remove(ip_str)
                return True
            return False

    def get_table_entries(self) -> List[str]:
        """Returns current list of blocked DoH IP addresses."""
        with self._lock:
            return sorted(list(self._active_table_ips))

    def parse_filter_log_line(self, log_line: str) -> Optional[Dict[str, Any]]:
        """
        Parses FreeBSD pf filter.log format:
        rule 1/(match) [block|pass] on em0: 192.168.1.100.54321 > 1.1.1.1.443: tcp
        """
        match = re.search(r'(block|pass)\s+on\s+(\w+):\s+([\d\.]+)\.(\d+)\s+>\s+([\d\.]+)\.(\d+)', log_line)
        if match:
            action, interface, src_ip, src_port, dst_ip, dst_port = match.groups()
            record = {
                "timestamp": time.time(),
                "action": action.upper(),
                "interface": interface,
                "src_ip": src_ip,
                "src_port": int(src_port),
                "dst_ip": dst_ip,
                "dst_port": int(dst_port)
            }
            if action.lower() == "block":
                with self._lock:
                    self._blocked_packets_count += 1
                    self._audit_records.append(record)
                    if len(self._audit_records) > 200:
                        self._audit_records.pop(0)
            return record
        return None

    def get_status(self) -> Dict[str, Any]:
        """Returns comprehensive PF sync status."""
        with self._lock:
            return {
                "anchor_name": self.anchor_name,
                "is_active": self.is_active,
                "is_locked": self.is_locked,
                "remaining_timer_seconds": self.remaining_timer_seconds,
                "can_uninstall": self.can_uninstall(),
                "active_table_ips_count": len(self._active_table_ips),
                "blocked_packets_count": self._blocked_packets_count,
                "audit_records_count": len(self._audit_records)
            }
