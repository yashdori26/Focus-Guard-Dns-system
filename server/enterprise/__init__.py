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
]
