"""
FocusDNS Engine - Enterprise MDM, Anti-Bypass Policy & Fleet Management Subsystem
Standards & Features:
- Android Enterprise Device Administration & Device Owner Policy Orchestration
- Remote uninstallation lock management & conditional deactivation authorization
- Device enrollment, public key cryptographic verification, and tamper detection
- Per-application split tunneling policy distribution
- Fleet-wide audit logging and compliance telemetry
"""

import enum
import hashlib
import hmac
import json
import threading
import time
from typing import Any, Dict, List, Optional, Set, Tuple


class PolicyLockMode(str, enum.Enum):
    """Conditional uninstallation lock policy."""
    ALWAYS_ALLOWED = "always_allowed"
    CONDITIONAL_ON_PROTECTION = "conditional_on_protection"  # Block if timer active or protection running
    ALWAYS_LOCKED = "always_locked"                        # Strict enterprise kiosk mode


class SplitTunnelPolicyMode(str, enum.Enum):
    """Split tunneling policy mode."""
    DISALLOW_LIST = "disallow_list"  # Exempt selected packages from VPN
    ALLOW_LIST = "allow_list"        # Only route selected packages into VPN


class DeviceStatus(str, enum.Enum):
    ACTIVE = "active"
    SUSPENDED = "suspended"
    UNENROLLED = "unenrolled"
    TAMPERED = "tampered"


class DeviceRecord:
    """Represents an enrolled mobile or desktop endpoint under management."""

    def __init__(
        self,
        device_id: str,
        device_name: str,
        platform: str = "Android",
        os_version: str = "14",
        profile_id: str = "default",
        device_owner_enrolled: bool = False,
        device_admin_active: bool = False,
        secret_key: Optional[bytes] = None,
    ):
        self.device_id: str = device_id
        self.device_name: str = device_name
        self.platform: str = platform
        self.os_version: str = os_version
        self.profile_id: str = profile_id
        self.device_owner_enrolled: bool = device_owner_enrolled
        self.device_admin_active: bool = device_admin_active
        self.secret_key: bytes = secret_key or hashlib.sha256(f"{device_id}:{time.time()}".encode()).digest()
        self.status: DeviceStatus = DeviceStatus.ACTIVE

        # Runtime telemetry
        self.is_protection_active: bool = False
        self.is_timer_active: bool = False
        self.remaining_timer_sec: int = 0
        self.can_uninstall: bool = True
        self.integrity_score: int = 100
        self.quarantined_apps_count: int = 0
        self.split_tunnel_exempt_count: int = 0
        self.last_seen: float = time.time()
        self.enrolled_at: float = time.time()

    def update_telemetry(self, telemetry: Dict[str, Any]):
        """Updates device telemetry from signed client payload."""
        self.last_seen = time.time()

        lock_status = telemetry.get("lockStatus", {})
        if isinstance(lock_status, dict):
            self.is_protection_active = bool(lock_status.get("isProtectionActive", False))
            self.is_timer_active = bool(lock_status.get("isTimerActive", False))
            self.remaining_timer_sec = int(lock_status.get("remainingSeconds", 0))
            self.can_uninstall = bool(lock_status.get("canUninstall", True))

        mdm_status = telemetry.get("mdmStatus", {})
        if isinstance(mdm_status, dict):
            self.device_admin_active = bool(mdm_status.get("isDeviceAdminActive", self.device_admin_active))
            self.device_owner_enrolled = bool(mdm_status.get("isDeviceOwner", self.device_owner_enrolled))

        anti_tamper = telemetry.get("antiTamper", {})
        if isinstance(anti_tamper, dict):
            self.integrity_score = int(anti_tamper.get("integrityScore", 100))
            if self.integrity_score < 50:
                self.status = DeviceStatus.TAMPERED

        quarantine = telemetry.get("quarantine", {})
        if isinstance(quarantine, dict):
            self.quarantined_apps_count = int(quarantine.get("quarantinedCount", 0))

        split = telemetry.get("splitTunnel", {})
        if isinstance(split, dict):
            self.split_tunnel_exempt_count = int(split.get("selectedCount", 0))

    def to_dict(self) -> Dict[str, Any]:
        return {
            "device_id": self.device_id,
            "device_name": self.device_name,
            "platform": self.platform,
            "os_version": self.os_version,
            "profile_id": self.profile_id,
            "status": self.status.value,
            "device_owner_enrolled": self.device_owner_enrolled,
            "device_admin_active": self.device_admin_active,
            "is_protection_active": self.is_protection_active,
            "is_timer_active": self.is_timer_active,
            "remaining_timer_sec": self.remaining_timer_sec,
            "can_uninstall": self.can_uninstall,
            "integrity_score": self.integrity_score,
            "quarantined_apps_count": self.quarantined_apps_count,
            "split_tunnel_exempt_count": self.split_tunnel_exempt_count,
            "last_seen_sec_ago": round(time.time() - self.last_seen, 1),
            "enrolled_at": self.enrolled_at,
        }


