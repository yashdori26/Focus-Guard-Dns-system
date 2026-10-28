"""
server/engine/managed_config_distributor.py
Android Enterprise Managed Configurations (AppConfig) Distributor for FocusDNS MDM.

Generates and distributes AppConfig schemas and device-specific payloads for EMM systems
(Google Workspace, Microsoft Intune, VMware Workspace ONE, Ivanti Neurons).
"""

import json
import time
from typing import Dict, Any, List, Optional


class TenantAppConfig:
    def __init__(
        self,
        tenant_id: str,
        name: str,
        server_url: str = "https://dns.focusguard.internal",
        enrollment_token: str = "",
        enforce_strict_uninstall_lock: bool = False,
        whitelisted_packages: Optional[List[str]] = None,
        kiosk_enabled: bool = False,
        approved_dot_host: str = "dns.focusguard.internal",
    ):
        self.tenant_id = tenant_id
        self.name = name
        self.server_url = server_url
        self.enrollment_token = enrollment_token
        self.enforce_strict_uninstall_lock = enforce_strict_uninstall_lock
        self.whitelisted_packages = whitelisted_packages or []
        self.kiosk_enabled = kiosk_enabled
        self.approved_dot_host = approved_dot_host
        self.updated_at = time.time()

    def to_appconfig_bundle(self) -> Dict[str, Any]:
        """Returns standard AppConfig dictionary as consumed by Android RestrictionsManager."""
        return {
            "server_url": self.server_url,
            "tenant_id": self.tenant_id,
            "enrollment_token": self.enrollment_token,
            "enforce_strict_uninstall_lock": self.enforce_strict_uninstall_lock,
            "whitelisted_split_tunnel_pkgs": self.whitelisted_packages,
            "lock_task_kiosk_enabled": self.kiosk_enabled,
            "approved_dot_host": self.approved_dot_host,
        }

    def to_dict(self) -> Dict[str, Any]:
        return {
            "tenant_id": self.tenant_id,
            "name": self.name,
            "server_url": self.server_url,
            "enrollment_token": self.enrollment_token,
            "enforce_strict_uninstall_lock": self.enforce_strict_uninstall_lock,
            "whitelisted_packages": self.whitelisted_packages,
            "kiosk_enabled": self.kiosk_enabled,
            "approved_dot_host": self.approved_dot_host,
            "updated_at": self.updated_at,
        }


class ManagedConfigDistributor:
    """
    Central server-side manager distributing AppConfig bundles to enterprise fleets.
    """

    def __init__(self):
        self._tenant_configs: Dict[str, TenantAppConfig] = {}
        self._setup_defaults()

    def _setup_defaults(self) -> None:
        default_cfg = TenantAppConfig(
            tenant_id="default_enterprise",
            name="Default Corporate Configuration",
            server_url="https://dns.focusguard.internal",
            enrollment_token="tok_default_enterprise_provisioning",
            enforce_strict_uninstall_lock=False,
            whitelisted_packages=["com.slack", "com.zoom.videomeetings"],
            kiosk_enabled=False,
            approved_dot_host="dns.focusguard.internal",
        )
        self._tenant_configs[default_cfg.tenant_id] = default_cfg

    def create_or_update_config(self, config: TenantAppConfig) -> None:
        config.updated_at = time.time()
        self._tenant_configs[config.tenant_id] = config

    def set_tenant_config(self, config: TenantAppConfig) -> TenantAppConfig:
        config.updated_at = time.time()
        self._tenant_configs[config.tenant_id] = config
        return config

    def get_config(self, tenant_id: str) -> Optional[TenantAppConfig]:
        return self._tenant_configs.get(tenant_id)

    def get_tenant_config(self, tenant_id: str) -> Optional[TenantAppConfig]:
        return self._tenant_configs.get(tenant_id)

    def get_appconfig_bundle(self, tenant_id: str) -> Dict[str, Any]:
        cfg = self.get_config(tenant_id)
        if not cfg:
            cfg = self._tenant_configs["default_enterprise"]
        return cfg.to_appconfig_bundle()

    def generate_intune_sync_payload(self, tenant_id: str) -> Dict[str, Any]:
        """Generates Microsoft Intune App Protection & Configuration format."""
        cfg = self.get_appconfig_bundle(tenant_id)
        return {
            "appConfigProfileName": f"FocusDNS-Policy-{tenant_id}",
            "targetApplication": "com.focusdns.app",
            "settings": [
                {"key": k, "value": v, "valueType": type(v).__name__}
                for k, v in cfg.items()
            ],
            "timestamp": time.time(),
        }

    def list_configs(self) -> List[Dict[str, Any]]:
        return [c.to_dict() for c in self._tenant_configs.values()]
