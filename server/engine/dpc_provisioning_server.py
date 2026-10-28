"""
server/engine/dpc_provisioning_server.py
Android Enterprise Zero-Touch & QR Code Provisioning Engine for FocusDNS MDM.

Generates standardized Google DPC enrollment bundles conforming to:
- Android Enterprise Zero-Touch Enrollment
- NFC & QR Code Device Owner Provisioning
- Managed Google Play Accounts & Work Profile Enrolment
"""

import base64
import hashlib
import json
import os
import time
from typing import Dict, Any, List, Optional


# Standard Google DPC Provisioning Extra Keys
EXTRA_PACKAGE_NAME = "android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME"
EXTRA_COMPONENT_NAME = "android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME"
EXTRA_SIGNATURE_CHECKSUM = "android.app.extra.PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM"
EXTRA_ADMIN_EXTRAS = "android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE"
EXTRA_LEAVE_ALL_SYSTEM_APPS = "android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED"
EXTRA_SKIP_ENCRYPTION = "android.app.extra.PROVISIONING_SKIP_ENCRYPTION"
EXTRA_WIFI_SSID = "android.app.extra.PROVISIONING_WIFI_SSID"
EXTRA_WIFI_SECURITY = "android.app.extra.PROVISIONING_WIFI_SECURITY_TYPE"
EXTRA_WIFI_PASSWORD = "android.app.extra.PROVISIONING_WIFI_PASSWORD"


class EnrollmentToken:
    def __init__(
        self,
        token_id: str,
        tenant_id: str,
        name: str,
        max_uses: int = 1,
        ttl_seconds: int = 86400,
        assigned_policy_id: str = "default",
        bound_hardware_id: Optional[str] = None,
    ):
        self.token_id = token_id
        self.tenant_id = tenant_id
        self.name = name
        self.max_uses = max_uses
        self.current_uses = 0
        self.created_at = time.time()
        self.expires_at = self.created_at + ttl_seconds
        self.assigned_policy_id = assigned_policy_id
        self.bound_hardware_id = bound_hardware_id
        self.revoked = False

    def is_valid(self, hardware_id: Optional[str] = None) -> bool:
        if self.revoked or time.time() > self.expires_at:
            return False
        if self.max_uses > 0 and self.current_uses >= self.max_uses:
            return False
        if self.bound_hardware_id and hardware_id and self.bound_hardware_id != hardware_id:
            return False
        return True

    def consume(self, hardware_id: Optional[str] = None) -> bool:
        if not self.is_valid(hardware_id):
            return False
        self.current_uses += 1
        return True

    def to_dict(self) -> Dict[str, Any]:
        return {
            "token_id": self.token_id,
            "tenant_id": self.tenant_id,
            "name": self.name,
            "max_uses": self.max_uses,
            "current_uses": self.current_uses,
            "created_at": self.created_at,
            "expires_at": self.expires_at,
            "assigned_policy_id": self.assigned_policy_id,
            "bound_hardware_id": self.bound_hardware_id,
            "revoked": self.revoked,
            "is_valid": self.is_valid(),
        }


