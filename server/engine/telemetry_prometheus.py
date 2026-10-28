"""
FocusDNS Engine - Prometheus & OpenTelemetry Metrics Subsystem
Standards & Specifications:
- Prometheus Exposition Format 0.0.4
- OpenTelemetry Metrics Specification v1.0
- RFC 8499: DNS Terminology
"""

import threading
import time
from enum import Enum
from typing import Any, Dict, List, Optional, Set, Tuple, Union


class MetricType(Enum):
    COUNTER = "counter"
    GAUGE = "gauge"
    HISTOGRAM = "histogram"


def format_labels(labels: Optional[Dict[str, str]]) -> str:
    """Formats label dictionary to Prometheus '{k1="v1",k2="v2"}' string."""
    if not labels:
        return ""
    sorted_pairs = sorted(labels.items())
    parts = [f'{k}="{v}"' for k, v in sorted_pairs]
    return "{" + ",".join(parts) + "}"


class CounterMetric:
    """Thread-safe Prometheus Counter with dimensional labels."""

    def __init__(self, name: str, help_text: str):
        self.name: str = name
        self.help_text: str = help_text
        self._values: Dict[Tuple[Tuple[str, str], ...], float] = {}
        self._lock = threading.Lock()

    def inc(self, value: float = 1.0, labels: Optional[Dict[str, str]] = None):
        if value < 0:
            raise ValueError("Counters can only be incremented by non-negative amounts")
        key = tuple(sorted(labels.items())) if labels else ()
        with self._lock:
            self._values[key] = self._values.get(key, 0.0) + value

    def get(self, labels: Optional[Dict[str, str]] = None) -> float:
        key = tuple(sorted(labels.items())) if labels else ()
        with self._lock:
            return self._values.get(key, 0.0)

    def render(self) -> List[str]:
        lines = [
            f"# HELP {self.name} {self.help_text}",
            f"# TYPE {self.name} counter",
        ]
        with self._lock:
            for key, val in sorted(self._values.items()):
                label_str = format_labels(dict(key))
                lines.append(f"{self.name}{label_str} {val}")
        return lines


class GaugeMetric:
    """Thread-safe Prometheus Gauge with dimensional labels."""

    def __init__(self, name: str, help_text: str):
        self.name: str = name
        self.help_text: str = help_text
        self._values: Dict[Tuple[Tuple[str, str], ...], float] = {}
        self._lock = threading.Lock()

    def set(self, value: float, labels: Optional[Dict[str, str]] = None):
        key = tuple(sorted(labels.items())) if labels else ()
        with self._lock:
            self._values[key] = float(value)

    def inc(self, value: float = 1.0, labels: Optional[Dict[str, str]] = None):
        key = tuple(sorted(labels.items())) if labels else ()
        with self._lock:
            self._values[key] = self._values.get(key, 0.0) + value

    def dec(self, value: float = 1.0, labels: Optional[Dict[str, str]] = None):
        key = tuple(sorted(labels.items())) if labels else ()
        with self._lock:
            self._values[key] = self._values.get(key, 0.0) - value

    def get(self, labels: Optional[Dict[str, str]] = None) -> float:
        key = tuple(sorted(labels.items())) if labels else ()
        with self._lock:
            return self._values.get(key, 0.0)

    def render(self) -> List[str]:
        lines = [
            f"# HELP {self.name} {self.help_text}",
            f"# TYPE {self.name} gauge",
        ]
        with self._lock:
            for key, val in sorted(self._values.items()):
                label_str = format_labels(dict(key))
                lines.append(f"{self.name}{label_str} {val}")
        return lines


DEFAULT_LATENCY_BUCKETS = (0.0005, 0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5)


class HistogramMetric:
    """Thread-safe Prometheus Histogram with cumulative upper bounds (le)."""

    def __init__(self, name: str, help_text: str, buckets: Tuple[float, ...] = DEFAULT_LATENCY_BUCKETS):
        self.name: str = name
        self.help_text: str = help_text
        self.buckets: Tuple[float, ...] = tuple(sorted(buckets))
        # key -> {bucket_le: count, '_sum': float, '_count': int}
        self._values: Dict[Tuple[Tuple[str, str], ...], Dict[Any, float]] = {}
        self._lock = threading.Lock()

    def observe(self, value: float, labels: Optional[Dict[str, str]] = None):
        key = tuple(sorted(labels.items())) if labels else ()
        with self._lock:
            if key not in self._values:
                b_dict: Dict[Any, float] = {b: 0.0 for b in self.buckets}
                b_dict["+Inf"] = 0.0
                b_dict["_sum"] = 0.0
                b_dict["_count"] = 0.0
                self._values[key] = b_dict

            entry = self._values[key]
            entry["_sum"] += value
            entry["_count"] += 1

            for b in self.buckets:
                if value <= b:
                    entry[b] += 1
            entry["+Inf"] += 1

    def render(self) -> List[str]:
        lines = [
            f"# HELP {self.name} {self.help_text}",
            f"# TYPE {self.name} histogram",
        ]
        with self._lock:
            for key, data in sorted(self._values.items()):
                base_labels = dict(key)
                for b in self.buckets:
                    b_labels = dict(base_labels)
                    b_labels["le"] = str(b)
                    lines.append(f"{self.name}_bucket{format_labels(b_labels)} {int(data[b])}")

                inf_labels = dict(base_labels)
                inf_labels["le"] = "+Inf"
                lines.append(f"{self.name}_bucket{format_labels(inf_labels)} {int(data['+Inf'])}")
                lines.append(f"{self.name}_sum{format_labels(base_labels)} {data['_sum']:.6f}")
                lines.append(f"{self.name}_count{format_labels(base_labels)} {int(data['_count'])}")
        return lines


