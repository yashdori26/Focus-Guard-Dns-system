"""
Unit Tests for Router AI Interceptor & Threat Sync Agent
Verifies gateway packet interception, LAN device telemetry logging, Life-Safety bypass,
Conditional Whitelisting Law on routers, and cryptographic HMAC model updates.
"""

import unittest
import sys
import os
import tempfile
import shutil
import json
import hmac
import hashlib

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from router.daemon.router_ai_interceptor import RouterAiInterceptor
from router.daemon.router_threat_sync import RouterThreatSyncAgent


class TestRouterAiInterceptor(unittest.TestCase):
    """Verifies edge router gateway threat interception and LAN device accounting."""

    def setUp(self):
        self.interceptor = RouterAiInterceptor()
        self.interceptor.register_device("AA:BB:CC:DD:EE:FF", "Kid's iPad Air")

    def test_life_safety_exemption_on_router(self):
        """Emergency and critical OS traffic bypasses router AI blocking."""
        should_block, ip, telem = self.interceptor.intercept_packet(
            domain="911.gov",
            client_ip="192.168.1.50",
            client_mac="AA:BB:CC:DD:EE:FF"
        )
        self.assertFalse(should_block)
        self.assertEqual(telem["action"], "ALLOW")
        self.assertEqual(telem["risk_score"], 0.0)

    def test_homograph_blocked_and_logged(self):
        """Mixed-script homograph query from LAN device is blocked and logged."""
        should_block, sinkhole_ip, telem = self.interceptor.intercept_packet(
            domain="\u0430pple.com",
            client_ip="192.168.1.105",
            client_mac="AA:BB:CC:DD:EE:FF"
        )
        self.assertTrue(should_block)
        self.assertEqual(sinkhole_ip, "0.0.0.0")
        self.assertEqual(telem["action"], "BLOCK")
        self.assertEqual(telem["device_name"], "Kid's iPad Air")
        self.assertEqual(telem["threat_type"], "HOMOGRAPH_TYPOSQUAT")

        # Verify threat was recorded in edge logs
        logs = self.interceptor.get_latest_threat_logs(limit=10)
        self.assertGreaterEqual(len(logs), 1)
        self.assertEqual(logs[0]["client_mac"], "AA:BB:CC:DD:EE:FF")
        self.assertEqual(logs[0]["device_name"], "Kid's iPad Air")

    def test_dga_blocked_on_router(self):
        """Malware C2 query is sinkholed on router."""
        should_block, sinkhole_ip, telem = self.interceptor.intercept_packet(
            domain="bcdfghjklmnpqrstvwxyz.org",
            client_ip="192.168.1.140",
            client_mac="AA:BB:CC:11:22:33"  # LG Smart TV
        )
        self.assertTrue(should_block)
        self.assertEqual(telem["threat_type"], "DGA_MALWARE")
        self.assertEqual(telem["device_name"], "Living Room LG Smart TV")

    def test_benign_domain_allowed(self):
        """Clean queries pass through to upstream DNS."""
        should_block, _, telem = self.interceptor.intercept_packet(
            domain="wikipedia.org",
            client_ip="192.168.1.182",
            client_mac="F0:18:98:77:88:99"
        )
        self.assertFalse(should_block)
        self.assertEqual(telem["action"], "ALLOW")

    def test_conditional_whitelisting_law_on_router(self):
        """Router strictly enforces Conditional Whitelisting Law."""
        # 1. Idle -> success
        self.interceptor.set_router_lock(locked=False, duration_seconds=0)
        self.assertTrue(self.interceptor.add_router_whitelist("school-portal.org"))

        # 2. Locked -> PermissionError (Access Denied)
        self.interceptor.set_router_lock(locked=True, duration_seconds=1800)
        with self.assertRaises(PermissionError):
            self.interceptor.add_router_whitelist("gaming-site.com")


class TestRouterThreatSyncAgent(unittest.TestCase):
    """Verifies edge model sync, HMAC integrity, and health diagnostics."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.secret = b"Test-Edge-Sync-Secret-12345"
        self.agent = RouterThreatSyncAgent(
            checkpoint_dir=self.temp_dir,
            sync_secret=self.secret
        )

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_apply_verified_model_update(self):
        weights = {"w1": [0.1, 0.2], "b1": [0.0]}
        payload_bytes = json.dumps(weights, sort_keys=True).encode("utf-8")
        sig = hmac.new(self.secret, payload_bytes, hashlib.sha256).hexdigest()

        applied = self.agent.apply_model_update(
            model_name="dga_mlp",
            version="2.0-router",
            weights_dict=weights,
            signature_hex=sig
        )
        self.assertTrue(applied)

        status = self.agent.get_sync_status()
        self.assertEqual(status["total_syncs_applied"], 1)

    def test_reject_tampered_sync(self):
        weights = {"w1": [0.1]}
        invalid_sig = "deadbeef12345678"
        with self.assertRaises(PermissionError):
            self.agent.apply_model_update(
                model_name="dga_mlp",
                version="2.0",
                weights_dict=weights,
                signature_hex=invalid_sig
            )

    def test_health_diagnostic_run(self):
        diag = self.agent.run_health_diagnostic()
        self.assertTrue(diag["passed"])
        self.assertEqual(diag["overall_health"], "HEALTHY")
        self.assertTrue(diag["checks"]["homograph_tr39"]["passed"])
        self.assertTrue(diag["checks"]["dga_neural_mlp"]["passed"])
        self.assertTrue(diag["checks"]["life_safety_exemptions"]["passed"])


if __name__ == "__main__":
    unittest.main()
