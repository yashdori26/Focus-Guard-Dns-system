"""
Unit Test Suite for FocusDNS Enterprise - Columnar Analytics Engine.
Validates DuckDB vectorized execution, FastColumnarStore fallback,
multi-tenant isolation, timeseries buckets, and latency quantiles.
"""

import time
import unittest
from server.enterprise.columnar_analytics import (
    ColumnarAnalyticsEngine,
    FastColumnarStore,
    DuckDbColumnarBackend,
    DnsQueryEvent,
    HAS_DUCKDB
)


class TestColumnarAnalytics(unittest.TestCase):

    def _generate_synthetic_events(self, count: int = 100, tenant_id: str = "org_acme") -> list:
        events = []
        now_us = int(time.time() * 1_000_000)
        domains = ["google.com", "github.com", "malware-c2.xyz", "phishing-bank.top", "internal.corp"]
        actions = ["ALLOWED", "ALLOWED", "BLOCKED_MALWARE", "BLOCKED_PHISHING", "ALLOWED"]
        threats = ["NONE", "NONE", "DGA_MALWARE", "PHISHING_ZERO_HOUR", "NONE"]
        categories = ["SEARCH", "DEVELOPMENT", "MALWARE_THREAT", "FINANCE", "PRODUCTIVITY_WORK"]

        for i in range(count):
            idx = i % len(domains)
            ev = DnsQueryEvent(
                timestamp_us=now_us + (i * 10_000),  # spaced by 10ms
                tenant_id=tenant_id,
                sub_tenant_id="unit_sales" if i % 2 == 0 else "unit_eng",
                device_id=f"dev_{i % 5}",
                client_ip=f"10.0.0.{10 + (i % 5)}",
                domain=domains[idx],
                qtype="A",
                rcode="NOERROR",
                action=actions[idx],
                threat_type=threats[idx],
                category=categories[idx],
                latency_us=1000 + (i * 20),
                bytes_transferred=64 + i
            )
            events.append(ev)
        return events

    def test_fast_columnar_store_roundtrip(self):
        """Validates FastColumnarStore memory fallback backend."""
        store = FastColumnarStore()
        events = self._generate_synthetic_events(count=50, tenant_id="tenant_alpha")
        store.insert_batch(events)
        self.assertEqual(store.total_count(), 50)

        start_us = events[0].timestamp_us - 1_000_000
        end_us = events[-1].timestamp_us + 1_000_000

        # Top domains
        top = store.query_top_domains("tenant_alpha", start_us, end_us, limit=5)
        self.assertGreater(len(top), 0)
        self.assertEqual(top[0]["domain"], "google.com")

        # Threat matrix
        matrix = store.query_threat_matrix("tenant_alpha", start_us, end_us)
        self.assertGreater(matrix["total_threats"], 0)
        self.assertIn("DGA_MALWARE", matrix["breakdown"])
        self.assertIn("PHISHING_ZERO_HOUR", matrix["breakdown"])

        # Latency quantiles
        lat = store.query_latency_quantiles("tenant_alpha", start_us, end_us)
        self.assertGreater(lat["p50"], 0)
        self.assertGreaterEqual(lat["p99"], lat["p50"])

    def test_multi_tenant_isolation(self):
        """Confirms queries against tenant A do not expose tenant B data."""
        engine = ColumnarAnalyticsEngine(use_duckdb=False)
        events_a = self._generate_synthetic_events(count=20, tenant_id="tenant_A")
        events_b = self._generate_synthetic_events(count=30, tenant_id="tenant_B")

        engine.log_batch(events_a)
        engine.log_batch(events_b)
        engine.flush()

        now_us = int(time.time() * 1_000_000)
        start_us = now_us - 100_000_000
        end_us = now_us + 100_000_000

        top_a = engine.get_top_domains("tenant_A", start_us, end_us)
        total_a = sum(d["query_count"] for d in top_a)
        self.assertEqual(total_a, 20)

        top_b = engine.get_top_domains("tenant_B", start_us, end_us)
        total_b = sum(d["query_count"] for d in top_b)
        self.assertEqual(total_b, 30)

        top_c = engine.get_top_domains("tenant_C_nonexistent", start_us, end_us)
        self.assertEqual(len(top_c), 0)
        engine.shutdown()

    @unittest.skipUnless(HAS_DUCKDB, "DuckDB not installed in environment")
    def test_duckdb_backend_execution(self):
        """Validates DuckDB vectorized execution backend."""
        duck_engine = ColumnarAnalyticsEngine(use_duckdb=True, db_path=":memory:")
        self.assertEqual(duck_engine.backend_type, "DUCKDB")

        events = self._generate_synthetic_events(count=100, tenant_id="tenant_enterprise")
        duck_engine.log_batch(events)
        duck_engine.flush()

        self.assertEqual(duck_engine.total_records(), 100)

        now_us = int(time.time() * 1_000_000)
        start_us = now_us - 100_000_000
        end_us = now_us + 100_000_000

        # Sub-tenant filter check
        ts_sales = duck_engine.get_timeseries(
            "tenant_enterprise", start_us, end_us, bucket_seconds=60, sub_tenant_id="unit_sales"
        )
        total_sales = sum(b["total_queries"] for b in ts_sales)
        self.assertEqual(total_sales, 50)

        # Quantiles check
        lat = duck_engine.get_latency_quantiles("tenant_enterprise", start_us, end_us)
        self.assertGreater(lat["p50"], 0)
        self.assertGreater(lat["p99"], lat["p50"])
        self.assertEqual(lat["count"], 100)

        # Category distribution
        cats = duck_engine.get_category_distribution("tenant_enterprise", start_us, end_us)
        self.assertIn("SEARCH", cats)
        self.assertIn("MALWARE_THREAT", cats)
        duck_engine.shutdown()

    def test_high_throughput_ingestion_performance(self):
        """Benchmarks ingestion and querying of 2,000 records under 250ms."""
        engine = ColumnarAnalyticsEngine(use_duckdb=HAS_DUCKDB)
        events = self._generate_synthetic_events(count=2000, tenant_id="bench_tenant")

        t0 = time.perf_counter()
        engine.log_batch(events)
        engine.flush()
        ingest_ms = (time.perf_counter() - t0) * 1000.0

        self.assertLess(ingest_ms, 250.0, f"Ingestion took {ingest_ms:.2f}ms")

        now_us = int(time.time() * 1_000_000)
        start_us = now_us - 100_000_000
        end_us = now_us + 100_000_000

        t1 = time.perf_counter()
        top = engine.get_top_domains("bench_tenant", start_us, end_us, limit=10)
        query_ms = (time.perf_counter() - t1) * 1000.0

        self.assertLess(query_ms, 50.0, f"Query took {query_ms:.2f}ms")
        self.assertEqual(sum(d["query_count"] for d in top), 2000)
        engine.shutdown()


if __name__ == "__main__":
    unittest.main()
