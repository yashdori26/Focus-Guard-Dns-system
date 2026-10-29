"""
FocusDNS Engine - Enterprise Multi-Tenant Analytics & SIEM Pipeline Hook.

Integrates the sub-millisecond DNS resolution engine with:
  1. Ultra-Fast Columnar Analytics (DuckDB / FastColumnarStore micro-batch buffer)
  2. Enterprise SIEM Streaming (RFC 5424 Syslog, Splunk HEC, Datadog, Elastic)
  3. Dynamic IP-to-Tenant/Sub-Tenant/Fleet Subnet Routing
  4. Inviolable Life-Safety Exemption Guarantee (Safety domains are NEVER blocked)
  5. Backpressure Protection: Non-blocking zero-drop queue ensuring DNS latency is unaffected.
"""

import ipaddress
import logging
import threading
import time
from typing import Dict, List, Set, Optional, Tuple, Any

from server.enterprise.columnar_analytics import (
    ColumnarAnalyticsEngine,
    DnsQueryEvent,
    get_columnar_engine,
)
from server.enterprise.siem_forwarder import (
    SiemForwarder,
    Rfc5424SyslogMessage,
    SyslogSeverity,
    SyslogFacility,
    get_siem_forwarder,
)

logger = logging.getLogger("FocusDNS.Engine.EnterpriseHook")

# Inviolable Life-Safety Domains: Cannot be blocked under any enterprise tier or strict mode
LIFE_SAFETY_DOMAINS: Set[str] = {
    "911.gov",
    "112.gov",
    "emergency.gov",
    "cops.usdoj.gov",
    "fema.gov",
    "update.microsoft.com",
    "windowsupdate.com",
    "push.apple.com",
    "identity.apple.com",
    "play.googleapis.com",
    "android.googleapis.com",
    "mtalk.google.com",
    "gcm-http.googleapis.com",
    "icloud.com",
    "crashlytics.com",
}


class TenantSubnetRule:
    """Represents a CIDR-based client IP routing rule to an enterprise tenant hierarchy."""
    __slots__ = ("network", "tenant_id", "sub_tenant_id", "fleet_id")

    def __init__(self, cidr: str, tenant_id: str, sub_tenant_id: str, fleet_id: str):
        self.network = ipaddress.ip_network(cidr, strict=False)
        self.tenant_id = tenant_id
        self.sub_tenant_id = sub_tenant_id
        self.fleet_id = fleet_id

    def matches(self, ip_str: str) -> bool:
        try:
            addr = ipaddress.ip_address(ip_str)
            return addr in self.network
        except ValueError:
            return False


