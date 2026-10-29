"""
FocusDNS Enterprise Engine - Inbound SIEM Ingestion & Bidirectional Webhook Gateway.

Ingests external threat alerts from Enterprise SIEM platforms:
  - Splunk Alert Webhook (Common Information Model - CIM)
  - Datadog Monitors (Webhook with HMAC-SHA256 signature verification)
  - Elastic Security ECS Alerts (Elastic Common Schema)
  - Generic RFC 5424 Syslog Ingest

Features:
  - Cryptographic Signature Verification (HMAC-SHA256 / Bearer Auth)
  - Normalized Schema Mapping into `SiemIngestAlert`
  - Sliding-Window Ingestion Deduplication (300s window) to prevent alert floods
  - Automated Dispatch into `SoarPlaybookEngine` for dynamic sub-50ms quarantine
  - Inviolable Life Safety Exemption Guard: External alerts targeting critical emergency
    infrastructure (911.gov, update.microsoft.com, etc.) are strictly neutralized.
"""

import enum
import hashlib
import hmac
import json
import logging
import threading
import time
from typing import Dict, List, Optional, Set, Tuple, Any

from server.enterprise.soar_playbook_engine import (
    SoarPlaybookEngine,
    SoarIncident,
    get_soar_engine
)
from server.enterprise.tenant_manager import TenantManager, get_tenant_manager

logger = logging.getLogger("FocusDNS.Enterprise.SiemIngestGateway")

# Inviolable Life Safety Domains that can NEVER be blocked by SIEM alerts
CRITICAL_LIFE_SAFETY_DOMAINS: Set[str] = {
    "911.gov",
    "112.gov",
    "emergency.gov",
    "update.microsoft.com",
    "push.apple.com",
    "play.googleapis.com"
}


class SiemVendorType(str, enum.Enum):
    SPLUNK = "SPLUNK"
    DATADOG = "DATADOG"
    ELASTIC = "ELASTIC"
    GENERIC_SYSLOG = "GENERIC_SYSLOG"

    @classmethod
    def from_str(cls, val: str) -> "SiemVendorType":
        try:
            return cls(val.upper())
        except Exception:
            return cls.GENERIC_SYSLOG


class SiemIngestAlert:
    """Normalized external SIEM security alert."""

    def __init__(
        self,
        alert_id: str,
        vendor: SiemVendorType,
        tenant_id: str,
        device_id: Optional[str] = None,
        client_ip: Optional[str] = None,
        indicator_domain: Optional[str] = None,
        threat_type: str = "EXTERNAL_SIEM_ALERT",
        severity: str = "HIGH",
        risk_score: float = 75.0,
        raw_payload: Optional[Dict[str, Any]] = None,
        received_at: Optional[float] = None,
        deduplicated: bool = False
    ):
        self.alert_id = alert_id
        self.vendor = vendor
        self.tenant_id = tenant_id
        self.device_id = device_id
        self.client_ip = client_ip
        self.indicator_domain = (indicator_domain or "").strip().lower()
        self.threat_type = threat_type.upper()
        self.severity = severity.upper()
        self.risk_score = max(0.0, min(100.0, float(risk_score)))
        self.raw_payload = raw_payload or {}
        self.received_at = received_at if received_at is not None else time.time()
        self.deduplicated = deduplicated

    def to_dict(self) -> Dict[str, Any]:
        return {
            "alert_id": self.alert_id,
            "vendor": self.vendor.value,
            "tenant_id": self.tenant_id,
            "device_id": self.device_id,
            "client_ip": self.client_ip,
            "indicator_domain": self.indicator_domain,
            "threat_type": self.threat_type,
            "severity": self.severity,
            "risk_score": self.risk_score,
            "received_at": self.received_at,
            "deduplicated": self.deduplicated,
            "raw_payload": self.raw_payload
        }


