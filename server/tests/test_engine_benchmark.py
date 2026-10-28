"""
Unit and integration tests for FocusDNS Benchmark Suite & Load Harness.
"""

import unittest
from server.engine.benchmark_suite import (
    BenchmarkResult,
    BenchmarkSuite,
    SAMPLE_BENCHMARK_DOMAINS,
)
from server.engine.pipeline import DNSPipeline
from dnslib import DNSRecord


class TestBenchmarkSuiteSubsystem(unittest.TestCase):
    def test_benchmark_result_percentiles_and_qps(self):
        """Verify mathematical percentile calculations, throughput, and export formatting."""
        # Synthesize 100 queries from 1.0ms to 100.0ms
        latencies = [float(i) for i in range(1, 101)]
        res = BenchmarkResult(
            protocol="DNS-UDP",
            total_queries=100,
            successful_queries=98,
            failed_queries=2,
            duration_seconds=0.5,
            latencies_ms=latencies,
        )

        self.assertEqual(res.successful_queries, 98)
        self.assertEqual(res.failed_queries, 2)
        self.assertEqual(res.packet_loss_percent, 2.0)
        self.assertEqual(res.qps, 196.0)  # 98 / 0.5s = 196.0 QPS
        self.assertEqual(res.min_latency, 1.0)
        self.assertEqual(res.max_latency, 100.0)
        self.assertAlmostEqual(res.p50, 50.5, places=1)
        self.assertAlmostEqual(res.p95, 95.05, places=1)
        self.assertAlmostEqual(res.p99, 99.01, places=1)

        # Verify JSON and Markdown export
        d = res.to_dict()
        self.assertIn("throughput_qps", d)
        self.assertIn("latency_p99_ms", d)

        md = res.to_markdown()
        self.assertIn("DNS-UDP", md)
        self.assertIn("Throughput (QPS)", md)

    def test_pipeline_direct_in_memory_benchmark(self):
        """Verify in-memory pipeline load tester runs without network dependencies."""
        pipeline = DNSPipeline(enable_dnssec=False)
        # Pre-seed cache to ensure pure 0ms in-memory hits
        dummy_reply = DNSRecord.question("cached.local", "A").reply().pack()
        pipeline.cache.put("cached.local", 1, dummy_reply, ttl=300)

        suite = BenchmarkSuite()
        result = suite.run_pipeline_direct_benchmark(
            pipeline=pipeline,
            query_count=100,
            domains=["cached.local"],
        )

        self.assertEqual(result.total_queries, 100)
        self.assertGreater(result.qps, 150.0)  # Pure in-memory hit > 150 QPS
        self.assertEqual(result.successful_queries, 100)
        self.assertLess(result.avg_latency, 5.0)

    def test_xdp_and_geodns_benchmarks(self):
        """Verify eBPF/XDP filter and GeoDNS routing benchmark routines."""
        pipeline = DNSPipeline(enable_dnssec=False)
        suite = BenchmarkSuite()

        # Run XDP benchmark
        xdp_res = suite.run_xdp_benchmark(pipeline, packet_count=200)
        self.assertEqual(xdp_res.total_queries, 200)
        self.assertGreater(xdp_res.qps, 1000.0)

        # Run GeoDNS benchmark
        geo_res = suite.run_geodns_benchmark(pipeline, query_count=200)
        self.assertEqual(geo_res.total_queries, 200)
        self.assertGreater(geo_res.qps, 500.0)


if __name__ == "__main__":
    unittest.main()
