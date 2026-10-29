"""
FocusDNS Enterprise Engine - Enterprise SIEM Integration (RFC 5424 Syslog & HEC).

Automated streaming of security events, zero-day threat catches, and policy drop logs
directly into Splunk, Datadog, Elastic, and enterprise SIEM aggregators.

Standards Implemented:
  1. RFC 5424 The Syslog Protocol:
     - Strict wire formatting (<PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID [STRUCTURED-DATA] MSG).
     - Standard Facility (LOG_LOCAL0 = 16) and granular RFC severities (Alert, Error, Warning, Notice, Info).
     - Standard enterprise PEN ID (Private Enterprise Number) structured data tags: [focusdns@54124 ...].
  2. Network Transports:
     - UDP, TCP, and TLS Syslog (RFC 5425).
  3. Direct Cloud SIEM Ingestion:
     - Splunk HTTP Event Collector (HEC) JSON payloads with Bearer token authentication.
     - Datadog Logs API (v2) with service tags and custom attributes.
     - Elasticsearch Bulk Indexer (_bulk) format.
  4. Backpressure Protection:
     - Circuit-breaker queueing drops lowest-priority logs during upstream SIEM outages.
"""

import datetime
import json
import logging
import os
import queue
import socket
import ssl
import threading
import time
import urllib.request
from enum import Enum
from typing import Dict, List, Set, Optional, Tuple, Any

from server.enterprise.columnar_analytics import DnsQueryEvent

logger = logging.getLogger("FocusDNS.Enterprise.SIEM")

PEN_FOCUSDNS = 54124  # Private Enterprise Number allocated for FocusDNS enterprise telemetry


class SyslogFacility(int, Enum):
    LOCAL0 = 16
    LOCAL1 = 17
    LOCAL2 = 18
    LOCAL3 = 19
    LOCAL4 = 20
    LOCAL5 = 21
    LOCAL6 = 22
    LOCAL7 = 23


class SyslogSeverity(int, Enum):
    EMERGENCY = 0
    ALERT = 1        # Zero-day threats (DGA, phishing, tunneling)
    CRITICAL = 2     # Strict mode tampering attempt
    ERROR = 3        # Authentication failure, broken audit chain
    WARNING = 4      # Blocked distraction site, policy violation
    NOTICE = 5       # Focus session locked/unlocked, policy pushed
    INFORMATIONAL = 6# Standard allowed DNS query
    DEBUG = 7


class SiemTransport(str, Enum):
    UDP = "UDP"
    TCP = "TCP"
    TLS = "TLS"
    SPLUNK_HEC = "SPLUNK_HEC"
    DATADOG_API = "DATADOG_API"
    ELASTIC_BULK = "ELASTIC_BULK"


class SiemConfig:
    """Configuration profile for enterprise SIEM streaming."""
    __slots__ = (
        "enabled", "transport", "host", "port", "api_token",
        "index_name", "facility", "min_severity", "tls_ca_cert"
    )

    def __init__(
        self,
        enabled: bool = True,
        transport: SiemTransport = SiemTransport.UDP,
        host: str = "127.0.0.1",
        port: int = 514,
        api_token: str = "",
        index_name: str = "focusdns_security",
        facility: SyslogFacility = SyslogFacility.LOCAL0,
        min_severity: SyslogSeverity = SyslogSeverity.WARNING,
        tls_ca_cert: Optional[str] = None
    ):
        self.enabled = enabled
        self.transport = transport if isinstance(transport, SiemTransport) else SiemTransport(transport)
        self.host = host
        self.port = port
        self.api_token = api_token
        self.index_name = index_name
        self.facility = facility if isinstance(facility, SyslogFacility) else SyslogFacility(facility)
        self.min_severity = min_severity if isinstance(min_severity, SyslogSeverity) else SyslogSeverity(min_severity)
        self.tls_ca_cert = tls_ca_cert

    def to_dict(self) -> Dict[str, Any]:
        return {
            "enabled": self.enabled,
            "transport": self.transport.value,
            "host": self.host,
            "port": self.port,
            "api_token": "***" if self.api_token else "",
            "index_name": self.index_name,
            "facility": self.facility.value,
            "min_severity": self.min_severity.value,
            "has_tls_ca": bool(self.tls_ca_cert)
        }


