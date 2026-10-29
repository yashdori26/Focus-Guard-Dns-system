"""
server/engine/windows_daemon_controller.py
Python Controller, IPC Bridge, and Emulation Harness for the FocusDNS Windows WFP Service.

Coordinates:
1. Named Pipe IPC communication with the native FocusDnsWfpService.
2. Inviolable Conditional Service Protection Law enforcement on Windows desktop.
3. Live bypass audit logging for Chrome DoH, Edge, Discord, and Steam connection attempts.
4. Remote policy orchestration and uninstallation clearance verification.
"""

import time
import os
import threading
from typing import Dict, Any, List, Optional, Tuple


class WindowsAppPolicy:
    """Represents a per-application WFP firewall policy."""

    def __init__(
        self,
        app_name: str,
        executable_path: str,
        is_blocked: bool = False,
        category: str = "Application",
    ):
        self.app_name = app_name
        self.executable_path = executable_path
        self.is_blocked = is_blocked
        self.category = category
        self.last_updated = time.time()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "app_name": self.app_name,
            "executable_path": self.executable_path,
            "is_blocked": self.is_blocked,
            "category": self.category,
            "last_updated": self.last_updated,
        }


class WindowsBypassAuditRecord:
    """Audit log entry capturing an intercepted bypass attempt on Windows."""

    def __init__(
        self,
        audit_id: str,
        app_name: str,
        target_ip: str,
        target_port: int,
        protocol: str,
        action_taken: str = "BLOCKED_BY_WFP",
        reason: str = "Rogue DoH/DoT bypass intercepted",
    ):
        self.audit_id = audit_id
        self.app_name = app_name
        self.target_ip = target_ip
        self.target_port = target_port
        self.protocol = protocol
        self.action_taken = action_taken
        self.reason = reason
        self.timestamp = time.time()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "audit_id": self.audit_id,
            "app_name": self.app_name,
            "target_ip": self.target_ip,
            "target_port": self.target_port,
            "protocol": self.protocol,
            "action_taken": self.action_taken,
            "reason": self.reason,
            "timestamp": self.timestamp,
        }


