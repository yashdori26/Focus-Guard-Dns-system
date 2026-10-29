"""
Unit tests for Behavioral Temporal Threat Correlator & Kill-Chain Linker.
Validates sliding window aggregation, NXDOMAIN DGA burst detection, periodic beaconing,
quarantine recommendations, life-safety exemptions, and Conditional Whitelisting Law.
"""

import time
import unittest
from unittest.mock import patch
from server.ai.behavioral_threat_correlator import (
    BehavioralThreatCorrelator,
    HostThreatPosture,
    STAGE_BENIGN,
    STAGE_C2,
    STAGE_RECON,
    STAGE_EXFILTRATION,
    LIFE_SAFETY_DOMAINS
)


class TestBehavioralThreatCorrelator(unittest.TestCase):

    def setUp(self):
        self.correlator = BehavioralThreatCorrelator(window_seconds=60, quarantine_threshold=70.0)

    def test_benign_client_activity(self):
        """Single normal queries should maintain clean posture with 0 compromise index."""
        posture = self.correlator.record_query(
            client_ip="192.168.1.50",
            domain="google.com",
            rcode="NOERROR",
            risk_score=0.0
        )
        self.assertEqual(posture.compromise_index, 0.0)
        self.assertEqual(posture.kill_chain_stage, STAGE_BENIGN)
        self.assertFalse(posture.quarantine_recommended)

    def test_dga_nxdomain_burst_detection(self):
        """High burst of algorithmic queries failing with NXDOMAIN indicates C2 scanning."""
        client_ip = "192.168.1.110"
        for i in range(12):
            posture = self.correlator.record_query(
                client_ip=client_ip,
                domain=f"bad-dga-{i}.biz",
                rcode="NXDOMAIN",
                risk_score=85.0,
                threat_type="DGA_MALWARE"
            )

        self.assertGreaterEqual(posture.compromise_index, 70.0)
        self.assertEqual(posture.kill_chain_stage, STAGE_C2)
        self.assertGreaterEqual(posture.nxdomain_rate, 0.8)
        self.assertTrue(posture.quarantine_recommended)

    def test_periodic_c2_beaconing_detection(self):
        """Periodic query arrival times with low jitter must trigger beaconing detection."""
        client_ip = "192.168.1.120"
        base_time = time.time() - 30.0

        # Simulate heartbeat every 5.0 seconds (5 queries: 0s, 5s, 10s, 15s, 20s)
        for i in range(6):
            t = base_time + (i * 5.0)
            posture = self.correlator.record_query(
                client_ip=client_ip,
                domain="c2-listener.attacker.com",
                rcode="NOERROR",
                risk_score=45.0,
                threat_type="SUSPICIOUS",
                timestamp=t
            )

        self.assertIsNotNone(posture.beacon_period_seconds)
        self.assertAlmostEqual(posture.beacon_period_seconds, 5.0, delta=0.5)
        self.assertIsNotNone(posture.beacon_jitter)
        self.assertLessEqual(posture.beacon_jitter, 0.15)
        self.assertEqual(posture.kill_chain_stage, STAGE_C2)

    def test_exfiltration_stage_transition(self):
        """Queries tagged with EXFIL / TUNNEL transition host to STAGE_EXFILTRATION."""
        client_ip = "192.168.1.130"
        self.correlator.record_query(client_ip, "hexpayload1.tunnel.com", threat_type="DNS_TUNNEL_EXFIL", risk_score=85.0)
        posture = self.correlator.record_query(client_ip, "hexpayload2.tunnel.com", threat_type="DNS_TUNNEL_EXFIL", risk_score=90.0)

        self.assertEqual(posture.kill_chain_stage, STAGE_EXFILTRATION)
        self.assertGreaterEqual(posture.compromise_index, 60.0)

    def test_life_safety_exemption_never_counted_as_threat(self):
        """Emergency domains must NEVER increment threat counters or compromise index."""
        client_ip = "192.168.1.140"
        for exempt in LIFE_SAFETY_DOMAINS:
            posture = self.correlator.record_query(
                client_ip=client_ip,
                domain=exempt,
                rcode="NXDOMAIN",
                risk_score=99.0
            )
            self.assertEqual(posture.active_threats_count, 0)
            self.assertEqual(posture.compromise_index, 0.0)
            self.assertFalse(posture.quarantine_recommended)

    def test_conditional_whitelisting_law_when_idle(self):
        """Whitelisting works when idle and zeroes threat score for that domain."""
        self.assertFalse(self.correlator.is_locked)

        domain = "internal-heavy-dns.corp"
        success = self.correlator.add_whitelist(domain)
        self.assertTrue(success)
        self.assertIn(domain, self.correlator.get_whitelist())

        posture = self.correlator.record_query(
            client_ip="192.168.1.150",
            domain=domain,
            rcode="NXDOMAIN",
            risk_score=90.0,
            threat_type="BLOCKED"
        )
        self.assertEqual(posture.active_threats_count, 0)
        self.assertEqual(posture.compromise_index, 0.0)

        removed = self.correlator.remove_whitelist(domain)
        self.assertTrue(removed)

    def test_conditional_whitelisting_law_denial_when_locked(self):
        """Whitelisting must raise PermissionError ERROR_ACCESS_DENIED (5) when locked."""
        self.correlator.set_lock_state(is_locked=True, countdown_seconds=0)
        self.assertTrue(self.correlator.is_locked)

        with self.assertRaises(PermissionError) as ctx:
            self.correlator.add_whitelist("sample.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

        with self.assertRaises(PermissionError) as ctx:
            self.correlator.remove_whitelist("sample.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

    def test_conditional_whitelisting_law_denial_when_timer_active(self):
        """Whitelisting must raise PermissionError if countdown_seconds > 0 even if is_locked is False."""
        self.correlator.set_lock_state(is_locked=False, countdown_seconds=1500)
        self.assertTrue(self.correlator.is_locked)

        with self.assertRaises(PermissionError) as ctx:
            self.correlator.add_whitelist("exempt.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))


if __name__ == "__main__":
    import unittest.mock
    unittest.main()
