"""
FocusDNS Enterprise Engine - Multi-Tenancy, Big Data Columnar Analytics, Fleet Push & SIEM.

Commercial management plane providing:
  1. Ultra-Fast Columnar Analytics (DuckDB & FastColumnarStore memory fallback)
  2. Hierarchical Role-Based Access Control (RBAC) & Multi-Tenant Boundaries
  3. Real-Time WebSocket Fleet Push with Sub-50ms Policy Fanout
  4. Enterprise SIEM Integration (RFC 5424 Syslog, Splunk HEC, Datadog, Elastic)
  5. Multi-Tenant Relational Manager with Policy Inheritance & Strict Mode Guarantees
"""

__version__ = "7.0.0-enterprise"
__author__ = "FocusDNS Enterprise Core Team"

from server.enterprise.columnar_analytics import (
    ColumnarAnalyticsEngine,
    DnsQueryEvent,
    FastColumnarStore,
    get_columnar_engine,
)
from server.enterprise.rbac_engine import (
    RbacEngine,
    RoleTier,
    Permission,
    EnterpriseUser,
    AuditLogEntry,
    get_rbac_engine,
)
from server.enterprise.tenant_manager import (
    TenantManager,
    Organization,
    TenantUnit,
    DeviceFleet,
    TenantQuota,
    get_tenant_manager,
)
from server.enterprise.fleet_websocket_server import (
    FleetWebSocketServer,
    FleetClientConnection,
    PendingPushMessage,
    get_fleet_websocket_server,
)
from server.enterprise.siem_forwarder import (
    SiemForwarder,
    Rfc5424SyslogMessage,
    SiemConfig,
    SiemTransport,
    get_siem_forwarder,
)
from server.enterprise.api_enterprise_router import (
    EnterpriseApiDispatcher,
    get_enterprise_dispatcher,
)
from server.enterprise.compliance_exporter import (
    ComplianceExporter,
    ComplianceReport,
    ComplianceFramework,
)
from server.enterprise.fleet_policy_compiler import (
    FleetPolicyCompiler,
    CompiledFleetPolicy,
)
from server.enterprise.parquet_archiver import (
    ParquetArchiver,
)
from server.enterprise.audit_log_exporter import (
    AuditLogExporter,
)
from server.enterprise.device_heartbeat_agent import (
    DeviceHeartbeatAgent,
    DeviceAgentState,
)
from server.engine.enterprise_pipeline_hook import (
    EnterprisePipelineHook,
    get_enterprise_pipeline_hook,
)
from server.enterprise.clickhouse_analytics import (
    ClickHouseAnalyticsEngine,
    get_clickhouse_engine,
    TDigest,
    CountMinSketch,
)
from server.enterprise.scim_directory_sync import (
    ScimDirectorySyncEngine,
    get_scim_engine,
)
from server.enterprise.saml_oidc_authenticator import (
    SamlOidcAuthenticator,
    get_sso_authenticator,
    SamlIdentityProviderConfig,
    OidcProviderConfig,
)
from server.enterprise.classroom_orchestrator import (
    ClassroomOrchestrator,
    get_classroom_orchestrator,
    ClassroomFocusMode,
    ClassroomSession,
)
from server.enterprise.soar_playbook_engine import (
    SoarPlaybookEngine,
    get_soar_engine,
    SoarIncident,
    SoarTriggerType,
)
from server.enterprise.usage_metering import (
    UsageMeteringEngine,
    get_metering_engine,
)
from server.enterprise.siem_ingest_gateway import (
    SiemIngestGateway,
    SiemIngestAlert,
    SiemVendorType,
    get_siem_ingest_gateway,
)
from server.enterprise.threat_hunter import (
    ThreatHunter,
    ThreatHuntQuery,
    ThreatHuntResult,
    get_threat_hunter,
    calculate_shannon_entropy,
    is_dga_candidate,
)
from server.enterprise.policy_drift_auditor import (
    PolicyDriftAuditor,
    PolicyDriftRecord,
    TenantComplianceReport,
    DriftType,
    get_policy_drift_auditor,
)
from server.enterprise.pii_redactor import (
    PiiRedactor,
    get_pii_redactor,
)

__all__ = [
    "ColumnarAnalyticsEngine",
    "DnsQueryEvent",
    "FastColumnarStore",
    "get_columnar_engine",
    "RbacEngine",
    "RoleTier",
    "Permission",
    "EnterpriseUser",
    "AuditLogEntry",
    "get_rbac_engine",
    "TenantManager",
    "Organization",
    "TenantUnit",
    "DeviceFleet",
    "TenantQuota",
    "get_tenant_manager",
    "FleetWebSocketServer",
    "FleetClientConnection",
    "PendingPushMessage",
    "get_fleet_websocket_server",
    "SiemForwarder",
    "Rfc5424SyslogMessage",
    "SiemConfig",
    "SiemTransport",
    "get_siem_forwarder",
    "EnterpriseApiDispatcher",
    "get_enterprise_dispatcher",
    "ComplianceExporter",
    "ComplianceReport",
    "ComplianceFramework",
    "FleetPolicyCompiler",
    "CompiledFleetPolicy",
    "ParquetArchiver",
    "AuditLogExporter",
    "DeviceHeartbeatAgent",
    "DeviceAgentState",
    "EnterprisePipelineHook",
    "get_enterprise_pipeline_hook",
    "ClickHouseAnalyticsEngine",
    "get_clickhouse_engine",
    "TDigest",
    "CountMinSketch",
    "ScimDirectorySyncEngine",
    "get_scim_engine",
    "SamlOidcAuthenticator",
    "get_sso_authenticator",
    "SamlIdentityProviderConfig",
    "OidcProviderConfig",
    "ClassroomOrchestrator",
    "get_classroom_orchestrator",
    "ClassroomFocusMode",
    "ClassroomSession",
    "SoarPlaybookEngine",
    "get_soar_engine",
    "SoarIncident",
    "SoarTriggerType",
    "UsageMeteringEngine",
    "get_metering_engine",
    "SiemIngestGateway",
    "SiemIngestAlert",
    "SiemVendorType",
    "get_siem_ingest_gateway",
    "ThreatHunter",
    "ThreatHuntQuery",
    "ThreatHuntResult",
    "get_threat_hunter",
    "calculate_shannon_entropy",
    "is_dga_candidate",
    "PolicyDriftAuditor",
    "PolicyDriftRecord",
    "TenantComplianceReport",
    "DriftType",
    "get_policy_drift_auditor",
    "PiiRedactor",
    "get_pii_redactor",
]

