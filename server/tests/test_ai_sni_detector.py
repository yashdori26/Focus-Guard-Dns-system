"""
Unit Test Suite for FocusDNS AI Engine - Zero-Day SNI & TLS Threat Detector.
Validates zero-copy parsing, domain fronting detection, brand spoofing,
covert padding channels, and hardcoded life safety exemptions.
"""

import unittest
from server.ai.sni_threat_detector import (
    SniThreatDetector,
    ClientHelloInfo,
    SniThreatVerdict,
    TLS_RECORD_HANDSHAKE,
    TLS_HANDSHAKE_CLIENT_HELLO
)


class TestSniThreatDetector(unittest.TestCase):
    def setUp(self):
        self.detector = SniThreatDetector(high_risk_threshold=65.0)

    def test_synthetic_packet_generation_and_parsing(self):
        """Validates synthetic ClientHello builder and raw byte parser roundtrip."""
        packet = self.detector.build_client_hello(
            sni_hostname="secure.example.com",
            alpn_protocols=["h2", "http/1.1"],
            padding_len=64
        )
        self.assertGreater(len(packet), 50)
        self.assertEqual(packet[0], TLS_RECORD_HANDSHAKE)

        info = self.detector.parse_client_hello(packet)
        self.assertTrue(info.is_valid)
        self.assertEqual(info.sni_hostname, "secure.example.com")
        self.assertIn("h2", info.alpn_protocols)
        self.assertIn("http/1.1", info.alpn_protocols)
        self.assertEqual(info.padding_length, 64)

    def test_malformed_packets(self):
        """Malformed or non-TLS packets return invalid status without raising exceptions."""
        # Empty
        info = self.detector.parse_client_hello(b"")
        self.assertFalse(info.is_valid)

        # Random garbage
        garbage = b"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
        verdict = self.detector.analyze_packet(garbage)
        self.assertFalse(verdict.is_threat)
        self.assertEqual(verdict.threat_type, "MALFORMED_NON_TLS")

    def test_inviolable_life_safety_exemptions(self):
        """Emergency calling and critical OS push/update domains are unconditionally exempt."""
        exempt_domains = [
            "911.gov",
            "emergency.gov",
            "push.apple.com",
            "update.microsoft.com",
            "play.googleapis.com"
        ]
        for domain in exempt_domains:
            packet = self.detector.build_client_hello(sni_hostname=domain)
            verdict = self.detector.analyze_packet(packet, expected_dns_domain=domain)
            self.assertFalse(verdict.is_threat, f"Exempt domain {domain} was flagged as threat!")
            self.assertEqual(verdict.risk_score, 0.0)
            self.assertEqual(verdict.threat_type, "LIFE_SAFETY_EXEMPT")

    def test_domain_fronting_mismatch_detection(self):
        """Flags domain fronting when TLS SNI diverts from pre-resolved DNS query."""
        # Attacker queries legitimate CDN on DNS, but issues ClientHello for malicious target
        dns_query = "ajax.microsoft.com"
        sni_target = "c2-covert-gateway.xyz"

        packet = self.detector.build_client_hello(sni_hostname=sni_target)
        verdict = self.detector.analyze_packet(packet, expected_dns_domain=dns_query)

        self.assertTrue(verdict.is_threat)
        self.assertEqual(verdict.threat_type, "DOMAIN_FRONTING")
        self.assertGreaterEqual(verdict.risk_score, 65.0)
        self.assertTrue(any("domain_fronting_mismatch" in ind for ind in verdict.indicators))

    def test_brand_impersonation_in_sni(self):
        """Detects zero-hour credential phishing SNI targeting protected brands."""
        phish_sni = "paypal-security-login-verification.xyz"
        packet = self.detector.build_client_hello(sni_hostname=phish_sni)
        verdict = self.detector.analyze_packet(packet)

        self.assertTrue(verdict.is_threat)
        self.assertEqual(verdict.threat_type, "BRAND_IMPERSONATION")
        self.assertEqual(verdict.targeted_brand.lower(), "paypal")
        self.assertGreater(verdict.risk_score, 65.0)

    def test_legitimate_brand_in_sni(self):
        """Legitimate brand apex domain should not be flagged as brand impersonation."""
        legit_sni = "checkout.paypal.com"
        packet = self.detector.build_client_hello(sni_hostname=legit_sni)
        verdict = self.detector.analyze_packet(packet, expected_dns_domain="paypal.com")

        self.assertFalse(verdict.is_threat)
        self.assertEqual(verdict.threat_type, "CLEAN")

    def test_punycode_idn_homograph_in_sni(self):
        """Detects internationalized punycode obfuscation within SNI."""
        # xn--pple-43d.com -> аpple.com (Cyrillic 'а')
        puny_sni = "xn--pple-43d.com"
        packet = self.detector.build_client_hello(sni_hostname=puny_sni)
        verdict = self.detector.analyze_packet(packet)

        self.assertTrue(any("punycode_idn_sni" in ind for ind in verdict.indicators))
        self.assertGreaterEqual(verdict.risk_score, 35.0)

    def test_covert_channel_padding(self):
        """Detects abnormal TLS padding extension lengths used for data exfiltration."""
        packet = self.detector.build_client_hello(
            sni_hostname="internal-api.example.com",
            padding_len=1024
        )
        verdict = self.detector.analyze_packet(packet)
        self.assertTrue(any("covert_padding_1024_bytes" in ind for ind in verdict.indicators))

    def test_missing_sni_detection(self):
        """Handles ClientHello packets that completely omit the SNI extension."""
        packet = self.detector.build_client_hello(sni_hostname=None)
        verdict = self.detector.analyze_packet(packet)
        self.assertIn("missing_sni_extension", verdict.indicators)

    def test_high_throughput_inference_benchmark(self):
        """Validates zero-latency execution: parses and classifies 100 packets under 25ms."""
        import time
        packets = [
            self.detector.build_client_hello(f"host-{i}.example.com")
            for i in range(100)
        ]
        t0 = time.perf_counter()
        for p in packets:
            self.detector.analyze_packet(p, expected_dns_domain="example.com")
        duration_ms = (time.perf_counter() - t0) * 1000.0
        self.assertLess(duration_ms, 25.0, f"Benchmark took {duration_ms:.2f}ms for 100 packets")


if __name__ == "__main__":
    unittest.main()
