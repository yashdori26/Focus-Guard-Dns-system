"""
macOS NetworkExtension & MobileConfig Profile Management Engine.

Generates signed MDM configuration profiles (.mobileconfig) for macOS Ventura, Sonoma,
and Sequoia, deploying:
1. com.apple.dnsProxy.managed (System-wide NEDNSProxyProvider)
2. com.apple.webcontent-filter (NEFilterDataProvider rogue DoH/DoT drop filter)
3. com.apple.systemextensions.install (Pre-approved daemon activation)

Enforces Conditional Uninstallation:
- PayloadRemovalDisallowed = True when focus session is active or countdown timer > 0.
- PayloadRemovalDisallowed = False when idle, allowing smooth removal.
"""

import uuid
import plistlib
import threading
from typing import Dict, Any, Optional, List


class MacOsExtensionManager:
    """Manages macOS configuration profiles, launchd plists, and extension telemetry."""

    ORGANIZATION = "FocusGuard Security Inc."
    BUNDLE_IDENTIFIER = "com.focusguard.dns.app"
    EXTENSION_BUNDLE_ID = "com.focusguard.dns.extension"
    DAEMON_LABEL = "com.focusguard.dns.daemon"

    def __init__(self):
        self._lock = threading.RLock()
        self._is_protection_active = False
        self._remaining_timer_seconds = 0
        self._active_profile = "profile_mac_workstation"
        self._audit_events: List[Dict[str, Any]] = []

    def set_protection(self, active: bool, timer_seconds: int = 0) -> None:
        """Sets macOS focus mode protection and countdown timer."""
        with self._lock:
            self._is_protection_active = active
            self._remaining_timer_seconds = max(0, timer_seconds)
            self._log_audit("POLICY_UPDATE", {
                "protection_active": active,
                "remaining_seconds": self._remaining_timer_seconds
            })

    def can_uninstall(self) -> bool:
        """Evaluates Conditional Uninstallation Law for macOS."""
        with self._lock:
            return (not self._is_protection_active) and (self._remaining_timer_seconds == 0)

    def generate_mobileconfig(self, profile_id: Optional[str] = None) -> bytes:
        """
        Compiles an Apple .mobileconfig property list containing SystemExtension,
        DNSProxy, and ContentFilter payloads with conditional removal lock.
        """
        with self._lock:
            active_profile = profile_id or self._active_profile
            can_uninst = self.can_uninstall()

            root_uuid = str(uuid.uuid4())
            dns_payload_uuid = str(uuid.uuid4())
            filter_payload_uuid = str(uuid.uuid4())
            sysext_payload_uuid = str(uuid.uuid4())

            # 1. System Extension Authorization Payload
            sysext_payload = {
                "PayloadType": "com.apple.systemextensions.install",
                "PayloadVersion": 1,
                "PayloadIdentifier": f"{self.BUNDLE_IDENTIFIER}.sysext.{sysext_payload_uuid}",
                "PayloadUUID": sysext_payload_uuid,
                "PayloadDisplayName": "FocusGuard System Extension Authorization",
                "PayloadDescription": "Pre-approves FocusGuard DNS Proxy and Network Content Filter.",
                "PayloadOrganization": self.ORGANIZATION,
                "AllowedSystemExtensions": {
                    "TEAMIDFOCUS": [
                        self.EXTENSION_BUNDLE_ID
                    ]
                },
                "AllowedSystemExtensionTypes": {
                    "TEAMIDFOCUS": ["com.apple.system_extension.network_extension"]
                }
            }

            # 2. System-wide DNS Proxy Managed Payload
            dns_proxy_payload = {
                "PayloadType": "com.apple.dnsProxy.managed",
                "PayloadVersion": 1,
                "PayloadIdentifier": f"{self.BUNDLE_IDENTIFIER}.dnsproxy.{dns_payload_uuid}",
                "PayloadUUID": dns_payload_uuid,
                "PayloadDisplayName": "FocusGuard System-Wide DNS Proxy",
                "PayloadDescription": "Directs all system DNS queries into the FocusDNS engine.",
                "PayloadOrganization": self.ORGANIZATION,
                "AppBundleIdentifier": self.EXTENSION_BUNDLE_ID,
                "ProviderBundleIdentifier": self.EXTENSION_BUNDLE_ID,
                "ProviderConfiguration": {
                    "serverAddress": "127.0.0.1",
                    "serverPort": 53,
                    "profileId": active_profile,
                    "isFocusLockActive": not can_uninst,
                    "remainingTimerSeconds": self._remaining_timer_seconds
                }
            }

            # 3. Content Filter Payload (Drops Rogue DoH/DoT)
            content_filter_payload = {
                "PayloadType": "com.apple.webcontent-filter",
                "PayloadVersion": 1,
                "PayloadIdentifier": f"{self.BUNDLE_IDENTIFIER}.contentfilter.{filter_payload_uuid}",
                "PayloadUUID": filter_payload_uuid,
                "PayloadDisplayName": "FocusGuard Network Socket Firewall",
                "PayloadDescription": "Blocks unmanaged DoH/DoT bypass IP addresses.",
                "PayloadOrganization": self.ORGANIZATION,
                "FilterType": "Plugin",
                "PluginBundleID": self.EXTENSION_BUNDLE_ID,
                "FilterSockets": True,
                "FilterPackets": True,
                "VendorConfig": {
                    "blockPublicDoh": True,
                    "rogueDotPort": 853,
                    "allowLocalResolver": "127.0.0.1"
                }
            }

            # Root Profile Document
            profile_dict = {
                "PayloadType": "Configuration",
                "PayloadVersion": 1,
                "PayloadIdentifier": f"{self.BUNDLE_IDENTIFIER}.profile.{root_uuid}",
                "PayloadUUID": root_uuid,
                "PayloadDisplayName": "FocusGuard macOS Workstation Shield",
                "PayloadDescription": "Zero-Bypass DNS Proxy and Content Filter for macOS.",
                "PayloadOrganization": self.ORGANIZATION,
                "PayloadRemovalDisallowed": not can_uninst,  # Inviolable lock
                "PayloadContent": [
                    sysext_payload,
                    dns_proxy_payload,
                    content_filter_payload
                ]
            }

            return plistlib.dumps(profile_dict, fmt=plistlib.FMT_XML)

    def generate_launchd_plist(self) -> str:
        """Generates /Library/LaunchDaemons/com.focusguard.dns.daemon.plist."""
        plist_data = {
            "Label": self.DAEMON_LABEL,
            "ProgramArguments": [
                "/usr/local/bin/focusguard-daemon",
                "--foreground",
                "--profile", self._active_profile
            ],
            "RunAtLoad": True,
            "KeepAlive": {
                "SuccessfulExit": False,
                "Crashed": True
            },
            "StandardErrorPath": "/var/log/focusguard.err",
            "StandardOutPath": "/var/log/focusguard.out",
            "HardResourceLimits": {
                "NumberOfFiles": 4096
            }
        }
        return plistlib.dumps(plist_data, fmt=plistlib.FMT_XML).decode("utf-8")

    def process_telemetry_event(self, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """Ingests live telemetry from macOS Network Extension."""
        with self._lock:
            event_type = event_data.get("event_type", "HEARTBEAT")
            self._log_audit(event_type, event_data)

            # Check for simulated tamper attempt
            if event_type == "ATTEMPT_UNINSTALL" and not self.can_uninstall():
                self._log_audit("TAMPER_BLOCKED", {
                    "reason": "Attempted uninstallation during active focus lock",
                    "remaining_seconds": self._remaining_timer_seconds
                })
                return {
                    "status": "REJECTED",
                    "error_code": "ERROR_ACCESS_DENIED",
                    "message": "FocusGuard uninstallation locked during active focus session."
                }

            return {
                "status": "OK",
                "can_uninstall": self.can_uninstall(),
                "remaining_seconds": self._remaining_timer_seconds
            }

    def get_status(self) -> Dict[str, Any]:
        """Returns comprehensive status dictionary for REST APIs and UI."""
        with self._lock:
            return {
                "platform": "macOS",
                "service_active": True,
                "is_protection_active": self._is_protection_active,
                "remaining_timer_seconds": self._remaining_timer_seconds,
                "can_uninstall": self.can_uninstall(),
                "active_profile": self._active_profile,
                "bundle_id": self.EXTENSION_BUNDLE_ID,
                "audit_events_count": len(self._audit_events)
            }

    def _log_audit(self, action: str, details: Dict[str, Any]) -> None:
        self._audit_events.append({
            "action": action,
            "details": details
        })
        if len(self._audit_events) > 100:
            self._audit_events.pop(0)
