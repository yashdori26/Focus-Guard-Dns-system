"""
FocusDNS Enterprise Engine - REST API Router & Control Plane Dispatcher.

Handles multi-tenant HTTP requests for `/api/v1/enterprise/*`:
  1. Organizational & Sub-Tenant CRUD (/api/v1/enterprise/tenants)
  2. Fleet Management & Focus Locks (/api/v1/enterprise/fleets/*)
  3. Columnar Big Data Analytics (/api/v1/enterprise/analytics/*)
  4. Real-Time WebSocket Fleet Push Trigger (/api/v1/enterprise/fleet/push)
  5. Cryptographic RBAC & Tamper-Evident Audit Trails (/api/v1/enterprise/rbac/*)
  6. Enterprise SIEM Configuration & Probe Verification (/api/v1/enterprise/siem/*)

Strictly Enforces:
  - Inviolable Conditional Whitelisting Law: Whitelist mutations during locked focus
    return HTTP 403 Forbidden with ERROR_ACCESS_DENIED (5).
"""

import json
import logging
import threading
import time
from typing import Dict, List, Set, Optional, Tuple, Any

from server.enterprise.columnar_analytics import (
    ColumnarAnalyticsEngine,
    get_columnar_engine,
    DnsQueryEvent
)
from server.enterprise.rbac_engine import (
    RbacEngine,
    RoleTier,
    Permission,
    EnterpriseUser,
    get_rbac_engine
)
from server.enterprise.tenant_manager import (
    TenantManager,
    Organization,
    TenantUnit,
    DeviceFleet,
    TenantQuota,
    get_tenant_manager
)
from server.enterprise.fleet_websocket_server import (
    FleetWebSocketServer,
    get_fleet_websocket_server
)
from server.enterprise.siem_forwarder import (
    SiemForwarder,
    SiemConfig,
    SiemTransport,
    get_siem_forwarder
)

logger = logging.getLogger("FocusDNS.Enterprise.ApiRouter")