class WindowsDaemonController:
    """
    Manages the Windows WFP service lifecycle, state synchronization,
    and anti-tamper uninstallation protection.
    """

    def __init__(
        self,
        pipe_name: str = r"\\.\pipe\FocusDnsWfpIpc",
        is_mock_mode: bool = True,
    ):
        self.pipe_name = pipe_name
        self.is_mock_mode = is_mock_mode
        self._lock = threading.RLock()

        # Internal state
        self._is_service_running: bool = True
        self._is_protection_active: bool = False
        self._remaining_timer_seconds: int = 0
        self._total_filters_installed: int = 14
        self._app_policies: Dict[str, WindowsAppPolicy] = {}
        self._audit_log: List[WindowsBypassAuditRecord] = []

        self._initialize_default_apps()

    def _initialize_default_apps(self) -> None:
        defaults = [
            WindowsAppPolicy("Google Chrome", r"C:\Program Files\Google\Chrome\Application\chrome.exe", False, "Browser"),
            WindowsAppPolicy("Microsoft Edge", r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe", False, "Browser"),
            WindowsAppPolicy("Mozilla Firefox", r"C:\Program Files\Mozilla Firefox\firefox.exe", False, "Browser"),
            WindowsAppPolicy("Discord", r"C:\Users\User\AppData\Local\Discord\app-1.0.9000\Discord.exe", False, "Chat"),
            WindowsAppPolicy("Steam", r"C:\Program Files (x86)\Steam\steam.exe", False, "Gaming"),
        ]
        for app in defaults:
            self._app_policies[app.app_name.lower()] = app

    def can_uninstall(self) -> bool:
        """
        Inviolable Conditional Uninstallation Law on Windows:
        - Normal Mode (Protection OFF & Timer 0): Clean uninstallation is 100% permitted.
        - Active Focus Mode (Protection ON or Timer > 0): Uninstallation is strictly locked.
        """
        with self._lock:
            if self._is_protection_active:
                return False
            if self._remaining_timer_seconds > 0:
                return False
            return True

    def arm_focus_lock(self, duration_seconds: int = 1800) -> bool:
        """Arms active focus mode and starts monotonic timer."""
        with self._lock:
            self._is_protection_active = True
            self._remaining_timer_seconds = max(0, duration_seconds)
            # Recompile filter count simulation
            self._total_filters_installed = 14 + sum(1 for a in self._app_policies.values() if a.is_blocked)
            return True

    def disarm_focus_lock(self) -> bool:
        """Disarms focus mode and clears timer, restoring normal idle state."""
        with self._lock:
            self._is_protection_active = False
            self._remaining_timer_seconds = 0
            self._total_filters_installed = 14
            return True

    def simulate_service_stop_attempt(self) -> Tuple[bool, str]:
        """
        Simulates an external `net stop FocusDnsWfpService` or `sc delete` attempt.
        Returns:
            (success: bool, status_message: str)
        """
        with self._lock:
            if not self.can_uninstall():
                msg = (
                    f"SERVICE_CONTROL_STOP REJECTED: ERROR_ACCESS_DENIED (5). "
                    f"Active Focus protection is locked with {self._remaining_timer_seconds}s remaining. "
                    f"Tampering and uninstallation are strictly prohibited until timer completion."
                )
                return False, msg

            self._is_service_running = False
            return True, "SERVICE_STOPPED: Clean shutdown permitted in normal idle mode."

    def block_application(self, app_name: str) -> bool:
        """Adds process-specific WFP blocking filter for designated application."""
        with self._lock:
            key = app_name.lower()
            if key in self._app_policies:
                self._app_policies[key].is_blocked = True
                self._total_filters_installed += 1
                return True
            # New application entry
            self._app_policies[key] = WindowsAppPolicy(
                app_name=app_name,
                executable_path=rf"C:\Program Files\{app_name}\{app_name}.exe",
                is_blocked=True,
            )
            self._total_filters_installed += 1
            return True

    def unblock_application(self, app_name: str) -> bool:
        """Removes process-specific WFP filter for designated application."""
        with self._lock:
            key = app_name.lower()
            if key in self._app_policies and self._app_policies[key].is_blocked:
                self._app_policies[key].is_blocked = False
                self._total_filters_installed = max(14, self._total_filters_installed - 1)
                return True
            return False

    def record_bypass_attempt(
        self,
        app_name: str,
        target_ip: str,
        target_port: int = 443,
        protocol: str = "TCP",
    ) -> WindowsBypassAuditRecord:
        """Records an intercepted bypass attempt into the audit ring buffer."""
        record = WindowsBypassAuditRecord(
            audit_id=f"audit_{os.urandom(6).hex()}",
            app_name=app_name,
            target_ip=target_ip,
            target_port=target_port,
            protocol=protocol,
            action_taken="BLOCKED_BY_WFP_KERNEL",
            reason="Unauthorized DoH / DoT circumvention intercepted by FocusDNS sublayer",
        )
        with self._lock:
            self._audit_log.append(record)
            if len(self._audit_log) > 500:
                self._audit_log.pop(0)
        return record

    def get_status(self) -> Dict[str, Any]:
        """Returns comprehensive telemetry on Windows WFP service."""
        with self._lock:
            return {
                "service_running": self._is_service_running,
                "is_protection_active": self._is_protection_active,
                "remaining_timer_seconds": self._remaining_timer_seconds,
                "can_uninstall": self.can_uninstall(),
                "total_filters_installed": self._total_filters_installed,
                "sublayers_registered": 2,
                "provider_guid": "{5D3E82A1-6B92-4C3D-8E1A-2F7B9C4D6E01}",
                "app_policies": [p.to_dict() for p in self._app_policies.values()],
                "audit_log_count": len(self._audit_log),
                "timestamp": time.time(),
            }

    def get_audit_log(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Returns recently recorded bypass interception events."""
        with self._lock:
            return [r.to_dict() for r in self._audit_log[-limit:]]
