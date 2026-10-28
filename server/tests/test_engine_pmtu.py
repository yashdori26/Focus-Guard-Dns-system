"""
Unit & Integration Tests for FocusDNS PMTU & Truncation Subsystem
=================================================================
Validates:
  1. RFC 6891 EDNS buffer size negotiation and Flag Day 1232-byte clamping
  2. RFC 8900 IP fragmentation prevention via TC=1 truncation trigger
  3. TCP passthrough without truncation
  4. RFC 7766 TCP fallback connection pool, rate limiting, and idle timeout
"""

import unittest
from dnslib import DNSRecord, DNSQuestion, QTYPE, RR, A, TXT, EDNSOption
from server.engine.pmtu_manager import (
    PMTUConfig,
    PMTUManager,
    TCPFallbackManager,
    DEFAULT_FLAG_DAY_BUFFER_SIZE,
    LEGACY_UDP_MAX_SIZE,
)


class TestPMTUManager(unittest.TestCase):
    """Tests buffer size calculation and TC=1 truncation behavior."""

    def setUp(self):
        self.pmtu = PMTUManager()

    def test_legacy_udp_limit_without_edns(self):
        # Plain query without OPT record
        q = DNSRecord(q=DNSQuestion("example.com", QTYPE.A))
        limit = self.pmtu.determine_effective_payload_limit(q)
        self.assertEqual(limit, LEGACY_UDP_MAX_SIZE)

    def test_flag_day_clamping_with_oversized_edns(self):
        # Client advertises 4096 buffer size
        q = DNSRecord(q=DNSQuestion("example.com", QTYPE.A))
        # Add OPT record with rclass = 4096
        opt_rr = RR(".", QTYPE.OPT, rclass=4096, rdata=[])
        q.add_ar(opt_rr)

        limit = self.pmtu.determine_effective_payload_limit(q)
        # MUST be clamped to Flag Day standard 1232 bytes
        self.assertEqual(limit, DEFAULT_FLAG_DAY_BUFFER_SIZE)

    def test_small_response_not_truncated(self):
        q = DNSRecord(q=DNSQuestion("small.com", QTYPE.A))
        resp = q.reply()
        resp.add_answer(RR("small.com", QTYPE.A, rdata=A("192.0.2.1")))

        processed, was_truncated = self.pmtu.evaluate_response(q, resp, is_tcp=False)
        self.assertFalse(was_truncated)
        self.assertEqual(processed.header.tc, 0)
        self.assertEqual(len(processed.rr), 1)

    def test_massive_response_truncated_with_tc_flag(self):
        q = DNSRecord(q=DNSQuestion("big.com", QTYPE.TXT))
        resp = q.reply()
        # Add 30 large TXT records to exceed 1232 bytes
        for i in range(30):
            resp.add_answer(RR("big.com", QTYPE.TXT, rdata=TXT(f"chunk_{i}_" + "X" * 100)))

        wire_len = len(resp.pack())
        self.assertGreater(wire_len, DEFAULT_FLAG_DAY_BUFFER_SIZE)

        processed, was_truncated = self.pmtu.evaluate_response(q, resp, is_tcp=False)
        self.assertTrue(was_truncated)
        self.assertEqual(processed.header.tc, 1)

        stats = self.pmtu.get_stats()
        self.assertEqual(stats["truncation_events"], 1)

    def test_tcp_responses_bypass_truncation(self):
        q = DNSRecord(q=DNSQuestion("tcp.com", QTYPE.TXT))
        resp = q.reply()
        for i in range(25):
            resp.add_answer(RR("tcp.com", QTYPE.TXT, rdata=TXT(f"payload_{i}_" + "Z" * 100)))

        processed, was_truncated = self.pmtu.evaluate_response(q, resp, is_tcp=True)
        self.assertFalse(was_truncated)
        self.assertEqual(processed.header.tc, 0)


class TestTCPFallbackManager(unittest.TestCase):
    """Tests TCP connection limits, tracking, and stale client cleanup."""

    def setUp(self):
        self.tcp_mgr = TCPFallbackManager(max_concurrent=3, idle_timeout=0.1)

    def test_client_registration_and_limits(self):
        self.assertTrue(self.tcp_mgr.register_client("192.0.2.10"))
        self.assertTrue(self.tcp_mgr.register_client("192.0.2.11"))
        self.assertTrue(self.tcp_mgr.register_client("192.0.2.12"))

        # Exceeds max_concurrent of 3
        self.assertFalse(self.tcp_mgr.register_client("192.0.2.13"))
        stats = self.tcp_mgr.get_stats()
        self.assertEqual(stats["active_tcp_connections"], 3)
        self.assertEqual(stats["rejected_connections"], 1)

    def test_client_release_and_idle_eviction(self):
        import time
        self.tcp_mgr.register_client("192.0.2.20")
        self.tcp_mgr.release_client("192.0.2.20")
        stats = self.tcp_mgr.get_stats()
        self.assertEqual(stats["active_tcp_connections"], 0)

        # Idle eviction
        self.tcp_mgr.register_client("192.0.2.30")
        time.sleep(0.15)  # exceed idle_timeout of 0.1s
        # Next registration triggers purge of stale connections
        self.assertTrue(self.tcp_mgr.register_client("192.0.2.31"))
        stats = self.tcp_mgr.get_stats()
        self.assertEqual(stats["active_tcp_connections"], 1)


if __name__ == "__main__":
    unittest.main()