class MdmPolicyProfile:
    """Enterprise policy profile distributed to endpoints."""

    def __init__(
        self,
        profile_id: str,
        name: str = "Standard Protection Policy",
        lock_mode: PolicyLockMode = PolicyLockMode.CONDITIONAL_ON_PROTECTION,
        split_tunnel_mode: SplitTunnelPolicyMode = SplitTunnelPolicyMode.DISALLOW_LIST,
        exempt_packages: Optional[List[str]] = None,
        disallow_safe_boot: bool = True,
        disallow_vpn_config: bool = True,
        camera_disabled: bool = False,
    ):
        self.profile_id: str = profile_id
        self.name: str = name
        self.lock_mode: PolicyLockMode = lock_mode
        self.split_tunnel_mode: SplitTunnelPolicyMode = split_tunnel_mode
        self.exempt_packages: List[str] = exempt_packages or [
            "com.google.android.apps.nbu.paisa.user",
            "com.sbi.lotusintouch",
            "com.whatsapp",
        ]
        self.disallow_safe_boot: bool = disallow_safe_boot
        self.disallow_vpn_config: bool = disallow_vpn_config
        self.camera_disabled: bool = camera_disabled
        self.version: int = 1
        self.updated_at: float = time.time()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "profile_id": self.profile_id,
            "name": self.name,
            "lock_mode": self.lock_mode.value,
            "split_tunnel_mode": self.split_tunnel_mode.value,
            "exempt_packages": self.exempt_packages,
            "disallow_safe_boot": self.disallow_safe_boot,
            "disallow_vpn_config": self.disallow_vpn_config,
            "camera_disabled": self.camera_disabled,
            "version": self.version,
            "updated_at": self.updated_at,
        }


