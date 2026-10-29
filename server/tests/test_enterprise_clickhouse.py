"""
FocusDNS Enterprise Engine - ClickHouse Columnar Analytics Unit Tests.

Tests:
  1. ClickHouse wire format codecs (TabSeparated, JSONEachRow, TabSeparated parser).
  2. T-Digest streaming quantile estimation (p50, p90, p95, p99) over high volume distributions.
  3. Count-Min Sketch frequency estimation with decaying memory for Top-K domains.
  4. Rolling window z-score anomaly detection for DNS query volume spikes.
  5. Vectorized micro-batching and window moving average aggregations.
"""

import math
import random
import time
import unittest

from server.enterprise.columnar_analytics import DnsQueryEvent
from server.enterprise.clickhouse_analytics import (
    ClickHouseAnalyticsEngine,
    ClickHouseWireCodec,
    TDigest,
    TDigestCentroid,
    CountMinSketch,
    RollingWindowAnomalyDetector,
    get_clickhouse_engine,
)


class TestTDigestQuantiles(unittest.TestCase):
    """Verifies precision and bounds of the T-Digest streaming quantile estimator."""

    def test_empty_tdigest(self):
        td = TDigest()
        self.assertEqual(td.quantile(0.5), 0.0)
        self.assertEqual(td.quantile(0.99), 0.0)

    def test_single_value(self):
        td = TDigest()
        td.add(42.0)
        self.assertEqual(td.quantile(0.0), 42.0)
        self.assertEqual(td.quantile(0.5), 42.0)
        self.assertEqual(td.quantile(1.0), 42.0)

    def test_uniform_distribution_quantiles(self):
        td = TDigest(delta=0.01, max_centroids=100)
        # Add 1,000 values from 0.0 to 1000.0 uniformly
        values = [float(i) for i in range(1001)]
        td.add_batch(values)

        p50 = td.quantile(0.50)
        p90 = td.quantile(0.90)
        p95 = td.quantile(0.95)
        p99 = td.quantile(0.99)

        # Expected: p50 ~ 500, p90 ~ 900, p95 ~ 950, p99 ~ 990 within reasonable delta
        self.assertAlmostEqual(p50, 500.0, delta=25.0)
        self.assertAlmostEqual(p90, 900.0, delta=25.0)
        self.assertAlmostEqual(p95, 950.0, delta=25.0)
        self.assertAlmostEqual(p99, 990.0, delta=25.0)

    def test_add_batch_and_compression(self):
        td = TDigest(delta=0.02, max_centroids=50)
        # Add large dataset triggering compression multiple times
        batch = [random.expovariate(0.1) for _ in range(5000)]
        td.add_batch(batch)
        self.assertLessEqual(len(td.centroids), 200)
        self.assertGreater(td.quantile(0.5), 0.0)
        self.assertGreaterEqual(td.quantile(0.99), td.quantile(0.5))