class EnterpriseApiDispatcher:
    """
    Enterprise API Router dispatching GET and POST requests for /api/v1/enterprise/*.
    Integrates all enterprise multi-tenancy subsystems.
    """

    def __init__(
        self,
        rbac: Optional[RbacEngine] = None,
        tenants: Optional[TenantManager] = None,
        analytics: Optional[ColumnarAnalyticsEngine] = None,
        ws_hub: Optional[FleetWebSocketServer] = None,
        siem: Optional[SiemForwarder] = None
    ):
        self.rbac = rbac or get_rbac_engine()
        self.tenants = tenants or get_tenant_manager()
        self.analytics = analytics or get_columnar_engine()
        self.ws_hub = ws_hub or get_fleet_websocket_server()
        self.siem = siem or get_siem_forwarder()

    def _extract_authenticated_user(self, headers: Dict[str, str]) -> Optional[EnterpriseUser]:
        auth_header = headers.get("Authorization", headers.get("authorization", ""))
        if not auth_header:
            # Check X-Api-Token
            token = headers.get("X-Api-Token", headers.get("x-api-token", ""))
        else:
            parts = auth_header.split(" ", 1)
            token = parts[1] if len(parts) == 2 else parts[0]

        if not token:
            return None
        return self.rbac.verify_session_token(token)

    def handle_get(
        self,
        path: str,
        params: Dict[str, List[str]],
        headers: Optional[Dict[str, str]] = None
    ) -> Optional[Tuple[int, Dict[str, Any]]]:
        clean_path = path.rstrip("/")
        headers = headers or {}

        # 1. Health & Version Info
        if clean_path in ("/api/v1/enterprise/info", "/api/enterprise/info"):
            return 200, {
                "success": True,
                "version": "7.0.0-enterprise",
                "subsystems": {
                    "columnar_backend": self.analytics.backend_type,
                    "records_indexed": self.analytics.total_records(),
                    "active_ws_clients": self.ws_hub.get_online_device_count(),
                    "siem_enabled": self.siem.config.enabled
                }
            }

        # 2. Audit Trail & Hash Verification (Compliance Auditor / Admins)
        if clean_path in ("/api/v1/enterprise/rbac/audit-trail", "/api/enterprise/rbac/audit-trail"):
            tenant_id = params.get("tenant_id", [""])[0] or None
            limit = int(params.get("limit", [100])[0])
            trail = self.rbac.get_audit_trail(tenant_id=tenant_id, limit=limit)
            return 200, {"success": True, "count": len(trail), "audit_trail": trail}

        if clean_path in ("/api/v1/enterprise/rbac/audit-verify", "/api/enterprise/rbac/audit-verify"):
            is_valid, error = self.rbac.verify_audit_chain()
            return 200, {
                "success": is_valid,
                "chain_valid": is_valid,
                "status": "UNBROKEN_CRYPTOGRAPHIC_CHAIN" if is_valid else "TAMPERING_DETECTED",
                "error": error
            }

        # 3. Tenants & Units Listing
        if clean_path in ("/api/v1/enterprise/tenants", "/api/enterprise/tenants"):
            org_id = params.get("org_id", [""])[0]
            if org_id:
                org = self.tenants.get_organization(org_id)
                if not org:
                    return 404, {"success": False, "error": f"Organization '{org_id}' not found"}
                units = self.tenants.list_tenant_units(org_id)
                return 200, {
                    "success": True,
                    "organization": org.to_dict(),
                    "units": [u.to_dict() for u in units]
                }
            return 400, {"success": False, "error": "Missing required query parameter: 'org_id'"}

        # 4. Fleet Status & Devices
        if clean_path in ("/api/v1/enterprise/fleets", "/api/enterprise/fleets"):
            fleet_id = params.get("fleet_id", [""])[0]
            if not fleet_id:
                return 400, {"success": False, "error": "Missing required query parameter: 'fleet_id'"}
            fleet = self.tenants.get_device_fleet(fleet_id)
            if not fleet:
                return 404, {"success": False, "error": f"Fleet '{fleet_id}' not found"}
            return 200, {"success": True, "fleet": fleet.to_dict()}

        if clean_path in ("/api/v1/enterprise/fleet/devices", "/api/enterprise/fleet/devices"):
            device_id = params.get("device_id", [""])[0]
            if device_id:
                status = self.ws_hub.get_device_status(device_id)
                if not status:
                    return 404, {"success": False, "error": f"Device '{device_id}' offline or not found"}
                return 200, {"success": True, "device": status}

            org_id = params.get("org_id", [""])[0] or None
            online_count = self.ws_hub.get_online_device_count(org_id)
            return 200, {"success": True, "online_devices_count": online_count}

        # 5. Columnar Big Data Analytics
        if clean_path in ("/api/v1/enterprise/analytics/timeseries", "/api/enterprise/analytics/timeseries"):
            tenant_id = params.get("tenant_id", [""])[0]
            if not tenant_id:
                return 400, {"success": False, "error": "Missing parameter: 'tenant_id'"}

            now_us = int(time.time() * 1_000_000)
            start_us = int(params.get("start_us", [now_us - 86400 * 1_000_000])[0])
            end_us = int(params.get("end_us", [now_us])[0])
            bucket_sec = int(params.get("bucket_seconds", [60])[0])
            sub_unit = params.get("sub_tenant_id", [""])[0] or None

            ts = self.analytics.get_timeseries(tenant_id, start_us, end_us, bucket_sec, sub_unit)
            return 200, {"success": True, "count": len(ts), "timeseries": ts}

        if clean_path in ("/api/v1/enterprise/analytics/top-domains", "/api/enterprise/analytics/top-domains"):
            tenant_id = params.get("tenant_id", [""])[0]
            if not tenant_id:
                return 400, {"success": False, "error": "Missing parameter: 'tenant_id'"}

            now_us = int(time.time() * 1_000_000)
            start_us = int(params.get("start_us", [now_us - 86400 * 1_000_000])[0])
            end_us = int(params.get("end_us", [now_us])[0])
            limit = int(params.get("limit", [20])[0])
            action_filter = params.get("action", [""])[0] or None
            sub_unit = params.get("sub_tenant_id", [""])[0] or None

            top = self.analytics.get_top_domains(tenant_id, start_us, end_us, limit, action_filter, sub_unit)
            return 200, {"success": True, "count": len(top), "top_domains": top}

        if clean_path in ("/api/v1/enterprise/analytics/threat-matrix", "/api/enterprise/analytics/threat-matrix"):
            tenant_id = params.get("tenant_id", [""])[0]
            if not tenant_id:
                return 400, {"success": False, "error": "Missing parameter: 'tenant_id'"}

            now_us = int(time.time() * 1_000_000)
            start_us = int(params.get("start_us", [now_us - 86400 * 1_000_000])[0])
            end_us = int(params.get("end_us", [now_us])[0])
            sub_unit = params.get("sub_tenant_id", [""])[0] or None

            matrix = self.analytics.get_threat_matrix(tenant_id, start_us, end_us, sub_unit)
            return 200, {"success": True, "threat_matrix": matrix}

        if clean_path in ("/api/v1/enterprise/analytics/quantiles", "/api/enterprise/analytics/quantiles"):
            tenant_id = params.get("tenant_id", [""])[0]
            if not tenant_id:
                return 400, {"success": False, "error": "Missing parameter: 'tenant_id'"}

            now_us = int(time.time() * 1_000_000)
            start_us = int(params.get("start_us", [now_us - 86400 * 1_000_000])[0])
            end_us = int(params.get("end_us", [now_us])[0])
            sub_unit = params.get("sub_tenant_id", [""])[0] or None

            lat = self.analytics.get_latency_quantiles(tenant_id, start_us, end_us, sub_unit)
            return 200, {"success": True, "latency_quantiles": lat}

        # 6. SIEM Config
        if clean_path in ("/api/v1/enterprise/siem/config", "/api/enterprise/siem/config"):
            return 200, {"success": True, "siem_config": self.siem.config.to_dict()}

        return None

    def handle_post(
        self,
        path: str,
        payload: Dict[str, Any],
        headers: Optional[Dict[str, str]] = None
    ) -> Optional[Tuple[int, Dict[str, Any]]]:
        clean_path = path.rstrip("/")
        headers = headers or {}

        # 1. User Authentication (Login)
        if clean_path in ("/api/v1/enterprise/auth/login", "/api/enterprise/auth/login"):
            username = payload.get("username", "")
            password = payload.get("password", "")
            res = self.rbac.authenticate(username, password)
            if not res:
                return 401, {"success": False, "error": "Invalid username or password"}
            user, token = res
            return 200, {
                "success": True,
                "token": token,
                "user": user.to_dict()
            }

        # 2. Organization Provisioning
        if clean_path in ("/api/v1/enterprise/tenants", "/api/enterprise/tenants"):
            name = payload.get("name", "").strip()
            domain = payload.get("domain", "").strip()
            if not name or not domain:
                return 400, {"success": False, "error": "Missing required fields: 'name', 'domain'"}

            tier = payload.get("plan_tier", "ENTERPRISE")
            max_dev = int(payload.get("max_devices", 500))
            quota = TenantQuota(max_devices=max_dev)
            org = self.tenants.create_organization(name=name, domain=domain, plan_tier=tier, quota=quota)
            return 201, {"success": True, "organization": org.to_dict()}

        # 3. Tenant Unit Creation
        if clean_path in ("/api/v1/enterprise/units", "/api/enterprise/units"):
            org_id = payload.get("org_id", "")
            name = payload.get("name", "")
            unit_type = payload.get("unit_type", "DEPARTMENT")
            if not org_id or not name:
                return 400, {"success": False, "error": "Missing 'org_id' or 'name'"}

            try:
                unit = self.tenants.create_tenant_unit(org_id=org_id, name=name, unit_type=unit_type)
                return 201, {"success": True, "unit": unit.to_dict()}
            except ValueError as e:
                return 400, {"success": False, "error": str(e)}

        # 4. Fleet Provisioning & Locks
        if clean_path in ("/api/v1/enterprise/fleets", "/api/enterprise/fleets"):
            org_id = payload.get("org_id", "")
            unit_id = payload.get("unit_id", "")
            name = payload.get("name", "")
            platform = payload.get("platform", "ALL")
            if not org_id or not unit_id or not name:
                return 400, {"success": False, "error": "Missing 'org_id', 'unit_id', or 'name'"}

            fleet = self.tenants.create_device_fleet(org_id, unit_id, name, platform)
            return 201, {"success": True, "fleet": fleet.to_dict()}

        if clean_path in ("/api/v1/enterprise/fleets/lock", "/api/enterprise/fleets/lock"):
            fleet_id = payload.get("fleet_id", "")
            duration = int(payload.get("duration_seconds", 3600))
            if not fleet_id:
                return 400, {"success": False, "error": "Missing 'fleet_id'"}

            try:
                fleet = self.tenants.lock_fleet(fleet_id, duration)
                # Broadcast lock event via WebSocket
                self.ws_hub.broadcast_to_fleet(fleet_id, {
                    "action": "LOCK_SESSION",
                    "duration_seconds": duration,
                    "locked_until": fleet.locked_until
                })
                return 200, {"success": True, "fleet": fleet.to_dict()}
            except ValueError as e:
                return 404, {"success": False, "error": str(e)}

        if clean_path in ("/api/v1/enterprise/fleets/unlock", "/api/enterprise/fleets/unlock"):
            fleet_id = payload.get("fleet_id", "")
            if not fleet_id:
                return 400, {"success": False, "error": "Missing 'fleet_id'"}

            try:
                fleet = self.tenants.unlock_fleet(fleet_id)
                self.ws_hub.broadcast_to_fleet(fleet_id, {"action": "UNLOCK_SESSION"})
                return 200, {"success": True, "fleet": fleet.to_dict()}
            except ValueError as e:
                return 404, {"success": False, "error": str(e)}

        # 5. Conditional Whitelisting Law Enforcement: /fleets/whitelist
        if clean_path in ("/api/v1/enterprise/fleets/whitelist", "/api/enterprise/fleets/whitelist"):
            fleet_id = payload.get("fleet_id", "")
            domain = payload.get("domain", "").strip()
            if not fleet_id or not domain:
                return 400, {"success": False, "error": "Missing 'fleet_id' or 'domain'"}

            try:
                self.tenants.modify_fleet_whitelist(fleet_id, domain)
                return 200, {
                    "success": True,
                    "message": f"Domain '{domain}' successfully whitelisted for fleet '{fleet_id}'."
                }
            except PermissionError as e:
                # STRICT MODE BARRIER: Strictly HTTP 403 Forbidden
                return 403, {
                    "success": False,
                    "error": str(e),
                    "code": "ERROR_ACCESS_DENIED",
                    "errno": 5
                }
            except ValueError as e:
                return 404, {"success": False, "error": str(e)}

        # 6. Real-Time Fleet WebSocket Push
        if clean_path in ("/api/v1/enterprise/fleet/push", "/api/enterprise/fleet/push"):
            target_type = payload.get("target_type", "FLEET").upper()
            target_id = payload.get("target_id", "")
            message_payload = payload.get("message", {})

            if not target_id or not message_payload:
                return 400, {"success": False, "error": "Missing 'target_id' or 'message'"}

            count = 0
            if target_type == "FLEET":
                count = self.ws_hub.broadcast_to_fleet(target_id, message_payload)
            elif target_type == "UNIT":
                count = self.ws_hub.broadcast_to_unit(target_id, message_payload)
            elif target_type == "ORG":
                count = self.ws_hub.broadcast_to_org(target_id, message_payload)
            elif target_type == "DEVICE":
                msg_id = self.ws_hub.send_to_device(target_id, message_payload)
                count = 1 if msg_id else 0

            return 200, {
                "success": True,
                "dispatched_count": count,
                "target_type": target_type,
                "target_id": target_id
            }

        # 7. SIEM Configuration & Connection Probe
        if clean_path in ("/api/v1/enterprise/siem/config", "/api/enterprise/siem/config"):
            transport_str = payload.get("transport", "UDP").upper()
            host = payload.get("host", "127.0.0.1")
            port = int(payload.get("port", 514))
            api_token = payload.get("api_token", "")
            enabled = bool(payload.get("enabled", True))

            try:
                new_cfg = SiemConfig(
                    enabled=enabled,
                    transport=SiemTransport(transport_str),
                    host=host,
                    port=port,
                    api_token=api_token
                )
                self.siem.update_config(new_cfg)
                return 200, {"success": True, "siem_config": new_cfg.to_dict()}
            except ValueError as e:
                return 400, {"success": False, "error": f"Invalid transport: {e}"}

        if clean_path in ("/api/v1/enterprise/siem/test", "/api/enterprise/siem/test"):
            success, msg = self.siem.test_connection()
            return 200 if success else 502, {"success": success, "message": msg}

        return None


# Global Singleton
_global_enterprise_dispatcher: Optional[EnterpriseApiDispatcher] = None
_dispatcher_lock = threading.Lock()


def get_enterprise_dispatcher() -> EnterpriseApiDispatcher:
    global _global_enterprise_dispatcher
    with _dispatcher_lock:
        if _global_enterprise_dispatcher is None:
            _global_enterprise_dispatcher = EnterpriseApiDispatcher()
        return _global_enterprise_dispatcher