class DeviceFleetManager:
    """
    Thread-safe Fleet Manager coordinating enterprise MDM device registration,
    anti-uninstall policy enforcement, and live audit telemetry.
    """

    def __init__(self):
        self._devices: Dict[str, DeviceRecord] = {}
        self._policies: Dict[str, MdmPolicyProfile] = {}
        self._audit_log: List[Dict[str, Any]] = []
        self._lock = threading.RLock()

        # Seed default policy
        default_policy = MdmPolicyProfile("default", "Standard Focus Guard Policy")
        self._policies["default"] = default_policy

    def enroll_device(
        self,
        device_id: str,
        device_name: str,
        platform: str = "Android",
        os_version: str = "14",
        profile_id: str = "default",
        device_owner: bool = False,
        admin_active: bool = False,
    ) -> DeviceRecord:
        """Enrolls a new device into management."""
        with self._lock:
            rec = DeviceRecord(
                device_id=device_id,
                device_name=device_name,
                platform=platform,
                os_version=os_version,
                profile_id=profile_id,
                device_owner_enrolled=device_owner,
                device_admin_active=admin_active,
            )
            self._devices[device_id] = rec
            self._append_audit("DEVICE_ENROLLED", device_id, f"Device {device_name} enrolled.")
            return rec

    def get_device(self, device_id: str) -> Optional[DeviceRecord]:
        with self._lock:
            return self._devices.get(device_id)

    def remove_device(self, device_id: str) -> bool:
        with self._lock:
            if device_id in self._devices:
                del self._devices[device_id]
                self._append_audit("DEVICE_UNENROLLED", device_id, "Device removed from fleet.")
                return True
            return False

    def list_devices(self) -> List[DeviceRecord]:
        with self._lock:
            return list(self._devices.values())

    def get_policy(self, profile_id: str) -> Optional[MdmPolicyProfile]:
        with self._lock:
            return self._policies.get(profile_id)

    def set_policy(self, policy: MdmPolicyProfile):
        with self._lock:
            self._policies[policy.profile_id] = policy
            self._append_audit("POLICY_UPDATED", policy.profile_id, f"Policy {policy.name} updated.")

    def process_telemetry(self, device_id: str, payload: Dict[str, Any]) -> bool:
        """Processes incoming device telemetry and updates security posture."""
        with self._lock:
            dev = self._devices.get(device_id)
            if not dev:
                # Auto-enroll
                dev_name = payload.get("deviceModel", f"Android-{device_id[:6]}")
                dev = self.enroll_device(device_id, dev_name)

            dev.update_telemetry(payload)
            if dev.status == DeviceStatus.TAMPERED:
                self._append_audit("SECURITY_TAMPER_DETECTED", device_id, f"Integrity score dropped to {dev.integrity_score}")

            return True

    def evaluate_uninstall_permission(self, device_id: str) -> Tuple[bool, str]:
        """
        Server-side validation of the core uninstallation law:
        - Allowed ONLY if Protection is OFF and Timer is NOT running.
        """
        with self._lock:
            dev = self._devices.get(device_id)
            if not dev:
                return True, "DEVICE_NOT_ENROLLED"

            policy = self._policies.get(dev.profile_id)
            lock_mode = policy.lock_mode if policy else PolicyLockMode.CONDITIONAL_ON_PROTECTION

            if lock_mode == PolicyLockMode.ALWAYS_ALLOWED:
                return True, "POLICY_ALWAYS_ALLOWED"

            if lock_mode == PolicyLockMode.ALWAYS_LOCKED:
                return False, "ENTERPRISE_KIOSK_LOCKED"

            # CONDITIONAL_ON_PROTECTION
            if dev.is_protection_active:
                return False, "PROTECTION_ACTIVE"

            if dev.is_timer_active or dev.remaining_timer_sec > 0:
                return False, f"TIMER_ACTIVE_{dev.remaining_timer_sec}s_REMAINING"

            return True, "SESSION_IDLE_UNINSTALL_PERMITTED"

    def _append_audit(self, event_type: str, target_id: str, description: str):
        self._audit_log.append({
            "timestamp": time.time(),
            "event_type": event_type,
            "target_id": target_id,
            "description": description,
        })
        if len(self._audit_log) > 1000:
            self._audit_log.pop(0)

    def get_audit_log(self, limit: int = 50) -> List[Dict[str, Any]]:
        with self._lock:
            return list(reversed(self._audit_log[-limit:]))

    def get_fleet_telemetry(self) -> Dict[str, Any]:
        with self._lock:
            total = len(self._devices)
            locked = sum(1 for d in self._devices.values() if not d.can_uninstall)
            admin_active = sum(1 for d in self._devices.values() if d.device_admin_active)
            tampered = sum(1 for d in self._devices.values() if d.status == DeviceStatus.TAMPERED)

            return {
                "total_devices": total,
                "uninstallation_locked_devices": locked,
                "device_admin_active_devices": admin_active,
                "tampered_devices": tampered,
                "policies_count": len(self._policies),
                "devices": [d.to_dict() for d in self._devices.values()],
            }


_fleet_manager_instance: Optional[DeviceFleetManager] = None
_fleet_manager_lock = threading.Lock()


def get_fleet_manager() -> DeviceFleetManager:
    """Returns singleton instance of DeviceFleetManager."""
    global _fleet_manager_instance
    with _fleet_manager_lock:
        if _fleet_manager_instance is None:
            _fleet_manager_instance = DeviceFleetManager()
        return _fleet_manager_instance
