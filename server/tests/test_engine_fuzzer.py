"""
Unit & Integration Tests for FocusDNS Wire Fuzzing & Cyclic Loop Defense Subsystem
==================================================================================
Validates:
  1. RFC 1035 Section 4.1.4 cyclic compression pointer loop detection (CVE-2000-0381)
  2. WireMutationEngine generation of self-loops, mutual loops, bit-flips, and overflows
  3. Safe exception containment without fatal crashes
  4. Automated fuzzing harness executing 200 hostile mutations with zero crashes
"""

import unittest
from dnslib import DNSRecord, DNSQuestion, QTYPE
from server.engine.dns_fuzzer import (
    LoopVulnerabilityDetector,
    WireMutationEngine,
    DNSFuzzHarness,
)


class TestLoopVulnerabilityDetector(unittest.TestCase):
    """Tests CVE-2000-0381 infinite pointer loop detection."""

    def setUp(self):
        # Base valid wire query for example.com
        self.valid_record = DNSRecord(q=DNSQuestion("example.com", QTYPE.A))
        self.base_wire = self.valid_record.pack()

    def test_valid_wire_not_flagged_as_loop(self):
        is_cyclic, _ = LoopVulnerabilityDetector.inspect_pointer_loops(self.base_wire)
        self.assertFalse(is_cyclic)

    def test_self_referential_pointer_loop_detected(self):
        mutated = WireMutationEngine.inject_cyclic_pointer_loop(self.base_wire, target_offset=12)
        is_cyclic, chain = LoopVulnerabilityDetector.inspect_pointer_loops(mutated, offset=12)
        self.assertTrue(is_cyclic)
        self.assertIn(12, chain)

    def test_mutual_pointer_loop_detected(self):
        mutated = WireMutationEngine.inject_mutual_pointer_loop(self.base_wire)
        is_cyclic, chain = LoopVulnerabilityDetector.inspect_pointer_loops(mutated, offset=12)
        self.assertTrue(is_cyclic)
        self.assertIn(14, chain)
        self.assertIn(12, chain)


class TestWireMutationEngine(unittest.TestCase):
    """Tests wire packet mutation generators."""

    def setUp(self):
        self.base_wire = DNSRecord(q=DNSQuestion("test.org", QTYPE.AAAA)).pack()

    def test_bit_flip_mutation(self):
        mutated = WireMutationEngine.inject_bit_flips(self.base_wire, flip_ratio=0.1, seed=123)
        self.assertEqual(len(mutated), len(self.base_wire))
        self.assertNotEqual(mutated, self.base_wire)

    def test_label_length_overflow(self):
        mutated = WireMutationEngine.inject_label_length_overflow(self.base_wire, offset=12)
        # Offset 12 must be 64 (illegal RFC 1035 label length > 63)
        self.assertEqual(mutated[12], 64)

    def test_truncate_wire(self):
        cut = WireMutationEngine.truncate_wire(self.base_wire, cut_length=8)
        self.assertEqual(len(cut), 8)


class TestDNSFuzzHarness(unittest.TestCase):
    """Tests resilience harness against live DNSRecord.parse."""

    def test_fuzz_cycle_zero_crashes(self):
        base_wire = DNSRecord(q=DNSQuestion("fuzz-target.net", QTYPE.A)).pack()

        def safe_parser(wire: bytes):
            # Safe wrapper imitating engine ingress
            is_loop, _ = LoopVulnerabilityDetector.inspect_pointer_loops(wire)
            if is_loop:
                raise ValueError("Dropped cyclic compression pointer loop")
            return DNSRecord.parse(wire)

        harness = DNSFuzzHarness(target_parser=safe_parser)
        stats = harness.run_fuzz_cycle(base_wire, iterations=200, seed=999)

        self.assertEqual(stats["total_fuzz_iterations"], 200)
        self.assertEqual(stats["fatal_crashes"], 0)
        self.assertTrue(stats["zero_crash_guarantee_met"])
        self.assertGreater(stats["loops_neutralized"], 10)
        self.assertGreater(stats["safe_exceptions_handled"], 10)


if __name__ == "__main__":
    unittest.main()
