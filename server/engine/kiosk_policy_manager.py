"""
server/engine/kiosk_policy_manager.py
LockTask (Dedicated Single & Multi-App Kiosk) Fleet Policy Manager for FocusDNS MDM.

Manages enterprise kiosk profiles with hardcoded emergency call life-safety guarantees:
- Always enforces inclusion of native dialers:
  com.android.phone, com.google.android.dialer, com.samsung.incallui, com.android.server.telecom.
- Dynamic transition between Kiosk Mode (during active focus) and Unlocked Normal Mode (when idle).
- Normal mode completely removes LockTask constraints and permits clean uninstallation.
"""

import time
from typing import Dict, Any, List, Optional, Set


# Inviolable emergency dialers that must NEVER be omitted from any kiosk profile
MANDATORY_EMERGENCY_PACKAGES = [
    "com.android.phone",
    "com.google.android.dialer",
    "com.samsung.incallui",
    "com.android.server.telecom",
]


class KioskProfile:
    def __init__(
        self,
        profile_id: str,
        name: str,
        primary_app: str = "com.focusdns.app",
        allowed_packages: Optional[List[str]] = None,
        allow_system_info: bool = True,
        allow_keyguard: bool = True,
        allow_notifications: bool = False,
        enforce_on_focus: bool = True,
    ):
        self.profile_id = profile_id
        self.name = name
        self.primary_app = primary_app
        self.allow_system_info = allow_system_info
        self.allow_keyguard = allow_keyguard
        self.allow_notifications = allow_notifications
        self.enforce_on_focus = enforce_on_focus
        self.created_at = time.time()

        # Build permitted set ensuring emergency dialers are hardcoded
        pkgs: Set[str] = {primary_app}
        pkgs.update(MANDATORY_EMERGENCY_PACKAGES)
        if allowed_packages:
            pkgs.update(allowed_packages)
        self.allowed_packages = sorted(list(pkgs))

    def to_dict(self) -> Dict[str, Any]:
        return {
            "profile_id": self.profile_id,
            "name": self.name,
            "primary_app": self.primary_app,
            "allowed_packages": self.allowed_packages,
            "allow_system_info": self.allow_system_info,
            "allow_keyguard": self.allow_keyguard,
            "allow_notifications": self.allow_notifications,
            "enforce_on_focus": self.enforce_on_focus,
            "emergency_packages_enforced": True,
            "created_at": self.created_at,
        }


class KioskPolicyManager:
    """
    Central server-side manager orchestrating fleet-wide LockTask Kiosk policies.
    """

    def __init__(self):
        self._profiles: Dict[str, KioskProfile] = {}
        self._device_kiosk_map: Dict[str, str] = {}  # device_id -> profile_id
        self._device_kiosk_states: Dict[str, bool] = {}  # device_id -> is_active
        self._setup_default_profiles()

    def _setup_default_profiles(self) -> None:
        # Default strict focus kiosk: FocusDNS + Emergency Phone
        strict_profile = KioskProfile(
            profile_id="kiosk_strict_focus",
            name="Strict Focus Single-App Lock",
            primary_app="com.focusdns.app",
            allowed_packages=[],
            allow_system_info=True,
            allow_keyguard=True,
            allow_notifications=False,
            enforce_on_focus=True,
        )
        self._profiles[strict_profile.profile_id] = strict_profile

        # Multi-app educational / study kiosk
        study_profile = KioskProfile(
            profile_id="kiosk_study_utility",
            name="Study & Productivity Multi-App Lock",
            primary_app="com.focusdns.app",
            allowed_packages=[
                "com.google.android.calculator",
                "com.google.android.calendar",
                "com.google.android.keep",
            ],
            allow_system_info=True,
            allow_keyguard=True,
            allow_notifications=True,
            enforce_on_focus=True,
        )
        self._profiles[study_profile.profile_id] = study_profile

    def create_or_update_profile(self, profile: KioskProfile) -> None:
        self._profiles[profile.profile_id] = profile

    def save_profile(self, profile: KioskProfile) -> KioskProfile:
        self._profiles[profile.profile_id] = profile
        return profile

    def get_profile(self, profile_id: str) -> Optional[KioskProfile]:
        if profile_id == "default":
            return self._profiles.get("kiosk_strict_focus")
        return self._profiles.get(profile_id)

    def list_profiles(self) -> List[Dict[str, Any]]:
        return [p.to_dict() for p in self._profiles.values()]

    def assign_profile_to_device(self, device_id: str, profile_id: str) -> bool:
        if profile_id not in self._profiles:
            return False
        self._device_kiosk_map[device_id] = profile_id
        return True

    def evaluate_kiosk_directive(self, device_id: str, is_focus_active: bool) -> Dict[str, Any]:
        """
        Evaluates whether a device should enter or exit LockTask Kiosk Mode.
        - If is_focus_active = True and profile enforces kiosk: Returns directive to START kiosk.
        - If is_focus_active = False (Normal Mode): Returns directive to STOP kiosk,
          clearing all restrictions and allowing clean uninstallation.
        """
        profile_id = self._device_kiosk_map.get(device_id, "kiosk_strict_focus")
        profile = self._profiles.get(profile_id, self._profiles["kiosk_strict_focus"])

        should_activate = is_focus_active and profile.enforce_on_focus
        self._device_kiosk_states[device_id] = should_activate

        return {
            "device_id": device_id,
            "profile_id": profile.profile_id,
            "profile_name": profile.name,
            "action": "START_KIOSK" if should_activate else "STOP_KIOSK",
            "kiosk_active": should_activate,
            "allowed_packages": profile.allowed_packages if should_activate else ["com.focusdns.app"],
            "allow_system_info": profile.allow_system_info,
            "allow_keyguard": profile.allow_keyguard,
            "emergency_exemption_law": "Emergency dialers (911/112) are guaranteed unblocked under all kiosk modes.",
            "uninstallation_permitted": not should_activate,
            "timestamp": time.time(),
        }

    def get_device_kiosk_state(self, device_id: str) -> bool:
        return self._device_kiosk_states.get(device_id, False)

    def get_fleet_kiosk_summary(self) -> Dict[str, Any]:
        total_assigned = len(self._device_kiosk_map)
        active_count = sum(1 for active in self._device_kiosk_states.values() if active)
        return {
            "total_assigned_devices": total_assigned,
            "active_kiosks": active_count,
            "standby_kiosks": total_assigned - active_count,
            "available_profiles_count": len(self._profiles),
        }