class DpcProvisioningServer:
    """
    Central DPC enrollment and Zero-Touch provisioning engine for FocusDNS.
    """

    def __init__(
        self,
        package_name: str = "com.focusdns.app",
        receiver_class: str = "com.focusdns.app.FocusDeviceAdminReceiver",
        apk_signature_sha256: str = "4a24cd80388b818606eb02eb55b650c4035787207dd6551724d2968a07a9e163",
        default_server_url: str = "https://dns.focusguard.internal",
    ):
        self.package_name = package_name
        self.component_name = f"{package_name}/{receiver_class}"
        self.apk_signature_sha256 = apk_signature_sha256
        self.default_server_url = default_server_url

        self._tokens: Dict[str, EnrollmentToken] = {}
        self._enrolled_devices: Dict[str, Dict[str, Any]] = {}
        self._audit_log: List[Dict[str, Any]] = []
        self._setup_default_token()

    def _setup_default_token(self) -> None:
        default_tok = EnrollmentToken(
            token_id="tok_default_enterprise_provisioning",
            tenant_id="default_enterprise",
            name="Default Corporate Enrollment Token",
            max_uses=1000,
            ttl_seconds=86400 * 30,
        )
        self._tokens[default_tok.token_id] = default_tok

    def create_enrollment_token(
        self,
        tenant_id: str,
        name: str,
        max_uses: int = 1,
        ttl_seconds: int = 86400,
        policy_id: str = "default",
        bound_hardware_id: Optional[str] = None,
    ) -> EnrollmentToken:
        token_id = f"tok_{os.urandom(16).hex()}"
        tok = EnrollmentToken(
            token_id=token_id,
            tenant_id=tenant_id,
            name=name,
            max_uses=max_uses,
            ttl_seconds=ttl_seconds,
            assigned_policy_id=policy_id,
            bound_hardware_id=bound_hardware_id,
        )
        self._tokens[token_id] = tok
        return tok

    def revoke_token(self, token_id: str) -> bool:
        tok = self._tokens.get(token_id)
        if not tok:
            return False
        tok.revoked = True
        return True

    def get_token(self, token_id: str) -> Optional[EnrollmentToken]:
        return self._tokens.get(token_id)

    def generate_zero_touch_qr_payload(
        self,
        token_id: str,
        server_url: Optional[str] = None,
        wifi_ssid: Optional[str] = None,
        wifi_password: Optional[str] = None,
        enforce_strict_uninstall_lock: bool = False,
    ) -> Dict[str, Any]:
        """
        Generates standard Android Enterprise QR Code Provisioning JSON payload.
        """
        tok = self._tokens.get(token_id)
        tenant = tok.tenant_id if tok else "default_enterprise"
        s_url = server_url or self.default_server_url

        payload: Dict[str, Any] = {
            EXTRA_PACKAGE_NAME: self.package_name,
            EXTRA_COMPONENT_NAME: self.component_name,
            EXTRA_SIGNATURE_CHECKSUM: self.apk_signature_sha256,
            EXTRA_ADMIN_EXTRAS: {
                "server_url": s_url,
                "tenant_id": tenant,
                "enrollment_token": token_id,
                "enforce_strict_uninstall_lock": enforce_strict_uninstall_lock,
            },
            EXTRA_LEAVE_ALL_SYSTEM_APPS: True,
            EXTRA_SKIP_ENCRYPTION: False,
        }

        if wifi_ssid:
            payload[EXTRA_WIFI_SSID] = wifi_ssid
            payload[EXTRA_WIFI_SECURITY] = "WPA" if wifi_password else "NONE"
            if wifi_password:
                payload[EXTRA_WIFI_PASSWORD] = wifi_password

        return payload

    def process_enrollment(
        self,
        device_id: str,
        token_id: str,
        hardware_id: Optional[str] = None,
        device_model: str = "Android Device",
        os_version: str = "Android 14",
    ) -> Dict[str, Any]:
        """
        Consumes an enrollment token and registers device under DPC management.
        """
        tok = self._tokens.get(token_id)
        if not tok:
            return {
                "success": False,
                "error": "INVALID_ENROLLMENT_TOKEN",
                "device_id": device_id,
            }

        if not tok.consume(hardware_id):
            return {
                "success": False,
                "error": "TOKEN_EXPIRED_OR_CONSUMED",
                "device_id": device_id,
            }

        rec = {
            "device_id": device_id,
            "token_id": token_id,
            "tenant_id": tok.tenant_id,
            "policy_id": tok.assigned_policy_id,
            "hardware_id": hardware_id,
            "device_model": device_model,
            "os_version": os_version,
            "enrolled_at": time.time(),
            "status": "ENROLLED_DEVICE_OWNER",
        }
        self._enrolled_devices[device_id] = rec

        return {
            "success": True,
            "device_record": rec,
            "server_url": self.default_server_url,
            "policy_id": tok.assigned_policy_id,
        }

    def get_enrolled_devices(self, tenant_id: Optional[str] = None) -> List[Dict[str, Any]]:
        devs = list(self._enrolled_devices.values())
        if tenant_id:
            devs = [d for d in devs if d.get("tenant_id") == tenant_id]
        return devs

    def _record_audit_event(self, event_type: str, details: Dict[str, Any]) -> None:
        event = {
            "event_id": f"dpc_aud_{os.urandom(8).hex()}",
            "event_type": event_type,
            "timestamp": time.time(),
            "details": details,
        }
        self._audit_log.append(event)
        # Retain last 2000 events
        if len(self._audit_log) > 2000:
            self._audit_log.pop(0)

    def create_bulk_tokens(
        self,
        tenant_id: str,
        base_name: str,
        count: int,
        max_uses: int = 1,
        ttl_seconds: int = 86400 * 30,
        policy_id: str = "default",
    ) -> List[EnrollmentToken]:
        """Creates batch of unique enrollment tokens for enterprise bulk staging."""
        tokens = []
        for i in range(1, count + 1):
            tok = self.create_enrollment_token(
                tenant_id=tenant_id,
                name=f"{base_name} #{i:03d}",
                max_uses=max_uses,
                ttl_seconds=ttl_seconds,
                policy_id=policy_id,
            )
            tokens.append(tok)
            self._record_audit_event("TOKEN_ISSUED", {"token_id": tok.token_id, "tenant_id": tenant_id})
        return tokens

    def export_tokens_csv(self, tenant_id: Optional[str] = None) -> str:
        """Exports enrollment tokens as CSV string for mass MDM provisioning."""
        lines = ["token_id,tenant_id,name,max_uses,current_uses,is_valid,revoked,expires_at"]
        tokens = self._tokens.values()
        if tenant_id:
            tokens = [t for t in tokens if t.tenant_id == tenant_id]
        for t in sorted(tokens, key=lambda x: x.created_at):
            lines.append(
                f"{t.token_id},{t.tenant_id},\"{t.name}\",{t.max_uses},{t.current_uses},{t.is_valid()},{t.revoked},{int(t.expires_at)}"
            )
        return "\n".join(lines)

    def export_tokens_json(self, tenant_id: Optional[str] = None) -> List[Dict[str, Any]]:
        """Exports enrollment tokens as JSON dictionary list."""
        tokens = self._tokens.values()
        if tenant_id:
            tokens = [t for t in tokens if t.tenant_id == tenant_id]
        return [t.to_dict() for t in sorted(tokens, key=lambda x: x.created_at)]

    def get_audit_log(
        self, tenant_id: Optional[str] = None, limit: int = 100
    ) -> List[Dict[str, Any]]:
        logs = self._audit_log
        if tenant_id:
            logs = [l for l in logs if l.get("details", {}).get("tenant_id") == tenant_id]
        return list(reversed(logs[-limit:]))

    def get_fleet_provisioning_summary(self, tenant_id: Optional[str] = None) -> Dict[str, Any]:
        """Returns fleet provisioning posture and token consumption metrics."""
        devices = self.get_enrolled_devices(tenant_id)
        tokens = self._tokens.values()
        if tenant_id:
            tokens = [t for t in tokens if t.tenant_id == tenant_id]

        active_tokens = [t for t in tokens if t.is_valid()]
        consumed_tokens = [t for t in tokens if not t.is_valid() and not t.revoked]
        revoked_tokens = [t for t in tokens if t.revoked]

        return {
            "tenant_id": tenant_id or "all_tenants",
            "enrolled_device_count": len(devices),
            "total_tokens_generated": len(list(tokens)),
            "active_available_tokens": len(active_tokens),
            "consumed_tokens": len(consumed_tokens),
            "revoked_tokens": len(revoked_tokens),
            "timestamp": time.time(),
        }
