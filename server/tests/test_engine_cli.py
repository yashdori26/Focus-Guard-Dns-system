"""
Unit and functional tests for FocusDNS CLI Engine command interface.
"""

import io
import sys
import unittest
from unittest.mock import patch

from server.engine.cli_engine import (
    cmd_status,
    cmd_threat_eval,
    cmd_dnssec_keys,
    cmd_health_check,
    main,
)


class TestCLIEngineSubsystem(unittest.TestCase):
    def test_cli_status_command(self):
        """Verify cli status command executes and outputs subsystem sections."""
        stdout_trap = io.StringIO()
        with patch("sys.stdout", stdout_trap):
            with patch("sys.argv", ["cli_engine", "status"]):
                main()

        output = stdout_trap.getvalue()
        self.assertIn("FOCUS-DNS MULTI-PROTOCOL ENGINE STATUS", output)
        self.assertIn("Radix Trie Matcher", output)
        self.assertIn("RFC 8767 Stale-While-Revalidate Cache", output)
        self.assertIn("Threat Analytics & Anomaly Shield", output)
        self.assertIn("DNS Response Rate Limiter", output)
        self.assertIn("Autonomous Upstream Resolver Pool", output)

    def test_cli_threat_eval_clean_domain(self):
        """Verify cli threat-eval outputs report for clean domain."""
        stdout_trap = io.StringIO()
        with patch("sys.stdout", stdout_trap):
            with patch("sys.argv", ["cli_engine", "threat-eval", "google.com"]):
                main()

        output = stdout_trap.getvalue()
        self.assertIn("THREAT ANALYTICS EVALUATION: google.com", output)
        self.assertIn("Final Action / Verdict: ALLOW", output)
        self.assertIn("Composite Risk Score:   0 / 100", output)

    def test_cli_threat_eval_dga_domain(self):
        """Verify cli threat-eval detects high-entropy DGA domains."""
        stdout_trap = io.StringIO()
        with patch("sys.stdout", stdout_trap):
            with patch("sys.argv", ["cli_engine", "threat-eval", "xqzpkjmvlkjhgfdwertyuiop.xyz"]):
                main()

        output = stdout_trap.getvalue()
        self.assertIn("Final Action / Verdict: BLOCK", output)
        self.assertIn("DGA Detected:           YES", output)

    def test_cli_dnssec_keys_command(self):
        """Verify cli dnssec-keys generates and prints KSK, ZSK, and DS records."""
        stdout_trap = io.StringIO()
        with patch("sys.stdout", stdout_trap):
            with patch("sys.argv", ["cli_engine", "dnssec-keys", "corp.local"]):
                main()

        output = stdout_trap.getvalue()
        self.assertIn("FOCUS-DNS DNSSEC CRYPTOGRAPHIC ANCHORS: corp.local", output)
        self.assertIn("[KSK] Key Tag:", output)
        self.assertIn("[ZSK] Key Tag:", output)
        self.assertIn("Delegation Signer (DS) Record", output)
        self.assertIn("Algorithm:   13 (ECDSA P-256 SHA-256)", output)

    def test_cli_health_check_command(self):
        """Verify cli health-check executes multi-protocol probe report."""
        stdout_trap = io.StringIO()
        with patch("sys.stdout", stdout_trap):
            with patch("sys.argv", ["cli_engine", "health-check"]):
                main()

        output = stdout_trap.getvalue()
        self.assertIn("ANYCAST MULTI-PROTOCOL HEALTH REPORT", output)
        self.assertIn("Overall Cluster Health:", output)
        self.assertIn("Anycast Route Ready:", output)


if __name__ == "__main__":
    unittest.main()
