"""
Unit Tests for focusguard-ai Threat Hunting CLI
Tests CLI subcommands: hunt, homograph, dga, categorize, lock, unlock, whitelist, and benchmark.
"""

import unittest
import sys
import os
from io import StringIO
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from server.ai import threat_hunting_cli


class TestThreatHuntingCli(unittest.TestCase):
    """Verifies CLI arguments and subcommand execution."""

    def test_cli_hunt_benign(self):
        with patch("sys.argv", ["focusguard-ai", "hunt", "google.com"]):
            with patch("sys.stdout", new=StringIO()) as fake_out:
                threat_hunting_cli.main()
                output = fake_out.getvalue()
                self.assertIn("FocusDNS AI Threat Hunt", output)
                self.assertIn("google.com", output)
                self.assertIn("Threat Detected:    NO", output)

    def test_cli_hunt_threat(self):
        with patch("sys.argv", ["focusguard-ai", "hunt", "\u0430pple.com"]):
            with patch("sys.stdout", new=StringIO()) as fake_out:
                threat_hunting_cli.main()
                output = fake_out.getvalue()
                self.assertIn("Threat Detected:    YES", output)
                self.assertIn("HOMOGRAPH", output)

    def test_cli_homograph_inspection(self):
        with patch("sys.argv", ["focusguard-ai", "homograph", "paypa1.com"]):
            with patch("sys.stdout", new=StringIO()) as fake_out:
                threat_hunting_cli.main()
                output = fake_out.getvalue()
                self.assertIn("IDN Homograph & Typosquat Analysis", output)
                self.assertIn("paypal", output)

    def test_cli_dga_classification(self):
        with patch("sys.argv", ["focusguard-ai", "dga", "bcdfghjklmnpqrstvwxyz.org"]):
            with patch("sys.stdout", new=StringIO()) as fake_out:
                threat_hunting_cli.main()
                output = fake_out.getvalue()
                self.assertIn("DGA Neural Classifier", output)
                self.assertIn("DGA Malware C2:     YES", output)

    def test_cli_categorize(self):
        with patch("sys.argv", ["focusguard-ai", "categorize", "steampowered.com"]):
            with patch("sys.stdout", new=StringIO()) as fake_out:
                threat_hunting_cli.main()
                output = fake_out.getvalue()
                self.assertIn("Multi-Class Domain Categorization", output)
                self.assertIn("GAMING", output)

    def test_cli_lock_and_conditional_whitelisting(self):
        """Tests locking focus mode and testing that whitelist attempt fails with code 5."""
        # 1. Unlock
        with patch("sys.argv", ["focusguard-ai", "unlock", "--force"]):
            with patch("sys.stdout", new=StringIO()):
                threat_hunting_cli.main()

        # 2. Whitelist while idle should succeed
        with patch("sys.argv", ["focusguard-ai", "whitelist", "safe-site.com"]):
            with patch("sys.stdout", new=StringIO()) as fake_out:
                threat_hunting_cli.main()
                self.assertIn("added to whitelist with 0 friction", fake_out.getvalue())

        # 3. Lock focus mode
        with patch("sys.argv", ["focusguard-ai", "lock", "1800"]):
            with patch("sys.stdout", new=StringIO()) as fake_out:
                threat_hunting_cli.main()
                self.assertIn("Active Focus lockdown enabled", fake_out.getvalue())

        # 4. Whitelist while locked must exit with code 5
        with patch("sys.argv", ["focusguard-ai", "whitelist", "distraction.com"]):
            with patch("sys.stdout", new=StringIO()) as fake_out:
                with self.assertRaises(SystemExit) as ctx:
                    threat_hunting_cli.main()
                self.assertEqual(ctx.exception.code, 5)
                self.assertIn("Access Denied", fake_out.getvalue())

        # 5. Clean unlock
        with patch("sys.argv", ["focusguard-ai", "unlock", "--force"]):
            with patch("sys.stdout", new=StringIO()):
                threat_hunting_cli.main()

    def test_cli_benchmark(self):
        with patch("sys.argv", ["focusguard-ai", "benchmark", "--count", "500"]):
            with patch("sys.stdout", new=StringIO()) as fake_out:
                threat_hunting_cli.main()
                output = fake_out.getvalue()
                self.assertIn("Benchmark Results", output)
                self.assertIn("Total Queries:      500", output)
                self.assertIn("Throughput:", output)


if __name__ == "__main__":
    unittest.main()