class TestCountMinSketch(unittest.TestCase):
    """Verifies heavy hitter Top-K domain frequency tracking."""

    def test_frequency_estimation(self):
        cms = CountMinSketch(width=500, depth=5, decay_factor=0.95)

        for _ in range(150):
            cms.add("google.com")
        for _ in range(50):
            cms.add("github.com")
        for _ in range(5):
            cms.add("rare-domain.org")

        self.assertGreaterEqual(cms.estimate("google.com"), 150)
        self.assertGreaterEqual(cms.estimate("github.com"), 50)
        self.assertGreaterEqual(cms.estimate("rare-domain.org"), 5)
        # Estimate should never underestimate true frequency
        self.assertLessEqual(cms.estimate("google.com"), 170)

        # Test Top-K retrieval
        top = cms.get_top_k(2)
        self.assertEqual(len(top), 2)
        self.assertEqual(top[0][0], "google.com")
        self.assertEqual(top[1][0], "github.com")

    def test_decay_memory(self):
        cms = CountMinSketch(width=200, depth=4, decay_factor=0.5)
        for _ in range(100):
            cms.add("burst.com")

        initial_count = cms.estimate("burst.com")
        self.assertGreaterEqual(initial_count, 100)

        # Apply decay
        cms.decay()
        decayed_count = cms.estimate("burst.com")
        self.assertEqual(decayed_count, initial_count // 2)


class TestRollingAnomalyDetector(unittest.TestCase):
    """Verifies rolling window z-score anomaly detection for DNS velocity spikes."""

    def test_stable_traffic_no_anomaly(self):
        detector = RollingWindowAnomalyDetector(window_size=20, z_threshold=3.0)
        # Stable baseline around 100 qps with minor variance
        for _ in range(30):
            is_anomaly, z_score, mean = detector.record_sample(100.0 + random.uniform(-2.0, 2.0))
            self.assertFalse(is_anomaly)

    def test_sudden_velocity_spike_triggers_anomaly(self):
        detector = RollingWindowAnomalyDetector(window_size=20, z_threshold=3.0)
        # Warmup baseline
        for _ in range(25):
            detector.record_sample(50.0 + random.uniform(-1.0, 1.0))

        # Sudden 10x DDoS flood spike
        is_anomaly, z_score, mean = detector.record_sample(500.0)
        self.assertTrue(is_anomaly)
        self.assertGreater(z_score, 3.0)


class TestClickHouseWireCodecs(unittest.TestCase):
    """Verifies parsing and serialization of ClickHouse wire formats."""

    def setUp(self):
        self.event1 = DnsQueryEvent(
            timestamp_us=1761700000000000,
            tenant_id="org_springfield",
            sub_tenant_id="unit_lincoln_high",
            device_id="chromebook_01",
            client_ip="192.168.1.101",
            domain="khanacademy.org",
            qtype="A",
            rcode="NOERROR",
            action="ALLOWED",
            threat_type="",
            category="EDUCATION",
            latency_us=1250,
            bytes_transferred=128,
        )
        self.event2 = DnsQueryEvent(
            timestamp_us=1761700001000000,
            tenant_id="org_springfield",
            sub_tenant_id="unit_lincoln_high",
            device_id="chromebook_02",
            client_ip="192.168.1.102",
            domain="phishing-login.com",
            qtype="A",
            rcode="NXDOMAIN",
            action="BLOCKED",
            threat_type="PHISHING",
            category="SECURITY_RISK",
            latency_us=450,
            bytes_transferred=64,
        )

    def test_serialize_tab_separated(self):
        output = ClickHouseWireCodec.serialize_tab_separated([self.event1, self.event2])
        lines = output.strip().split("\n")
        self.assertEqual(len(lines), 2)
        fields0 = lines[0].split("\t")
        self.assertEqual(fields0[0], "1761700000000000")
        self.assertEqual(fields0[1], "org_springfield")
        self.assertEqual(fields0[5], "khanacademy.org")
        self.assertEqual(fields0[8], "ALLOWED")

    def test_parse_tab_separated(self):
        raw = (
            "timestamp_us\ttenant_id\tdomain\tlatency_us\n"
            "UInt64\tString\tString\tUInt32\n"
            "1761700000000000\torg_springfield\tkhanacademy.org\t1250\n"
        )
        parsed = ClickHouseWireCodec.parse_tab_separated(raw)
        self.assertEqual(len(parsed), 1)
        row = parsed[0]
        self.assertEqual(row["tenant_id"], "org_springfield")
        self.assertEqual(row["domain"], "khanacademy.org")
        self.assertEqual(row["latency_us"], 1250)

    def test_serialize_json_each_row(self):
        output = ClickHouseWireCodec.serialize_json_each_row([self.event1])
        self.assertIn('"domain": "khanacademy.org"', output)
        self.assertIn('"tenant_id": "org_springfield"', output)


class TestClickHouseEngineIngestAndAggregations(unittest.TestCase):
    """Verifies end-to-end ClickHouse bulk ingestion and analytics metrics."""

    def setUp(self):
        self.engine = ClickHouseAnalyticsEngine(flush_interval_sec=10.0)

    def tearDown(self):
        self.engine.shutdown()

    def test_ingest_and_query_metrics(self):
        events = []
        now_us = int(time.time() * 1_000_000)
        for i in range(100):
            events.append(
                DnsQueryEvent(
                    timestamp_us=now_us + (i * 10_000),
                    tenant_id="org_springfield",
                    sub_tenant_id="unit_lincoln_high",
                    device_id=f"device_{i % 5}",
                    client_ip=f"192.168.1.{100 + (i % 5)}",
                    domain="google.com" if i % 2 == 0 else "wikipedia.org",
                    qtype="A",
                    rcode="NOERROR",
                    action="ALLOWED" if i % 10 != 0 else "BLOCKED",
                    threat_type="" if i % 10 != 0 else "SUSPICIOUS",
                    category="GENERAL",
                    latency_us=500 + (i * 20),
                    bytes_transferred=128,
                )
            )

        enqueued = self.engine.log_batch(events)
        self.assertEqual(enqueued, 100)

        # Force synchronous flush
        flushed = self.engine.flush()
        self.assertEqual(flushed, 100)

        # Verify quantiles
        quantiles = self.engine.query_latency_quantiles("org_springfield")
        self.assertEqual(quantiles["count"], 100)
        self.assertGreater(quantiles["p50"], 0)
        self.assertGreater(quantiles["p99"], quantiles["p50"])

        # Verify top domains
        top = self.engine.query_top_domains("org_springfield", limit=5)
        self.assertTrue(any(d["domain"] == "google.com" for d in top))

        # Verify operational metrics
        metrics = self.engine.get_metrics()
        self.assertEqual(metrics["total_ingested"], 100)
        self.assertEqual(metrics["total_records"], 100)

        # Verify anomaly evaluation
        anomaly_res = self.engine.check_traffic_anomaly("org_springfield", 15.0)
        self.assertIn("is_anomaly", anomaly_res)
        self.assertIn("z_score", anomaly_res)


if __name__ == "__main__":
    unittest.main()