class SiemIngestGateway:
    """
    Enterprise Inbound SIEM Ingestion Gateway.
    Receives alerts from Splunk, Datadog, Elastic, verifies cryptographic signatures,
    normalizes payloads, suppresses deduplicated events, and invokes SOAR playbooks.
    """

    def __init__(
        self,
        soar_engine: Optional[SoarPlaybookEngine] = None,
        tenant_mgr: Optional[TenantManager] = None,
        dedup_window_seconds: float = 300.0,
        auto_soar_threshold: float = 70.0
    ):
        self.soar = soar_engine or get_soar_engine()
        self.tenants = tenant_mgr or get_tenant_manager()
        self.dedup_window_seconds = dedup_window_seconds
        self.auto_soar_threshold = auto_soar_threshold

        # Vendor Secrets: {tenant_id: {vendor: secret_str}}
        self._vendor_secrets: Dict[str, Dict[SiemVendorType, str]] = {}
        # Global fallback secrets if tenant-specific not set
        self._default_secrets: Dict[SiemVendorType, str] = {
            SiemVendorType.SPLUNK: "focusdns-splunk-hec-secret",
            SiemVendorType.DATADOG: "focusdns-datadog-webhook-token",
            SiemVendorType.ELASTIC: "focusdns-elastic-sec-key"
        }

        # Deduplication Cache: {(tenant_id, indicator_domain, client_ip): last_seen_timestamp}
        self._dedup_cache: Dict[Tuple[str, str, str], float] = {}
        self._lock = threading.RLock()

        # Telemetry & History
        self._recent_alerts: List[SiemIngestAlert] = []
        self._max_recent_alerts = 500
        self._stats = {
            "total_received": 0,
            "total_deduplicated": 0,
            "total_dispatched_soar": 0,
            "invalid_signatures": 0,
            "life_safety_neutralized": 0,
            "by_vendor": {
                SiemVendorType.SPLUNK.value: 0,
                SiemVendorType.DATADOG.value: 0,
                SiemVendorType.ELASTIC.value: 0,
                SiemVendorType.GENERIC_SYSLOG.value: 0
            }
        }

    def set_vendor_secret(self, vendor: SiemVendorType, secret: str, tenant_id: Optional[str] = None) -> None:
        """Register or update a shared secret/token for webhook verification."""
        with self._lock:
            if tenant_id:
                if tenant_id not in self._vendor_secrets:
                    self._vendor_secrets[tenant_id] = {}
                self._vendor_secrets[tenant_id][vendor] = secret
            else:
                self._default_secrets[vendor] = secret

    def get_vendor_secret(self, vendor: SiemVendorType, tenant_id: Optional[str] = None) -> str:
        """Retrieve the configured secret for the given vendor and tenant."""
        with self._lock:
            if tenant_id and tenant_id in self._vendor_secrets:
                if vendor in self._vendor_secrets[tenant_id]:
                    return self._vendor_secrets[tenant_id][vendor]
            return self._default_secrets.get(vendor, "")

    def verify_webhook_signature(
        self,
        vendor: SiemVendorType,
        headers: Dict[str, str],
        raw_body: bytes,
        tenant_id: Optional[str] = None
    ) -> bool:
        """
        Cryptographically verify the authenticity of an incoming SIEM webhook payload.
        """
        secret = self.get_vendor_secret(vendor, tenant_id)
        if not secret:
            # If no secret configured, accept (useful in test mode)
            return True

        # Case-insensitive header lookup
        normalized_headers = {k.lower(): v for k, v in headers.items()}

        if vendor == SiemVendorType.SPLUNK:
            # Splunk sends Authorization: Bearer <token> or Splunk <token>
            auth_val = normalized_headers.get("authorization", "")
            if auth_val.startswith("Bearer "):
                token = auth_val[7:].strip()
            elif auth_val.startswith("Splunk "):
                token = auth_val[7:].strip()
            else:
                token = auth_val.strip()
            return hmac.compare_digest(token, secret)

        elif vendor == SiemVendorType.DATADOG:
            # Datadog webhook signature in X-Datadog-Signature
            sig = normalized_headers.get("x-datadog-signature", "")
            if not sig:
                # Check query parameter or custom token header
                token_header = normalized_headers.get("x-datadog-webhook-token", "")
                if token_header:
                    return hmac.compare_digest(token_header, secret)
                return False
            expected_sig = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
            return hmac.compare_digest(sig.lower(), expected_sig.lower())

        elif vendor == SiemVendorType.ELASTIC:
            # Elastic Security uses Authorization: ApiKey <key> or X-Elastic-Secret
            token = normalized_headers.get("x-elastic-secret", "")
            if not token:
                auth = normalized_headers.get("authorization", "")
                if auth.startswith("ApiKey "):
                    token = auth[7:].strip()
                elif auth.startswith("Bearer "):
                    token = auth[7:].strip()
                else:
                    token = auth.strip()
            return hmac.compare_digest(token, secret)

        return True

    def ingest_splunk_alert(
        self,
        payload: Dict[str, Any],
        headers: Optional[Dict[str, str]] = None,
        tenant_id_override: Optional[str] = None,
        raw_body: Optional[bytes] = None
    ) -> Tuple[bool, str, Optional[SiemIngestAlert]]:
        """
        Ingest and normalize a Splunk Common Information Model (CIM) Alert.
        Expected format:
        {
          "sid": "1698572...",
          "search_name": "FocusDNS - High Volume C2 Anomaly",
          "result": {
            "src_ip": "10.0.1.42",
            "device_id": "win11_laptop_12",
            "query": "malicious-c2-beacon.xyz",
            "threat_category": "COMMAND_AND_CONTROL",
            "urgency": "critical",
            "tenant_id": "org_springfield"
          }
        }
        """
        headers = headers or {}
        tenant_id = (
            tenant_id_override
            or payload.get("result", {}).get("tenant_id")
            or payload.get("tenant_id")
            or "org_default"
        )

        body_bytes = raw_body or json.dumps(payload).encode("utf-8")
        if not self.verify_webhook_signature(SiemVendorType.SPLUNK, headers, body_bytes, tenant_id):
            with self._lock:
                self._stats["invalid_signatures"] += 1
            return False, "Invalid Splunk authentication token", None

        result_obj = payload.get("result", {})
        alert_id = payload.get("sid") or f"splunk_{int(time.time() * 1000)}"
        threat_type = result_obj.get("threat_category") or payload.get("search_name") or "SPLUNK_ANOMALY"
        domain = result_obj.get("query") or result_obj.get("domain") or payload.get("domain")
        device_id = result_obj.get("device_id") or payload.get("device_id")
        client_ip = result_obj.get("src_ip") or result_obj.get("client_ip") or payload.get("client_ip")

        urgency = str(result_obj.get("urgency", payload.get("urgency", "high"))).upper()
        severity_map = {"CRITICAL": 95.0, "HIGH": 80.0, "MEDIUM": 50.0, "LOW": 20.0}
        risk_score = severity_map.get(urgency, 75.0)

        alert = SiemIngestAlert(
            alert_id=alert_id,
            vendor=SiemVendorType.SPLUNK,
            tenant_id=tenant_id,
            device_id=device_id,
            client_ip=client_ip,
            indicator_domain=domain,
            threat_type=threat_type,
            severity=urgency,
            risk_score=risk_score,
            raw_payload=payload
        )
        return self._process_alert(alert)

    def ingest_datadog_alert(
        self,
        payload: Dict[str, Any],
        headers: Optional[Dict[str, str]] = None,
        tenant_id_override: Optional[str] = None,
        raw_body: Optional[bytes] = None
    ) -> Tuple[bool, str, Optional[SiemIngestAlert]]:
        """
        Ingest and normalize a Datadog Monitor Alert Webhook.
        Expected format:
        {
          "id": "datadog_event_9981",
          "event_title": "[Alert] Spike in DGA Domain Invocations",
          "alert_type": "error",
          "tags": ["tenant:org_springfield", "device:macbook_air_09", "ip:192.168.1.55"],
          "body": "Excessive queries to xyz-malware.cc",
          "domain": "xyz-malware.cc"
        }
        """
        headers = headers or {}
        # Parse tags
        tags_list = payload.get("tags", [])
        tag_dict = {}
        for tag in tags_list:
            if ":" in tag:
                k, v = tag.split(":", 1)
                tag_dict[k.strip().lower()] = v.strip()

        tenant_id = (
            tenant_id_override
            or tag_dict.get("tenant")
            or payload.get("tenant_id")
            or "org_default"
        )

        body_bytes = raw_body or json.dumps(payload).encode("utf-8")
        if not self.verify_webhook_signature(SiemVendorType.DATADOG, headers, body_bytes, tenant_id):
            with self._lock:
                self._stats["invalid_signatures"] += 1
            return False, "Invalid Datadog webhook HMAC signature", None

        alert_id = str(payload.get("id") or f"dd_{int(time.time() * 1000)}")
        threat_type = payload.get("event_title") or "DATADOG_MONITOR_BREACH"
        device_id = tag_dict.get("device") or payload.get("device_id")
        client_ip = tag_dict.get("ip") or payload.get("client_ip")
        domain = payload.get("domain") or tag_dict.get("domain")

        # Parse body for domain if missing
        if not domain and "body" in payload:
            words = str(payload["body"]).split()
            for w in words:
                if "." in w and not w.startswith("http"):
                    domain = w.strip(".,;:()")
                    break

        alert_type = str(payload.get("alert_type", "error")).lower()
        if alert_type == "error":
            severity = "CRITICAL"
            risk_score = 90.0
        elif alert_type == "warning":
            severity = "HIGH"
            risk_score = 70.0
        else:
            severity = "MEDIUM"
            risk_score = 45.0

        alert = SiemIngestAlert(
            alert_id=alert_id,
            vendor=SiemVendorType.DATADOG,
            tenant_id=tenant_id,
            device_id=device_id,
            client_ip=client_ip,
            indicator_domain=domain,
            threat_type=threat_type,
            severity=severity,
            risk_score=risk_score,
            raw_payload=payload
        )
        return self._process_alert(alert)

    def ingest_elastic_alert(
        self,
        payload: Dict[str, Any],
        headers: Optional[Dict[str, str]] = None,
        tenant_id_override: Optional[str] = None,
        raw_body: Optional[bytes] = None
    ) -> Tuple[bool, str, Optional[SiemIngestAlert]]:
        """
        Ingest and normalize an Elastic Security ECS Alert.
        Expected format:
        {
          "kibana.alert.rule.name": "DNS Tunneling Exfiltration Observed",
          "kibana.alert.rule.id": "rule_elastic_884",
          "source.ip": "10.200.1.99",
          "host.name": "srv_dns_edge",
          "dns.question.name": "exfil-tunnel.dnscat.org",
          "event.severity": 3,
          "labels": {"tenant_id": "org_springfield", "device_id": "iot_sensor_4"}
        }
        """
        headers = headers or {}
        labels = payload.get("labels", {})
        tenant_id = (
            tenant_id_override
            or labels.get("tenant_id")
            or payload.get("tenant_id")
            or "org_default"
        )

        body_bytes = raw_body or json.dumps(payload).encode("utf-8")
        if not self.verify_webhook_signature(SiemVendorType.ELASTIC, headers, body_bytes, tenant_id):
            with self._lock:
                self._stats["invalid_signatures"] += 1
            return False, "Invalid Elastic Security secret key", None

        alert_id = payload.get("kibana.alert.rule.id") or f"elastic_{int(time.time() * 1000)}"
        threat_type = payload.get("kibana.alert.rule.name") or "ELASTIC_SECURITY_DETECTION"
        client_ip = payload.get("source.ip") or payload.get("source", {}).get("ip")
        domain = payload.get("dns.question.name") or payload.get("dns", {}).get("question", {}).get("name")
        device_id = labels.get("device_id") or payload.get("host.name") or payload.get("host", {}).get("name")

        # Elastic severity integer: 1=low, 2=med, 3=high, 4=critical
        sev_int = payload.get("event.severity", 3)
        if sev_int >= 4:
            severity = "CRITICAL"
            risk_score = 95.0
        elif sev_int == 3:
            severity = "HIGH"
            risk_score = 80.0
        elif sev_int == 2:
            severity = "MEDIUM"
            risk_score = 50.0
        else:
            severity = "LOW"
            risk_score = 25.0

        alert = SiemIngestAlert(
            alert_id=alert_id,
            vendor=SiemVendorType.ELASTIC,
            tenant_id=tenant_id,
            device_id=device_id,
            client_ip=client_ip,
            indicator_domain=domain,
            threat_type=threat_type,
            severity=severity,
            risk_score=risk_score,
            raw_payload=payload
        )
        return self._process_alert(alert)

    def _process_alert(self, alert: SiemIngestAlert) -> Tuple[bool, str, SiemIngestAlert]:
        """
        Core normalization, deduplication, life safety check, and SOAR execution.
        """
        now = time.time()
        with self._lock:
            self._stats["total_received"] += 1
            self._stats["by_vendor"][alert.vendor.value] = (
                self._stats["by_vendor"].get(alert.vendor.value, 0) + 1
            )

            # Deduplication Key: (tenant_id, domain, client_ip)
            dedup_key = (
                alert.tenant_id,
                alert.indicator_domain or "",
                alert.client_ip or ""
            )

            last_seen = self._dedup_cache.get(dedup_key, 0.0)
            if (now - last_seen) < self.dedup_window_seconds and last_seen > 0:
                alert.deduplicated = True
                self._stats["total_deduplicated"] += 1
                self._record_recent(alert)
                logger.info(
                    f"[SIEM DEDUP] Suppressing duplicate alert for '{alert.indicator_domain}' "
                    f"from {alert.vendor.value} (seen {now - last_seen:.1f}s ago)."
                )
                return True, "Alert ingested (deduplicated within sliding window)", alert

            # Update cache & sweep old records if cache grows large
            self._dedup_cache[dedup_key] = now
            if len(self._dedup_cache) > 10000:
                cutoff = now - self.dedup_window_seconds
                self._dedup_cache = {k: ts for k, ts in self._dedup_cache.items() if ts > cutoff}

        # Inviolable Life Safety Exemption Guard
        if alert.indicator_domain:
            norm_dom = alert.indicator_domain.lower().strip(".")
            for critical in CRITICAL_LIFE_SAFETY_DOMAINS:
                if norm_dom == critical or norm_dom.endswith("." + critical):
                    with self._lock:
                        self._stats["life_safety_neutralized"] += 1
                    logger.warning(
                        f"[LIFE SAFETY DEFENSE] External SIEM alert targeted critical domain '{norm_dom}'! "
                        f"Neutralizing automated block/quarantine playbook."
                    )
                    self._record_recent(alert)
                    return True, f"Alert ingested; Life Safety Exemption protected '{norm_dom}'", alert

        # Automated SOAR Playbook Trigger
        if alert.risk_score >= self.auto_soar_threshold:
            self._dispatch_to_soar(alert)

        self._record_recent(alert)
        return True, "Alert ingested and processed successfully", alert

    def _dispatch_to_soar(self, alert: SiemIngestAlert) -> Optional[SoarIncident]:
        """Trigger SOAR Playbook if threshold is met."""
        try:
            with self._lock:
                self._stats["total_dispatched_soar"] += 1

            logger.info(
                f"[SIEM -> SOAR] Triggering automated playbook for alert '{alert.alert_id}' "
                f"vendor={alert.vendor.value} domain={alert.indicator_domain} score={alert.risk_score}"
            )

            threat_event = {
                "tenant_id": alert.tenant_id,
                "device_id": alert.device_id or "unknown_device",
                "client_ip": alert.client_ip or "0.0.0.0",
                "domain": alert.indicator_domain or "unknown.domain",
                "threat_type": alert.threat_type,
                "risk_score": alert.risk_score,
                "source": f"SIEM_{alert.vendor.value}"
            }
            return self.soar.evaluate_threat_event(threat_event)
        except Exception as e:
            logger.error(f"Error dispatching SIEM alert to SOAR: {e}", exc_info=True)
            return None

    def _record_recent(self, alert: SiemIngestAlert) -> None:
        with self._lock:
            self._recent_alerts.insert(0, alert)
            if len(self._recent_alerts) > self._max_recent_alerts:
                self._recent_alerts.pop()

    def get_recent_alerts(self, limit: int = 50, tenant_id: Optional[str] = None) -> List[Dict[str, Any]]:
        with self._lock:
            res = []
            for a in self._recent_alerts:
                if tenant_id and a.tenant_id != tenant_id:
                    continue
                res.append(a.to_dict())
                if len(res) >= limit:
                    break
            return res

    def get_telemetry(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "stats": dict(self._stats),
                "dedup_window_seconds": self.dedup_window_seconds,
                "auto_soar_threshold": self.auto_soar_threshold,
                "cached_signatures": len(self._dedup_cache),
                "in_memory_recent_count": len(self._recent_alerts)
            }


# Global Singleton
_global_siem_gateway: Optional[SiemIngestGateway] = None
_gateway_lock = threading.Lock()


def get_siem_ingest_gateway() -> SiemIngestGateway:
    global _global_siem_gateway
    with _gateway_lock:
        if _global_siem_gateway is None:
            _global_siem_gateway = SiemIngestGateway()
        return _global_siem_gateway