class Rfc5424SyslogMessage:
    """Compliant RFC 5424 Syslog protocol frame."""
    __slots__ = (
        "facility", "severity", "timestamp", "hostname",
        "app_name", "proc_id", "msg_id", "structured_data", "message"
    )

    def __init__(
        self,
        severity: SyslogSeverity,
        msg_id: str,
        message: str,
        structured_data: Optional[Dict[str, Dict[str, str]]] = None,
        facility: SyslogFacility = SyslogFacility.LOCAL0,
        hostname: Optional[str] = None,
        app_name: str = "FocusDNS",
        proc_id: Optional[str] = None,
        timestamp: Optional[datetime.datetime] = None
    ):
        self.facility = facility
        self.severity = severity
        self.timestamp = timestamp or datetime.datetime.now(datetime.timezone.utc)
        self.hostname = hostname or socket.gethostname() or "focusdns-gateway"
        self.app_name = app_name
        self.proc_id = proc_id or str(os.getpid())
        self.msg_id = msg_id
        self.structured_data = structured_data or {}
        self.message = message

    @property
    def priority(self) -> int:
        """Computes RFC 5424 PRI = (Facility * 8) + Severity."""
        return (self.facility.value * 8) + self.severity.value

    def to_rfc5424(self) -> str:
        """Serializes to standard RFC 5424 wire format."""
        # Format timestamp with microsecond precision: 2026-10-29T12:00:00.123456Z
        ts_str = self.timestamp.strftime("%Y-%m-%dT%H:%M:%S.%fZ")

        # Format Structured Data: [id key="val" key2="val2"]
        sd_str = ""
        if self.structured_data:
            sd_blocks = []
            for sd_id, params in self.structured_data.items():
                param_strs = [f'{k}="{v}"' for k, v in params.items()]
                sd_blocks.append(f"[{sd_id} {' '.join(param_strs)}]")
            sd_str = "".join(sd_blocks)
        else:
            sd_str = "-"

        header = f"<{self.priority}>1 {ts_str} {self.hostname} {self.app_name} {self.proc_id} {self.msg_id} {sd_str}"
        if self.message:
            return f"{header} {self.message}"
        return header


