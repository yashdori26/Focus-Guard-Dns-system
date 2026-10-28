"""
Unit & Integration Tests for FocusDNS Prometheus & OpenTelemetry Subsystem
==========================================================================
Validates:
  1. Prometheus Exposition Format 0.0.4 text rendering
  2. Dimensional Counter, Gauge, and Histogram metrics
  3. Metric label formatting and sorting
  4. Query duration observation across latency buckets
  5. OpenTelemetry Metrics v1.0 JSON export
"""

import unittest
from server.engine.telemetry_prometheus import (
    format_labels,
    CounterMetric,
    GaugeMetric,
    HistogramMetric,
    PrometheusExporter,
    get_prometheus_exporter,
)


class TestMetricPrimitives(unittest.TestCase):
    """Tests Counter, Gauge, and Histogram primitives."""

    def test_format_labels(self):
        lbls = {"transport": "udp", "qtype": "A"}
        rendered = format_labels(lbls)
        self.assertEqual(rendered, '{qtype="A",transport="udp"}')
        self.assertEqual(format_labels(None), "")

    def test_counter_metric(self):
        cnt = CounterMetric("test_total", "Test counter")
        cnt.inc(1, {"env": "prod"})
        cnt.inc(2, {"env": "prod"})
        cnt.inc(5, {"env": "dev"})

        self.assertEqual(cnt.get({"env": "prod"}), 3.0)
        self.assertEqual(cnt.get({"env": "dev"}), 5.0)

        with self.assertRaises(ValueError):
            cnt.inc(-1)

        rendered = "\n".join(cnt.render())
        self.assertIn("# HELP test_total Test counter", rendered)
        self.assertIn("# TYPE test_total counter", rendered)
        self.assertIn('test_total{env="prod"} 3.0', rendered)

    def test_gauge_metric(self):
        gauge = GaugeMetric("test_gauge", "Test gauge")
        gauge.set(10.5, {"node": "east"})
        gauge.inc(2.0, {"node": "east"})
        gauge.dec(1.5, {"node": "east"})
        self.assertEqual(gauge.get({"node": "east"}), 11.0)

        rendered = "\n".join(gauge.render())
        self.assertIn("# TYPE test_gauge gauge", rendered)
        self.assertIn('test_gauge{node="east"} 11.0', rendered)

    def test_histogram_metric(self):
        hist = HistogramMetric("test_latency_seconds", "Latency test", buckets=(0.01, 0.05, 0.1))
        hist.observe(0.005, {"code": "200"})
        hist.observe(0.025, {"code": "200"})
        hist.observe(0.08, {"code": "200"})
        hist.observe(0.5, {"code": "200"})

        rendered = "\n".join(hist.render())
        self.assertIn("# TYPE test_latency_seconds histogram", rendered)
        self.assertIn('test_latency_seconds_bucket{code="200",le="0.01"} 1', rendered)
        self.assertIn('test_latency_seconds_bucket{code="200",le="0.05"} 2', rendered)
        self.assertIn('test_latency_seconds_bucket{code="200",le="0.1"} 3', rendered)
        self.assertIn('test_latency_seconds_bucket{code="200",le="+Inf"} 4', rendered)
        self.assertIn('test_latency_seconds_count{code="200"} 4', rendered)


class TestPrometheusExporter(unittest.TestCase):
    """Tests full PrometheusExporter registry and OpenTelemetry exporter."""

    def setUp(self):
        self.exporter = PrometheusExporter()

    def test_record_query_and_metrics_text(self):
        self.exporter.record_query("udp", "A", "NOERROR", 0.002)
        self.exporter.record_query("dot", "AAAA", "NXDOMAIN", 0.015)
        self.exporter.record_cache("hit")
        self.exporter.record_dnssec("secure")
        self.exporter.record_xdp_drop("rate_limit")
        self.exporter.record_threat("dga")

        text = self.exporter.export_metrics_text()
        self.assertIn('focusdns_queries_total{qtype="A",rcode="NOERROR",transport="udp"} 1.0', text)
        self.assertIn('focusdns_queries_total{qtype="AAAA",rcode="NXDOMAIN",transport="dot"} 1.0', text)
        self.assertIn('focusdns_cache_lookups_total{state="hit"} 1.0', text)
        self.assertIn('focusdns_dnssec_validations_total{status="secure"} 1.0', text)
        self.assertIn('focusdns_xdp_packet_drops_total{reason="rate_limit"} 1.0', text)
        self.assertIn('focusdns_threat_blocks_total{threat_type="dga"} 1.0', text)
        self.assertIn("focusdns_query_duration_seconds_bucket", text)

    def test_opentelemetry_json_structure(self):
        data = self.exporter.export_opentelemetry_json()
        self.assertIn("resource", data)
        self.assertIn("scopeMetrics", data)
        self.assertEqual(data["resource"]["attributes"][0]["value"]["stringValue"], "focusdns")
        self.assertGreaterEqual(len(data["scopeMetrics"][0]["metrics"]), 5)

    def test_global_singleton(self):
        exp1 = get_prometheus_exporter()
        exp2 = get_prometheus_exporter()
        self.assertIs(exp1, exp2)


if __name__ == "__main__":
    unittest.main()