class PrometheusExporter:
    """
    Carrier-grade Prometheus exposition metrics engine.
    Collects real-time telemetry across all DNS transports, caches,
    security filters, and upstream resolvers.
    """

    def __init__(self):
        # Queries counter: protocol, qtype, rcode
        self.queries_total = CounterMetric(
            "focusdns_queries_total", "Total incoming DNS queries categorized by transport, qtype, and rcode"
        )
        # Latency histogram: transport, rcode
        self.query_duration_seconds = HistogramMetric(
            "focusdns_query_duration_seconds", "End-to-end DNS query processing latency in seconds"
        )
        # Cache hits counter: state (hit, stale, miss)
        self.cache_lookups_total = CounterMetric(
            "focusdns_cache_lookups_total", "DNS resolution cache lookups partitioned by state"
        )
        # DNSSEC validation counter: status (secure, insecure, bogus, unsigned)
        self.dnssec_validations_total = CounterMetric(
            "focusdns_dnssec_validations_total", "DNSSEC cryptographic validation outcomes"
        )
        # XDP drops counter: reason (rate_limit, amplification, blocklist)
        self.xdp_packet_drops_total = CounterMetric(
            "focusdns_xdp_packet_drops_total", "Kernel-bypass eBPF/XDP driver packet drops"
        )
        # Threat blocks counter: threat_type (dga, tunneling, fastflux)
        self.threat_blocks_total = CounterMetric(
            "focusdns_threat_blocks_total", "Queries blocked by real-time heuristic threat analytics"
        )
        # Active connections gauge: transport
        self.active_connections = GaugeMetric(
            "focusdns_active_connections", "Number of currently active client connections"
        )
        # Upstream latency gauge: upstream_ip
        self.upstream_latency_ms = GaugeMetric(
            "focusdns_upstream_latency_ms", "Latest measured round-trip latency to upstream resolvers in milliseconds"
        )

        self._all_metrics = [
            self.queries_total,
            self.query_duration_seconds,
            self.cache_lookups_total,
            self.dnssec_validations_total,
            self.xdp_packet_drops_total,
            self.threat_blocks_total,
            self.active_connections,
            self.upstream_latency_ms,
        ]

    def record_query(self, transport: str, qtype: str, rcode: str, duration_sec: float):
        """Records an evaluated DNS query with its latency."""
        lbls = {
            "transport": transport.lower(),
            "qtype": qtype.upper(),
            "rcode": rcode.upper(),
        }
        self.queries_total.inc(1, lbls)
        self.query_duration_seconds.observe(duration_sec, {"transport": transport.lower(), "rcode": rcode.upper()})

    def record_cache(self, state: str):
        self.cache_lookups_total.inc(1, {"state": state.lower()})

    def record_dnssec(self, status: str):
        self.dnssec_validations_total.inc(1, {"status": status.lower()})

    def record_xdp_drop(self, reason: str):
        self.xdp_packet_drops_total.inc(1, {"reason": reason.lower()})

    def record_threat(self, threat_type: str):
        self.threat_blocks_total.inc(1, {"threat_type": threat_type.lower()})

    def export_metrics_text(self) -> str:
        """Renders standard Prometheus exposition text (RFC 0.0.4)."""
        rendered_blocks = []
        for metric in self._all_metrics:
            rendered_blocks.extend(metric.render())
        return "\n".join(rendered_blocks) + "\n"

    def export_opentelemetry_json(self) -> Dict[str, Any]:
        """Renders OpenTelemetry Metrics JSON payload."""
        now_ns = int(time.time() * 1e9)
        return {
            "resource": {
                "attributes": [
                    {"key": "service.name", "value": {"stringValue": "focusdns"}},
                    {"key": "service.version", "value": {"stringValue": "3.0.0"}},
                ]
            },
            "scopeMetrics": [
                {
                    "scope": {"name": "focusdns.engine"},
                    "metrics": [
                        {
                            "name": m.name,
                            "description": m.help_text,
                            "data": {"timestamp": now_ns},
                        }
                        for m in self._all_metrics
                    ],
                }
            ],
        }


# Global singleton instance for server-wide metrics
_GLOBAL_EXPORTER: Optional[PrometheusExporter] = None
_EXPORTER_LOCK = threading.Lock()


def get_prometheus_exporter() -> PrometheusExporter:
    global _GLOBAL_EXPORTER
    with _EXPORTER_LOCK:
        if _GLOBAL_EXPORTER is None:
            _GLOBAL_EXPORTER = PrometheusExporter()
        return _GLOBAL_EXPORTER