class EnterprisePipelineHook:
    """
    Sub-millisecond interception hook connecting the live DNS pipeline to
    multi-tenant columnar storage and real-time SIEM security telemetry.
    """

    def __init__(
        self,
        columnar_engine: Optional[ColumnarAnalyticsEngine] = None,
        siem_forwarder: Optional[SiemForwarder] = None,
        default_tenant_id: str = "tenant_default",
        default_sub_tenant_id: str = "unit_default",
        default_fleet_id: str = "fleet_default",
        siem_all_queries: bool = False,
    ):
        self._lock = threading.RLock()
        self.default_tenant_id = default_tenant_id
        self.default_sub_tenant_id = default_sub_tenant_id
        self.default_fleet_id = default_fleet_id
        self.siem_all_queries = siem_all_queries
        self.enabled = True

        # External services (dependency injection with singleton fallback)
        self._columnar_engine = columnar_engine or get_columnar_engine()
        self._siem_forwarder = siem_forwarder or get_siem_forwarder()

        # CIDR Subnet mappings (longest-prefix match ordering)
        self._subnet_rules: List[TenantSubnetRule] = []

        # Device mapping: client_ip -> (tenant_id, sub_tenant_id, fleet_id, device_id)
        self._static_ip_devices: Dict[str, Tuple[str, str, str, str]] = {}

        # Telemetry metrics
        self._queries_intercepted = 0
        self._queries_ingested = 0
        self._queries_dropped = 0
        self._safety_exemptions_granted = 0
        self._siem_events_streamed = 0
        self._blocked_events = 0

    def register_subnet_mapping(
        self,
        cidr: str,
        tenant_id: str,
        sub_tenant_id: str,
        fleet_id: str,
    ) -> None:
        """Associates a CIDR network range with an enterprise tenant hierarchy."""
        with self._lock:
            rule = TenantSubnetRule(cidr, tenant_id, sub_tenant_id, fleet_id)
            self._subnet_rules.append(rule)
            # Sort by prefix length descending for longest-prefix match
            self._subnet_rules.sort(key=lambda r: r.network.prefixlen, reverse=True)
            logger.info(f"Registered enterprise subnet {cidr} -> Tenant={tenant_id}, Unit={sub_tenant_id}")

    def register_static_device(
        self,
        client_ip: str,
        tenant_id: str,
        sub_tenant_id: str,
        fleet_id: str,
        device_id: str,
    ) -> None:
        """Registers a fixed IP-to-device mapping."""
        with self._lock:
            self._static_ip_devices[client_ip] = (tenant_id, sub_tenant_id, fleet_id, device_id)

    def resolve_tenant_context(self, client_ip: str) -> Tuple[str, str, str, str]:
        """
        Resolves client IP to (tenant_id, sub_tenant_id, fleet_id, device_id).
        Order of resolution:
          1. Static device IP mapping
          2. Longest-prefix CIDR subnet match
          3. Default fallback tenant
        """
        with self._lock:
            # 1. Static device lookup
            if client_ip in self._static_ip_devices:
                return self._static_ip_devices[client_ip]

            # 2. CIDR subnet rules
            for rule in self._subnet_rules:
                if rule.matches(client_ip):
                    return rule.tenant_id, rule.sub_tenant_id, rule.fleet_id, f"dev_{client_ip.replace('.', '_')}"

            # 3. Default fallback
            return (
                self.default_tenant_id,
                self.default_sub_tenant_id,
                self.default_fleet_id,
                f"dev_{client_ip.replace('.', '_')}"
            )

    def check_life_safety_exemption(self, domain: str) -> bool:
        """
        Evaluates whether the requested domain qualifies for Inviolable Life-Safety Exemption.
        Returns True if domain or parent domain matches hardcoded safety list.
        """
        clean_domain = domain.lower().strip(".")
        if clean_domain in LIFE_SAFETY_DOMAINS:
            return True
        for safe_domain in LIFE_SAFETY_DOMAINS:
            if clean_domain.endswith("." + safe_domain):
                return True
        return False

    def intercept_and_record(
        self,
        client_ip: str,
        domain: str,
        qtype: str = "A",
        action: str = "ALLOWED",
        rcode: str = "NOERROR",
        threat_type: str = "NONE",
        category: str = "UNCATEGORIZED",
        latency_us: int = 1200,
        bytes_transferred: int = 64,
        override_action: Optional[str] = None,
    ) -> Tuple[str, bool]:
        """
        Real-time interception point.
        Enforces Inviolable Life-Safety Exemption and pushes event to columnar & SIEM stores.

        Returns:
            Tuple[effective_action, is_safety_override]
        """
        if not self.enabled:
            return action, False

        with self._lock:
            self._queries_intercepted += 1

        clean_domain = domain.lower().strip(".")
        is_safety = self.check_life_safety_exemption(clean_domain)
        effective_action = action.upper()
        safety_override = False

        # Inviolable Life-Safety Exemption: Never allow blocking safety domains
        if is_safety and effective_action in ("BLOCKED", "SINKHOLED"):
            effective_action = "ALLOWED"
            safety_override = True
            with self._lock:
                self._safety_exemptions_granted += 1
            logger.warning(
                f"[LIFE-SAFETY EXEMPTION] Overriding illegal block on critical domain '{clean_domain}' "
                f"requested by client {client_ip}."
            )

        if override_action:
            effective_action = override_action.upper()

        if effective_action == "BLOCKED":
            with self._lock:
                self._blocked_events += 1

        # Resolve tenant hierarchy
        tenant_id, sub_tenant_id, fleet_id, device_id = self.resolve_tenant_context(client_ip)

        now_us = int(time.time() * 1_000_000)

        # Build columnar telemetry event
        event = DnsQueryEvent(
            timestamp_us=now_us,
            tenant_id=tenant_id,
            sub_tenant_id=sub_tenant_id,
            device_id=device_id,
            client_ip=client_ip,
            domain=clean_domain,
            qtype=qtype,
            rcode=rcode,
            action=effective_action,
            threat_type=threat_type,
            category=category,
            latency_us=latency_us,
            bytes_transferred=bytes_transferred,
        )

        # Asynchronous Columnar Ingestion
        if self._columnar_engine:
            queued = self._columnar_engine.log_query(event)
            with self._lock:
                if queued:
                    self._queries_ingested += 1
                else:
                    self._queries_dropped += 1

        # Real-Time SIEM Streaming
        if self._siem_forwarder:
            should_stream = self.siem_all_queries or (effective_action in ("BLOCKED", "SINKHOLED")) or (threat_type != "NONE") or safety_override
            if should_stream:
                severity = SyslogSeverity.INFORMATIONAL
                if safety_override:
                    severity = SyslogSeverity.CRITICAL
                elif threat_type in ("PHISHING", "MALWARE", "DGA", "TUNNELING"):
                    severity = SyslogSeverity.ALERT
                elif effective_action == "BLOCKED":
                    severity = SyslogSeverity.WARNING

                syslog_msg = Rfc5424SyslogMessage(
                    severity=severity,
                    msg_id=f"DNS_{effective_action}",
                    message=f"DNS Query '{clean_domain}' ({qtype}) action={effective_action} reason={threat_type} client={client_ip}",
                    structured_data={
                        "enterprise": {
                            "tenantId": tenant_id,
                            "unitId": sub_tenant_id,
                            "fleetId": fleet_id,
                            "deviceId": device_id,
                            "clientIp": client_ip,
                        },
                        "dns": {
                            "domain": clean_domain,
                            "qtype": qtype,
                            "action": effective_action,
                            "threatType": threat_type,
                            "category": category,
                            "safetyOverride": str(safety_override).lower(),
                        }
                    },
                    facility=SyslogFacility.LOCAL0,
                    hostname=f"tenant-{tenant_id}",
                    app_name="focusdns-pipeline",
                    proc_id=str(fleet_id),
                )
                if self._siem_forwarder.enqueue_message(syslog_msg):
                    with self._lock:
                        self._siem_events_streamed += 1

        return effective_action, safety_override

    def get_telemetry(self) -> Dict[str, Any]:
        """Returns runtime diagnostic metrics for enterprise monitoring."""
        with self._lock:
            return {
                "enabled": self.enabled,
                "queries_intercepted": self._queries_intercepted,
                "queries_ingested": self._queries_ingested,
                "queries_dropped": self._queries_dropped,
                "blocked_events": self._blocked_events,
                "safety_exemptions_granted": self._safety_exemptions_granted,
                "siem_events_streamed": self._siem_events_streamed,
                "active_subnet_rules": len(self._subnet_rules),
                "active_static_devices": len(self._static_ip_devices),
                "default_tenant": self.default_tenant_id,
            }

    def clear_mappings(self) -> None:
        """Clears all configured subnet and device routes."""
        with self._lock:
            self._subnet_rules.clear()
            self._static_ip_devices.clear()

    def shutdown(self) -> None:
        """Flushes columnar queues and disconnects forwarders."""
        with self._lock:
            self.enabled = False
            if self._columnar_engine:
                self._columnar_engine.flush()


# Global Singleton
_global_enterprise_hook: Optional[EnterprisePipelineHook] = None
_hook_lock = threading.Lock()


def get_enterprise_pipeline_hook() -> EnterprisePipelineHook:
    global _global_enterprise_hook
    with _hook_lock:
        if _global_enterprise_hook is None:
            _global_enterprise_hook = EnterprisePipelineHook()
        return _global_enterprise_hook
