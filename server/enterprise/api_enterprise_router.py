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
from server.enterprise.classroom_orchestrator import (
    ClassroomOrchestrator,
    ClassroomFocusMode,
    get_classroom_orchestrator
)
from server.enterprise.soar_playbook_engine import (
    SoarPlaybookEngine,
    get_soar_engine
)
from server.enterprise.scim_directory_sync import (
    ScimDirectorySyncEngine,
    get_scim_engine
)
from server.enterprise.saml_oidc_authenticator import (
    SamlOidcAuthenticator,
    get_sso_authenticator
)
from server.enterprise.usage_metering import (
    UsageMeteringEngine,
    get_metering_engine
)
from server.enterprise.clickhouse_analytics import (
    ClickHouseAnalyticsEngine,
    get_clickhouse_engine
)
from server.enterprise.siem_ingest_gateway import (
    SiemIngestGateway,
    SiemIngestAlert,
    SiemVendorType,
    get_siem_ingest_gateway
)
from server.enterprise.threat_hunter import (
    ThreatHunter,
    ThreatHuntQuery,
    ThreatHuntResult,
    get_threat_hunter
)
from server.enterprise.policy_drift_auditor import (
    PolicyDriftAuditor,
    PolicyDriftRecord,
    get_policy_drift_auditor
)
from server.enterprise.pii_redactor import (
    PiiRedactor,
    get_pii_redactor
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
        siem: Optional[SiemForwarder] = None,
        classroom: Optional[ClassroomOrchestrator] = None,
        soar: Optional[SoarPlaybookEngine] = None,
        scim: Optional[ScimDirectorySyncEngine] = None,
        sso: Optional[SamlOidcAuthenticator] = None,
        metering: Optional[UsageMeteringEngine] = None,
        clickhouse: Optional[ClickHouseAnalyticsEngine] = None,
        siem_gateway: Optional[SiemIngestGateway] = None,
        threat_hunter: Optional[ThreatHunter] = None,
        drift_auditor: Optional[PolicyDriftAuditor] = None,
        pii_redactor: Optional[PiiRedactor] = None,
    ):
        self.rbac = rbac or get_rbac_engine()
        self.tenants = tenants or get_tenant_manager()
        self.analytics = analytics or get_columnar_engine()
        self.ws_hub = ws_hub or get_fleet_websocket_server()
        self.siem = siem or get_siem_forwarder()
        self.classroom = classroom or get_classroom_orchestrator()
        self.soar = soar or get_soar_engine()
        self.scim = scim or get_scim_engine()
        self.sso = sso or get_sso_authenticator()
        self.metering = metering or get_metering_engine()
        self.clickhouse = clickhouse or get_clickhouse_engine()
        self.siem_gateway = siem_gateway or get_siem_ingest_gateway()
        self.threat_hunter = threat_hunter or get_threat_hunter()
        self.drift_auditor = drift_auditor or get_policy_drift_auditor()
        self.pii_redactor = pii_redactor or get_pii_redactor()

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

        # 7. Classroom & Fleet Sessions
        if clean_path in ("/api/v1/enterprise/classroom/sessions", "/api/enterprise/classroom/sessions"):
            org_id = params.get("org_id", [""])[0] or None
            sessions = self.classroom.list_active_sessions(org_id)
            return 200, {"success": True, "sessions": sessions}

        if clean_path in ("/api/v1/enterprise/classroom/session", "/api/enterprise/classroom/session"):
            session_id = params.get("session_id", [""])[0]
            if not session_id:
                return 400, {"success": False, "error": "Missing parameter: 'session_id'"}
            session = self.classroom.get_session(session_id)
            if not session:
                return 404, {"success": False, "error": "Session not found"}
            return 200, {"success": True, "session": session.to_dict()}

        # 8. SOAR Incident Response & Telemetry
        if clean_path in ("/api/v1/enterprise/soar/incidents", "/api/enterprise/soar/incidents"):
            limit = int(params.get("limit", [50])[0])
            incidents = self.soar.list_incidents(limit)
            return 200, {"success": True, "incidents": incidents}

        if clean_path in ("/api/v1/enterprise/soar/incident", "/api/enterprise/soar/incident"):
            incident_id = params.get("incident_id", [""])[0]
            if not incident_id:
                return 400, {"success": False, "error": "Missing parameter: 'incident_id'"}
            inc = self.soar.get_incident(incident_id)
            if not inc:
                return 404, {"success": False, "error": "Incident not found"}
            return 200, {"success": True, "incident": inc}

        if clean_path in ("/api/v1/enterprise/soar/metrics", "/api/enterprise/soar/metrics"):
            return 200, {"success": True, "metrics": self.soar.get_metrics()}

        # 9. SCIM 2.0 Directory Protocol & Logs
        if clean_path in ("/api/v1/enterprise/scim/v2/ServiceProviderConfig", "/scim/v2/ServiceProviderConfig"):
            return 200, self.scim.get_service_provider_config()

        if clean_path in ("/api/v1/enterprise/scim/v2/Users", "/scim/v2/Users"):
            start_idx = int(params.get("startIndex", [1])[0])
            count = int(params.get("count", [50])[0])
            return 200, self.scim.list_users(start_idx, count)

        if clean_path in ("/api/v1/enterprise/scim/v2/Groups", "/scim/v2/Groups"):
            start_idx = int(params.get("startIndex", [1])[0])
            count = int(params.get("count", [50])[0])
            return 200, self.scim.list_groups(start_idx, count)

        if clean_path in ("/api/v1/enterprise/scim/logs", "/api/enterprise/scim/logs"):
            limit = int(params.get("limit", [50])[0])
            logs = self.scim.get_provisioning_logs(limit)
            return 200, {"success": True, "logs": logs}

        # 10. Commercial Metering & Invoicing
        if clean_path in ("/api/v1/enterprise/metering/invoice", "/api/enterprise/metering/invoice"):
            org_id = params.get("org_id", [""])[0]
            if not org_id:
                return 400, {"success": False, "error": "Missing parameter: 'org_id'"}
            cycle = params.get("billing_cycle", [""])[0] or None
            try:
                inv = self.metering.generate_signed_invoice(org_id, cycle)
                return 200, {"success": True, "invoice": inv}
            except KeyError as e:
                return 404, {"success": False, "error": str(e)}

        if clean_path in ("/api/v1/enterprise/metering/usage", "/api/enterprise/metering/usage"):
            org_id = params.get("org_id", [""])[0]
            if not org_id:
                return 400, {"success": False, "error": "Missing parameter: 'org_id'"}
            usage = self.metering.get_current_usage(org_id)
            return 200, {"success": True, "usage": usage}

        # 11. ClickHouse Analytics Stats
        if clean_path in ("/api/v1/enterprise/clickhouse/stats", "/api/enterprise/clickhouse/stats"):
            return 200, {"success": True, "stats": self.clickhouse.get_metrics()}

        # 12. Inbound SIEM Ingest Alerts & Telemetry
        if clean_path in ("/api/v1/enterprise/siem/alerts", "/api/enterprise/siem/alerts"):
            limit = int(params.get("limit", [50])[0])
            tenant_id = params.get("tenant_id", [""])[0] or None
            alerts = self.siem_gateway.get_recent_alerts(limit=limit, tenant_id=tenant_id)
            return 200, {"success": True, "count": len(alerts), "alerts": alerts}

        if clean_path in ("/api/v1/enterprise/siem/telemetry", "/api/enterprise/siem/telemetry"):
            return 200, {"success": True, "telemetry": self.siem_gateway.get_telemetry()}

        # 13. Threat Hunter Device Timeline
        if clean_path in ("/api/v1/enterprise/threat-hunter/timeline", "/api/enterprise/threat-hunter/timeline"):
            tenant_id = params.get("tenant_id", [""])[0]
            device_id = params.get("device_id", [""])[0]
            if not tenant_id or not device_id:
                return 400, {"success": False, "error": "Missing required 'tenant_id' or 'device_id'"}
            window_min = int(params.get("window_minutes", [30])[0])
            timeline = self.threat_hunter.reconstruct_device_timeline(
                tenant_id=tenant_id,
                device_id=device_id,
                window_minutes=window_min
            )
            return 200, {"success": True, "timeline": timeline}

        # 14. Fleet Policy Drift & Compliance
        if clean_path in ("/api/v1/enterprise/compliance/drift", "/api/enterprise/compliance/drift"):
            tenant_id = params.get("tenant_id", [""])[0]
            if not tenant_id:
                return 400, {"success": False, "error": "Missing required 'tenant_id'"}
            report = self.drift_auditor.generate_compliance_report(tenant_id)
            return 200, {"success": True, "report": report.to_dict()}

        # 15. Billing Summary & Invoices
        if clean_path in ("/api/v1/enterprise/billing/summary", "/api/enterprise/billing/summary"):
            org_id = params.get("org_id", [""])[0]
            if not org_id:
                return 400, {"success": False, "error": "Missing parameter: 'org_id'"}
            usage = self.metering.get_current_usage(org_id)
            inv = self.metering.generate_signed_invoice(org_id)
            return 200, {
                "success": True,
                "org_id": org_id,
                "usage": usage,
                "current_invoice": inv
            }

        # 16. PII Redacted Query Analytics View
        if clean_path in ("/api/v1/enterprise/analytics/redacted", "/api/enterprise/analytics/redacted"):
            tenant_id = params.get("tenant_id", [""])[0]
            if not tenant_id:
                return 400, {"success": False, "error": "Missing parameter: 'tenant_id'"}
            role_str = params.get("role", ["COMPLIANCE_AUDITOR"])[0]
            limit = int(params.get("limit", [50])[0])
            role = RoleTier.from_str(role_str)
            raw_events = self.threat_hunter._fetch_columnar_events(
                tenant_id=tenant_id,
                start_us=0,
                end_us=int(time.time() * 1_000_000),
                limit=limit
            )
            redacted = self.pii_redactor.redact_dataset(
                raw_events,
                viewer_role=role,
                tenant_id=tenant_id
            )
            return 200, {"success": True, "count": len(redacted), "events": redacted}

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

        # 8. Classroom Session Management
        if clean_path in ("/api/v1/enterprise/classroom/start", "/api/enterprise/classroom/start"):
            org_id = payload.get("org_id", "")
            unit_id = payload.get("unit_id", "")
            fleet_id = payload.get("fleet_id", "")
            classroom_name = payload.get("classroom_name", "Focus Classroom")
            duration_sec = int(payload.get("duration_seconds", 2700))
            mode_str = payload.get("mode", "NORMAL_PROTECTION")
            try:
                mode = ClassroomFocusMode(mode_str)
            except ValueError:
                mode = ClassroomFocusMode.NORMAL_PROTECTION

            allowed = payload.get("allowed_exam_domains")
            allowed_set = set(allowed) if allowed else None

            session = self.classroom.start_session(
                org_id=org_id,
                unit_id=unit_id,
                fleet_id=fleet_id,
                classroom_name=classroom_name,
                teacher_user_id=payload.get("teacher_user_id", "teacher_admin"),
                mode=mode,
                duration_seconds=duration_sec,
                allowed_exam_domains=allowed_set,
            )
            return 200, {"success": True, "session": session.to_dict()}

        if clean_path in ("/api/v1/enterprise/classroom/end", "/api/enterprise/classroom/end"):
            session_id = payload.get("session_id", "")
            if not session_id:
                return 400, {"success": False, "error": "Missing 'session_id'"}
            session = self.classroom.end_session(session_id)
            if not session:
                return 404, {"success": False, "error": "Session not found"}
            return 200, {"success": True, "session": session.to_dict()}

        if clean_path in ("/api/v1/enterprise/classroom/mode", "/api/enterprise/classroom/mode"):
            session_id = payload.get("session_id", "")
            mode_str = payload.get("mode", "NORMAL_PROTECTION")
            try:
                mode = ClassroomFocusMode(mode_str)
            except ValueError:
                return 400, {"success": False, "error": f"Invalid mode: {mode_str}"}

            ok = self.classroom.set_focus_mode(session_id, mode)
            if not ok:
                return 404, {"success": False, "error": "Session not active or not found"}
            return 200, {"success": True, "mode": mode.value}

        # Conditional Whitelisting Law: Classroom Whitelist Mutation Enforcement
        if clean_path in ("/api/v1/enterprise/classroom/whitelist", "/api/enterprise/classroom/whitelist"):
            session_id = payload.get("session_id", "")
            domain = payload.get("domain", "").strip()
            if not session_id or not domain:
                return 400, {"success": False, "error": "Missing 'session_id' or 'domain'"}

            try:
                self.classroom.request_whitelist_domain(session_id, domain)
                return 200, {"success": True, "domain": domain}
            except PermissionError as e:
                # STRICT MODE BARRIER: Return HTTP 403 with ERROR_ACCESS_DENIED (5)
                return 403, {
                    "success": False,
                    "error": str(e),
                    "code": "ERROR_ACCESS_DENIED",
                    "errno": 5
                }

        if clean_path in ("/api/v1/enterprise/classroom/record-query", "/api/enterprise/classroom/record-query"):
            device_id = payload.get("device_id", "")
            domain = payload.get("domain", "")
            action = payload.get("action", "ALLOWED")
            allowed, reason = self.classroom.record_student_query(device_id, domain, action)
            return 200, {"allowed": allowed, "reason": reason}

        # 9. SOAR Playbook Execution & Incident Control
        if clean_path in ("/api/v1/enterprise/soar/trigger", "/api/enterprise/soar/trigger"):
            tenant_id = payload.get("tenant_id", "default")
            device_id = payload.get("device_id", "")
            domain = payload.get("domain", "")
            threat_type = payload.get("threat_type", "PHISHING")
            risk_score = float(payload.get("risk_score", 90.0))
            metadata = payload.get("metadata", {})

            inc = self.soar.evaluate_threat_event(
                tenant_id=tenant_id,
                device_id=device_id,
                domain=domain,
                threat_type=threat_type,
                risk_score=risk_score,
                metadata=metadata
            )
            if not inc:
                return 200, {"success": False, "message": "No playbook triggered for threat event."}
            return 200, {"success": True, "incident": inc.to_dict()}

        if clean_path in ("/api/v1/enterprise/soar/lift-quarantine", "/api/enterprise/soar/lift-quarantine"):
            device_id = payload.get("device_id", "")
            if not device_id:
                return 400, {"success": False, "error": "Missing 'device_id'"}
            ok = self.soar.lift_quarantine(device_id)
            return 200 if ok else 404, {"success": ok, "device_id": device_id}

        # 10. SCIM 2.0 User & Group Provisioning (RFC 7644)
        if clean_path in ("/api/v1/enterprise/scim/v2/Users", "/scim/v2/Users"):
            status_code, res = self.scim.create_user(payload)
            return status_code, res

        if clean_path in ("/api/v1/enterprise/scim/v2/Groups", "/scim/v2/Groups"):
            status_code, res = self.scim.create_group(payload)
            return status_code, res

        # 11. Usage Metering Billable Record
        if clean_path in ("/api/v1/enterprise/metering/record", "/api/enterprise/metering/record"):
            org_id = payload.get("org_id", "")
            if not org_id:
                return 400, {"success": False, "error": "Missing 'org_id'"}
            query_count = int(payload.get("queries", 1))
            device_id = payload.get("device_id")
            instant_qps = float(payload.get("instant_qps", 0.0))
            storage_bytes = int(payload.get("storage_bytes", 0))
            siem_bytes = int(payload.get("siem_bytes", 0))

            warnings = self.metering.record_query_usage(
                org_id=org_id,
                query_count=query_count,
                device_id=device_id,
                instant_qps=instant_qps,
                storage_bytes=storage_bytes,
                siem_bytes=siem_bytes
            )
            return 200, {"success": True, "quota_warnings": warnings}

        # 12. Inbound SIEM Webhooks (Splunk, Datadog, Elastic)
        if clean_path in ("/api/v1/enterprise/siem/webhook/splunk", "/api/enterprise/siem/webhook/splunk"):
            ok, msg, alert = self.siem_gateway.ingest_splunk_alert(payload, headers=headers)
            status = 200 if ok else 401
            return status, {"success": ok, "message": msg, "alert": alert.to_dict() if alert else None}

        if clean_path in ("/api/v1/enterprise/siem/webhook/datadog", "/api/enterprise/siem/webhook/datadog"):
            ok, msg, alert = self.siem_gateway.ingest_datadog_alert(payload, headers=headers)
            status = 200 if ok else 401
            return status, {"success": ok, "message": msg, "alert": alert.to_dict() if alert else None}

        if clean_path in ("/api/v1/enterprise/siem/webhook/elastic", "/api/enterprise/siem/webhook/elastic"):
            ok, msg, alert = self.siem_gateway.ingest_elastic_alert(payload, headers=headers)
            status = 200 if ok else 401
            return status, {"success": ok, "message": msg, "alert": alert.to_dict() if alert else None}

        # 13. Threat Hunter Retrospective & IOC Scanning
        if clean_path in ("/api/v1/enterprise/threat-hunter/query", "/api/enterprise/threat-hunter/query"):
            tenant_id = payload.get("tenant_id", "")
            if not tenant_id:
                return 400, {"success": False, "error": "Missing 'tenant_id'"}
            th_query = ThreatHuntQuery(
                tenant_id=tenant_id,
                start_time_us=payload.get("start_time_us"),
                end_time_us=payload.get("end_time_us"),
                sub_tenant_id=payload.get("sub_tenant_id"),
                device_id=payload.get("device_id"),
                cidr_subnet=payload.get("cidr_subnet"),
                domain_pattern=payload.get("domain_pattern"),
                min_entropy=payload.get("min_entropy"),
                threat_type=payload.get("threat_type"),
                action=payload.get("action"),
                limit=int(payload.get("limit", 200))
            )
            result = self.threat_hunter.execute_hunt(th_query)
            return 200, {"success": True, "result": result.to_dict()}

        if clean_path in ("/api/v1/enterprise/threat-hunter/ioc-scan", "/api/enterprise/threat-hunter/ioc-scan"):
            tenant_id = payload.get("tenant_id", "")
            iocs = payload.get("iocs", [])
            if not tenant_id or not isinstance(iocs, list):
                return 400, {"success": False, "error": "Missing 'tenant_id' or 'iocs' list"}
            lookback = int(payload.get("lookback_seconds", 86400))
            hits = self.threat_hunter.scan_ioc_batch(tenant_id, iocs, lookback_seconds=lookback)
            return 200, {"success": True, "hits_count": len(hits), "hits": hits}

        # 14. Policy Drift Remediation Push
        if clean_path in ("/api/v1/enterprise/compliance/drift/remediate", "/api/enterprise/compliance/drift/remediate"):
            device_id = payload.get("device_id", "")
            record_id = payload.get("record_id", "")
            target_record = None
            if record_id and record_id in self.drift_auditor._drift_records:
                target_record = self.drift_auditor._drift_records[record_id]
            elif device_id:
                for r in self.drift_auditor._drift_records.values():
                    if r.device_id == device_id and not r.remediated:
                        target_record = r
                        break

            if not target_record:
                return 404, {"success": False, "error": f"No active drift record found for target"}

            ok = self.drift_auditor.remediate_device(target_record)
            return 200 if ok else 500, {"success": ok, "record": target_record.to_dict()}

        # 15. Invoice Signature Verification
        if clean_path in ("/api/v1/enterprise/billing/invoices/verify", "/api/enterprise/billing/invoices/verify"):
            invoice = payload.get("invoice")
            if not invoice or not isinstance(invoice, dict):
                return 400, {"success": False, "error": "Missing 'invoice' object"}
            is_valid = self.metering.verify_invoice_signature(invoice)
            return 200, {
                "success": is_valid,
                "verified": is_valid,
                "certificate_status": "VALID_HMAC_SHA256" if is_valid else "TAMPERING_DETECTED"
            }

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
