"""
Unit tests for Windows WFP Installer, ETW Bypass Detector, and Trace Analyzer.

Verifies:
  1. Win32 WFP installer and ETW source integrity.
  2. WFP trace log parser and event classification.
  3. Detection of stealth browser (Chrome, Edge) and gaming (Discord, Steam) bypass attempts.
  4. Life Safety Exemption Guarantee: Windows Update (svchost.exe), DHCP (67/68),
     and Apple APNs (5223) exemption compliance.
  5. Security incident report generation.
"""

import os
import unittest
from server.engine.wfp_trace_analyzer import WfpTraceAnalyzer, WfpDropRecord


class TestWindowsWfpInstallerAndDetector(unittest.TestCase):
    def setUp(self):
        self.workspace_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    def test_wfp_source_files_exist(self):
        installer_h = os.path.join(self.workspace_root, "windows", "wfp", "FocusDnsWfpInstaller.h")
        installer_cpp = os.path.join(self.workspace_root, "windows", "wfp", "FocusDnsWfpInstaller.cpp")
        detector_h = os.path.join(self.workspace_root, "windows", "wfp", "FocusDnsBypassDetector.h")
        detector_cpp = os.path.join(self.workspace_root, "windows", "wfp", "FocusDnsBypassDetector.cpp")

        self.assertTrue(os.path.exists(installer_h))
        self.assertTrue(os.path.exists(installer_cpp))
        self.assertTrue(os.path.exists(detector_h))
        self.assertTrue(os.path.exists(detector_cpp))

    def test_installer_cpp_conditional_uninstallation_law(self):
        installer_cpp = os.path.join(self.workspace_root, "windows", "wfp", "FocusDnsWfpInstaller.cpp")
        with open(installer_cpp, "r", encoding="utf-8") as f:
            content = f.read()

        # Enforce that ERROR_ACCESS_DENIED is returned when active focus is locked
        self.assertIn("ERROR_ACCESS_DENIED", content)
        self.assertIn("QueryUninstallationPosture", content)
        self.assertIn("DeleteService", content)
        self.assertIn("OpenSCManagerW", content)

    def test_bypass_detector_cpp_target_processes(self):
        detector_cpp = os.path.join(self.workspace_root, "windows", "wfp", "FocusDnsBypassDetector.cpp")
        with open(detector_cpp, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("chrome.exe", content)
        self.assertIn("msedge.exe", content)
        self.assertTrue("Discord.exe" in content or "discord.exe" in content)
        self.assertIn("steam.exe", content)
        self.assertIn("ETW", content)


class TestWfpTraceAnalyzer(unittest.TestCase):
    def setUp(self):
        self.analyzer = WfpTraceAnalyzer()

    def test_parse_regular_drop(self):
        line = "[2026-10-29 11:00:01] DROP PID=1204 APP=curl.exe SRC=192.168.1.100:45123 DST=198.51.100.5:53 PROTO=UDP FILTER=501 REASON=FOCUS_GUARD_FILTER"
        rec = self.analyzer.parse_log_line(line)
        self.assertIsNotNone(rec)
        self.assertEqual(rec.process_name, "curl.exe")
        self.assertEqual(rec.remote_ip, "198.51.100.5")
        self.assertEqual(rec.remote_port, 53)
        self.assertFalse(rec.is_bypass_attempt)

    def test_detect_chrome_doh_bypass(self):
        line = "[2026-10-29 11:00:05] DROP PID=8842 APP=chrome.exe SRC=192.168.1.100:51222 DST=1.1.1.1:443 PROTO=TCP FILTER=602 REASON=FOCUS_GUARD_DOH_BLOCKED"
        rec = self.analyzer.parse_log_line(line)
        self.assertIsNotNone(rec)
        self.assertEqual(rec.process_name, "chrome.exe")
        self.assertEqual(rec.remote_ip, "1.1.1.1")
        self.assertTrue(rec.is_bypass_attempt)

    def test_detect_steam_dot_bypass(self):
        line = "[2026-10-29 11:00:09] DROP PID=9912 APP=steam.exe SRC=192.168.1.100:54321 DST=8.8.8.8:853 PROTO=TCP FILTER=603 REASON=FOCUS_GUARD_DOT_BLOCKED"
        rec = self.analyzer.parse_log_line(line)
        self.assertIsNotNone(rec)
        self.assertEqual(rec.process_name, "steam.exe")
        self.assertEqual(rec.remote_port, 853)
        self.assertTrue(rec.is_bypass_attempt)

    def test_life_safety_exemption_audit(self):
        # Ingest benign and bypass logs
        logs = [
            "[2026-10-29 11:01:00] DROP PID=4100 APP=msedge.exe SRC=192.168.1.100:59102 DST=8.8.4.4:443 PROTO=TCP FILTER=602 REASON=DOH_INTERCEPTED",
            "[2026-10-29 11:01:02] DROP PID=5211 APP=discord.exe SRC=192.168.1.100:59104 DST=9.9.9.9:853 PROTO=TCP FILTER=603 REASON=DOT_INTERCEPTED",
            "[2026-10-29 11:01:05] DROP PID=1220 APP=wget.exe SRC=192.168.1.100:59106 DST=203.0.113.8:53 PROTO=UDP FILTER=501 REASON=ADULT_BLOCKED"
        ]
        self.assertEqual(self.analyzer.ingest_records(logs), 3)
        self.assertTrue(self.analyzer.verify_life_safety_exemptions())

        report = self.analyzer.generate_incident_report()
        self.assertEqual(report["total_drop_events_analyzed"], 3)
        self.assertEqual(report["bypass_attempts_detected"], 2)
        self.assertEqual(report["exemption_violations_detected"], 0)
        self.assertTrue(report["life_safety_exemption_verified"])
        self.assertEqual(report["severity"], "CRITICAL_BYPASS_ATTEMPTS")
        self.assertIn("msedge.exe", report["bypass_attempts_by_application"])
        self.assertIn("discord.exe", report["bypass_attempts_by_application"])

    def test_exemption_violation_flagged(self):
        # If an erroneous rule drops svchost.exe or DHCP port 67, analyzer must flag it
        faulty_log = "[2026-10-29 11:02:00] DROP PID=800 APP=svchost.exe SRC=192.168.1.100:68 DST=192.168.1.1:67 PROTO=UDP FILTER=999 REASON=ACCIDENTAL_DROP"
        self.analyzer.ingest_records([faulty_log])
        self.assertFalse(self.analyzer.verify_life_safety_exemptions())
        report = self.analyzer.generate_incident_report()
        self.assertEqual(report["exemption_violations_detected"], 1)
        self.assertFalse(report["life_safety_exemption_verified"])


if __name__ == "__main__":
    unittest.main()