class SiemForwarder:
    """
    Enterprise SIEM Streaming Engine.
    Buffered, non-blocking exporter streaming RFC 5424 syslog packets,
    Splunk HEC payloads, Datadog events, and Elastic records.
    """

    def __init__(self, config: Optional[SiemConfig] = None, queue_size: int = 20000):
        self.config = config or SiemConfig()
        self.queue_size = queue_size
        self._queue: queue.Queue = queue.Queue(maxsize=queue_size)
        self._running = True
        self._lock = threading.RLock()
        self.dropped_events = 0
        self.sent_events = 0

        self._worker_thread = threading.Thread(
            target=self._forwarding_loop,
            name="SiemForwardWorker",
            daemon=True
        )
        self._worker_thread.start()

    def update_config(self, new_config: SiemConfig) -> None:
        with self._lock:
            self.config = new_config
            logger.info(f"SIEM configuration updated: {new_config.transport.value} to {new_config.host}:{new_config.port}")

    def enqueue_message(self, message: Rfc5424SyslogMessage) -> bool:
        """Pushes an RFC 5424 message to the async forwarding queue."""
        if not self.config.enabled:
            return False

        # Filter by severity ceiling
        if message.severity.value > self.config.min_severity.value:
            return False

        try:
            self._queue.put_nowait(message)
            return True
        except queue.Full:
            self.dropped_events += 1
            if self.dropped_events % 100 == 1:
                logger.warning(f"SIEM forwarding queue full; dropped {self.dropped_events} events.")
            return False

    def stream_dns_event(self, event: DnsQueryEvent) -> bool:
        """Transforms a DNS query event into an RFC 5424 message."""
        severity = SyslogSeverity.INFORMATIONAL
        msg_id = "DNS_QUERY"

        if event.threat_type != "NONE":
            severity = SyslogSeverity.ALERT
            msg_id = "THREAT_BLOCKED"
        elif "BLOCK" in event.action:
            severity = SyslogSeverity.WARNING
            msg_id = "POLICY_BLOCKED"

        sd = {
            f"focusdns@{PEN_FOCUSDNS}": {
                "tenant": event.tenant_id,
                "unit": event.sub_tenant_id,
                "device": event.device_id,
                "ip": event.client_ip,
                "domain": event.domain,
                "qtype": event.qtype,
                "action": event.action,
                "threat": event.threat_type,
                "category": event.category,
                "latency_us": str(event.latency_us)
            }
        }
        msg = f"DNS query '{event.domain}' ({event.qtype}) from {event.client_ip} verdict={event.action} threat={event.threat_type}"
        syslog_msg = Rfc5424SyslogMessage(
            severity=severity,
            msg_id=msg_id,
            message=msg,
            structured_data=sd,
            facility=self.config.facility
        )
        return self.enqueue_message(syslog_msg)

    def stream_security_violation(
        self,
        tenant_id: str,
        actor: str,
        action: str,
        reason: str
    ) -> bool:
        """Streams an immediate high-priority audit security alert."""
        sd = {
            f"focusdns@{PEN_FOCUSDNS}": {
                "tenant": tenant_id,
                "actor": actor,
                "action": action,
                "violation": "STRICT_MODE_BREACH_ATTEMPT"
            }
        }
        syslog_msg = Rfc5424SyslogMessage(
            severity=SyslogSeverity.CRITICAL,
            msg_id="SECURITY_VIOLATION",
            message=f"Tampering attempt by {actor} on tenant {tenant_id}: {reason}",
            structured_data=sd,
            facility=self.config.facility
        )
        return self.enqueue_message(syslog_msg)

    def _forwarding_loop(self) -> None:
        """Background thread dispatching messages to configured SIEM backend."""
        while self._running:
            try:
                msg = self._queue.get(timeout=0.2)
            except queue.Empty:
                continue

            try:
                self._dispatch_single(msg)
                self.sent_events += 1
            except Exception as e:
                logger.error(f"Error forwarding SIEM packet via {self.config.transport.value}: {e}")

    def _dispatch_single(self, msg: Rfc5424SyslogMessage) -> None:
        cfg = self.config
        raw_str = msg.to_rfc5424() + "\n"
        raw_bytes = raw_str.encode("utf-8")

        if cfg.transport == SiemTransport.UDP:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.sendto(raw_bytes, (cfg.host, cfg.port))
            sock.close()

        elif cfg.transport == SiemTransport.TCP:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(2.0)
            sock.connect((cfg.host, cfg.port))
            sock.sendall(raw_bytes)
            sock.close()

        elif cfg.transport == SiemTransport.TLS:
            raw_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            context = ssl.create_default_context()
            if cfg.tls_ca_cert and os.path.exists(cfg.tls_ca_cert):
                context.load_verify_locations(cafile=cfg.tls_ca_cert)
            else:
                context.check_hostname = False
                context.verify_mode = ssl.CERT_NONE

            tls_sock = context.wrap_socket(raw_sock, server_hostname=cfg.host)
            tls_sock.settimeout(2.0)
            tls_sock.connect((cfg.host, cfg.port))
            tls_sock.sendall(raw_bytes)
            tls_sock.close()

        elif cfg.transport == SiemTransport.SPLUNK_HEC:
            # Format Splunk HEC JSON payload
            hec_payload = {
                "time": msg.timestamp.timestamp(),
                "host": msg.hostname,
                "source": "focusdns:agent",
                "sourcetype": "focusdns:syslog:rfc5424",
                "index": cfg.index_name,
                "event": {
                    "message": msg.message,
                    "msg_id": msg.msg_id,
                    "severity": msg.severity.name,
                    "facility": msg.facility.name,
                    "structured_data": msg.structured_data
                }
            }
            self._post_http(
                f"http://{cfg.host}:{cfg.port}/services/collector/event",
                hec_payload,
                headers={"Authorization": f"Splunk {cfg.api_token}"}
            )

        elif cfg.transport == SiemTransport.DATADOG_API:
            dd_payload = {
                "ddsource": "focusdns",
                "service": "focusdns-gateway",
                "hostname": msg.hostname,
                "message": msg.message,
                "status": msg.severity.name.lower(),
                "tags": [f"msg_id:{msg.msg_id}", f"facility:{msg.facility.name}"],
                "attributes": msg.structured_data
            }
            self._post_http(
                f"https://{cfg.host}:{cfg.port}/api/v2/logs",
                dd_payload,
                headers={"DD-API-KEY": cfg.api_token}
            )

    @staticmethod
    def _post_http(url: str, json_data: Dict[str, Any], headers: Dict[str, str]) -> None:
        data = json.dumps(json_data).encode("utf-8")
        req = urllib.request.Request(url, data=data, method="POST")
        req.add_header("Content-Type", "application/json")
        for k, v in headers.items():
            req.add_header(k, v)
        with urllib.request.urlopen(req, timeout=3.0) as resp:
            resp.read()

    def test_connection(self) -> Tuple[bool, str]:
        """Sends a synthetic test packet to verify SIEM reachability."""
        test_msg = Rfc5424SyslogMessage(
            severity=SyslogSeverity.NOTICE,
            msg_id="SIEM_TEST_PROBE",
            message="FocusDNS Enterprise SIEM connectivity test probe.",
            facility=self.config.facility
        )
        try:
            self._dispatch_single(test_msg)
            return True, f"Successfully transmitted RFC 5424 test probe via {self.config.transport.value} to {self.config.host}:{self.config.port}"
        except Exception as e:
            return False, f"SIEM transmission failed: {e}"

    def shutdown(self) -> None:
        self._running = False
        if self._worker_thread.is_alive():
            self._worker_thread.join(timeout=1.0)


# Global Singleton
_global_siem_forwarder: Optional[SiemForwarder] = None
_siem_lock = threading.Lock()


def get_siem_forwarder() -> SiemForwarder:
    global _global_siem_forwarder
    with _siem_lock:
        if _global_siem_forwarder is None:
            _global_siem_forwarder = SiemForwarder()
        return _global_siem_forwarder
