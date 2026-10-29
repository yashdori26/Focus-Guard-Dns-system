"""
router/openwrt/mac_profile_router.py
DHCP Lease Analyzer and Hardware MAC-to-Profile Router for OpenWrt.

Responsibilities:
1. Ingests /tmp/dhcp.leases or /var/lib/misc/dnsmasq.leases.
2. Correlates client hardware MAC addresses and hostnames to FocusDNS custom profiles.
3. Automatically categorizes newly discovered devices (Smart TVs, iPads, consoles, guest devices).
4. Provides fast in-memory IP-to-profile lookup for router_stub_daemon.
"""

import time
import os
import re
from typing import Dict, Any, List, Optional


class ConnectedDeviceRecord:
    """Represents a connected LAN endpoint on the router."""

    def __init__(
        self,
        mac_address: str,
        ip_address: str,
        hostname: str,
        assigned_profile: str = "profile_home_primary",
        device_category: str = "Generic",
        strict_lock: bool = False,
    ):
        self.mac_address = mac_address.upper()
        self.ip_address = ip_address
        self.hostname = hostname or "Unknown Device"
        self.assigned_profile = assigned_profile
        self.device_category = device_category
        self.strict_lock = strict_lock
        self.last_seen = time.time()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "mac_address": self.mac_address,
            "ip_address": self.ip_address,
            "hostname": self.hostname,
            "assigned_profile": self.assigned_profile,
            "device_category": self.device_category,
            "strict_lock": self.strict_lock,
            "last_seen": self.last_seen,
        }


class MacProfileRouter:
    """
    Manages MAC address mapping and dynamic profile resolution for router clients.
    """

    OUI_CATEGORY_HINTS = {
        "D8:9E:3F": ("Apple", "Tablet"),
        "F0:18:98": ("Apple", "Laptop"),
        "AA:BB:CC": ("LG Electronics", "SmartTV"),
        "70:2C:1F": ("Samsung Electronics", "SmartTV"),
        "B8:27:EB": ("Raspberry Pi Foundation", "IoT"),
        "DC:A6:32": ("Raspberry Pi Foundation", "IoT"),
        "00:04:4B": ("NVIDIA", "GamingConsole"),
        "F8:46:1C": ("Sony Interactive", "GamingConsole"),
    }

    def __init__(
        self,
        default_profile: str = "profile_home_primary",
        dhcp_lease_path: str = "/tmp/dhcp.leases",
    ):
        self.default_profile = default_profile
        self.dhcp_lease_path = dhcp_lease_path
        self._mac_to_device: Dict[str, ConnectedDeviceRecord] = {}
        self._ip_to_device: Dict[str, ConnectedDeviceRecord] = {}

    def register_manual_mapping(
        self,
        mac_address: str,
        profile_id: str,
        hostname: Optional[str] = None,
        category: Optional[str] = None,
        strict_lock: bool = False,
    ) -> None:
        """Explicitly assigns a profile to a device MAC address."""
        clean_mac = mac_address.upper()
        dev = self._mac_to_device.get(clean_mac)
        if dev:
            dev.assigned_profile = profile_id
            if hostname:
                dev.hostname = hostname
            if category:
                dev.device_category = category
            dev.strict_lock = strict_lock
        else:
            dev = ConnectedDeviceRecord(
                mac_address=clean_mac,
                ip_address="",
                hostname=hostname or "Manual Configuration",
                assigned_profile=profile_id,
                device_category=category or "Generic",
                strict_lock=strict_lock,
            )
            self._mac_to_device[clean_mac] = dev

    def parse_dhcp_leases(self, file_content: Optional[str] = None) -> List[ConnectedDeviceRecord]:
        """
        Parses dnsmasq lease format:
        <expiry_epoch> <mac_address> <ip_address> <hostname> <client_id>
        """
        content = file_content
        if content is None:
            if not os.path.exists(self.dhcp_lease_path):
                return list(self._mac_to_device.values())
            try:
                with open(self.dhcp_lease_path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
            except Exception:
                return list(self._mac_to_device.values())

        for line in content.strip().split("\n"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 4:
                mac = parts[1].upper()
                ip = parts[2]
                host = parts[3] if parts[3] != "*" else "Unnamed Device"

                category = self._infer_category(mac, host)
                existing = self._mac_to_device.get(mac)
                if existing:
                    existing.ip_address = ip
                    existing.hostname = host
                    existing.last_seen = time.time()
                    self._ip_to_device[ip] = existing
                else:
                    new_dev = ConnectedDeviceRecord(
                        mac_address=mac,
                        ip_address=ip,
                        hostname=host,
                        assigned_profile=self.default_profile,
                        device_category=category,
                        strict_lock=False,
                    )
                    self._mac_to_device[mac] = new_dev
                    self._ip_to_device[ip] = new_dev

        return list(self._mac_to_device.values())

    def _infer_category(self, mac: str, hostname: str) -> str:
        """Heuristically determines device category from MAC OUI or hostname strings."""
        prefix = mac[:8]
        if prefix in self.OUI_CATEGORY_HINTS:
            return self.OUI_CATEGORY_HINTS[prefix][1]

        lower_host = hostname.lower()
        if any(w in lower_host for w in ["playstation", "ps5", "xbox", "switch", "nintendo"]):
            return "GamingConsole"
        if any(w in lower_host for w in ["tv", "oled", "webos", "roku", "bravia", "firetv"]):
            return "SmartTV"
        if any(w in lower_host for w in ["ipad", "tab", "galaxy-tab", "kindle"]):
            return "Tablet"
        if any(w in lower_host for w in ["iphone", "pixel", "galaxy-s", "oneplus", "xiaomi"]):
            return "Phone"
        if any(w in lower_host for w in ["macbook", "laptop", "pc", "desktop", "thinkpad", "surface"]):
            return "Laptop"
        if any(w in lower_host for w in ["hub", "echo", "nest", "camera", "sonos", "plug", "hue"]):
            return "IoT"
        return "Generic"

    def resolve_profile_for_ip(self, ip_address: str) -> str:
        """Resolves target FocusDNS profile token for an incoming client IP address."""
        dev = self._ip_to_device.get(ip_address)
        if dev:
            return dev.assigned_profile
        return self.default_profile

    def resolve_profile_for_mac(self, mac_address: str) -> str:
        """Resolves target FocusDNS profile token for a client MAC address."""
        dev = self._mac_to_device.get(mac_address.upper())
        if dev:
            return dev.assigned_profile
        return self.default_profile

    def get_all_devices(self) -> List[Dict[str, Any]]:
        """Returns JSON-serializable list of all registered and discovered devices."""
        return [d.to_dict() for d in self._mac_to_device.values()]
