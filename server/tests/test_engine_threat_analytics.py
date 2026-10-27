"""
Unit and integration tests for FocusDNS Threat Analytics & Anomaly Detection Subsystem.
"""

import unittest
from server.engine.threat_analytics import (
    calculate_shannon_entropy,
    calculate_consonant_ratio,
    calculate_digit_ratio,
    is_base64_or_hex_pattern,
    ThreatAnalyticsEngine,
    ThreatVerdict,
)


class TestThreatAnalyticsSubsystem(unittest.TestCase):
    def setUp(self):
        self.engine = ThreatAnalyticsEngine(
            entropy_threshold=3.65,
        )

    def test_shannon_entropy_calculation(self):
        """Verify Shannon entropy accurately distinguishes natural words from random DGA strings."""
        natural_word = "wikipedia"
        dga_string = "xqzpkjmvlkjhgfdwertyuiop"

        h_natural = calculate_shannon_entropy(natural_word)
        h_dga = calculate_shannon_entropy(dga_string)

        self.assertLess(h_natural, 3.2)
        self.assertGreater(h_dga, 3.8)

    def test_consonant_and_digit_ratios(self):
        """Verify structural lexical analysis metrics."""
        no_vowels = "bcdfghjklmnpqrstvwxyz"
        all_vowels = "aeiouaeiou"
        self.assertEqual(calculate_consonant_ratio(no_vowels), 1.0)
        self.assertEqual(calculate_consonant_ratio(all_vowels), 0.0)

        numeric = "sub12345678"
        self.assertGreater(calculate_digit_ratio(numeric), 0.5)

    def test_base64_and_hex_tunneling_patterns(self):
        """Verify detection of hex and encoded exfiltration payloads."""
        hex_payload = "4a6f686e20446f652053656372657421"  # 32 chars hex
        self.assertTrue(is_base64_or_hex_pattern(hex_payload))

        normal_label = "contact-us"
        self.assertFalse(is_base64_or_hex_pattern(normal_label))

    def test_trusted_apex_domain_immunity(self):
        """Verify whitelisted major apex domains receive zero false positives."""
        trusted_domains = ["google.com", "api.github.com", "cdn.cloudflare.com", "aws.amazon.com"]
        for domain in trusted_domains:
            verdict = self.engine.analyze_domain(domain, "A", "10.0.0.1")
            self.assertEqual(verdict.verdict, ThreatVerdict.ALLOW)
            self.assertEqual(verdict.risk_score, 0)

    def test_dga_domain_detection_and_blocking(self):
        """Verify high entropy DGA domains are flagged and scored above block threshold."""
        dga_domain = "qx7z9k2m4v8p1w3j5t6y.xyz"
        verdict = self.engine.analyze_domain(dga_domain, "A", "192.168.1.50")
        self.assertTrue(verdict.is_dga)
        self.assertGreaterEqual(verdict.risk_score, 60)
        self.assertEqual(verdict.verdict, ThreatVerdict.BLOCK)
        self.assertTrue(any("Entropy" in r or "TLD" in r for r in verdict.reasons))

    def test_dns_tunneling_label_length_and_burst(self):
        """Verify detection of DNS tunneling exfiltration payloads."""
        # Very long label with hex data
        tunneling_domain = (
            "4a6f686e20446f652053656372657420546f6b656e203132333435363738.exfil.attacker.net"
        )
        verdict = self.engine.analyze_domain(tunneling_domain, "TXT", "192.168.1.50")
        self.assertTrue(verdict.is_tunneling)
        self.assertGreaterEqual(verdict.risk_score, 60)
        self.assertEqual(verdict.verdict, ThreatVerdict.BLOCK)

    def test_fast_flux_network_detection(self):
        """Verify fast-flux detection when domain resolves to many distinct IPs across /16 subnets with low TTL."""
        domain = "suspicious-flux-botnet.cc"

        # Record resolutions across 5 different /16 subnets with TTL <= 90
        ip_pool = [
            "198.51.100.1",
            "198.52.100.2",
            "198.53.100.3",
            "198.54.100.4",
            "198.55.100.5",
            "198.56.100.6",
        ]
        for ip in ip_pool:
            self.engine.record_resolution(domain, [ip], ttl=30)

        # Analyze domain now that fast-flux history exists
        verdict = self.engine.analyze_domain(domain, "A", "192.168.1.50")
        self.assertTrue(verdict.is_fast_flux)
        self.assertTrue(any("Fast-Flux" in r for r in verdict.reasons))

    def test_threat_analytics_telemetry_counters(self):
        """Verify engine metrics and counters reflect analysis history."""
        self.engine.analyze_domain("clean-domain.org", "A", "127.0.0.1")
        stats = self.engine.get_stats()
        self.assertIn("total_analyzed", stats)
        self.assertIn("dga_detected", stats)
        self.assertIn("tunneling_detected", stats)
        self.assertIn("fast_flux_detected", stats)
        self.assertIn("high_risk_blocked", stats)
        self.assertGreaterEqual(stats["total_analyzed"], 1)


if __name__ == "__main__":
    unittest.main()
