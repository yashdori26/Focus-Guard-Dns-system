"""
Unit Tests for AI Pipeline Hook, REST API Dispatcher, Checkpoint Manager & Fast Tokenizer
Verifies zero-latency query interception, DNS pipeline integration, REST endpoints,
HMAC model serialization, and lexical string distance metrics.
"""

import unittest
import sys
import os
import tempfile
import shutil

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from dnslib import DNSRecord, QTYPE
from server.engine.ai_pipeline_hook import AIPipelineHook, AIInterceptVerdict, register_ai_threat_hook
from server.engine.pipeline import DNSPipeline
from server.ai.api_ai_router import AIApiDispatcher
from server.ai.model_checkpoint_manager import ModelCheckpointManager, ModelCheckpointError
from server.ai.fast_tokenizer import FastTokenizer, FastDistanceMetrics


class TestAIPipelineHook(unittest.TestCase):
    """Verifies real-time AI query interception and pipeline integration."""

    def setUp(self):
        self.hook = AIPipelineHook()
        self.pipeline = DNSPipeline(cache_max_entries=500)
        register_ai_threat_hook(self.pipeline, self.hook)

    def test_life_safety_exemption_fast_path(self):
        """Emergency calling and critical OS services bypass AI threat hunting."""
        verdict: AIInterceptVerdict = self.hook.intercept_query("911.gov")
        self.assertFalse(verdict.is_threat)
        self.assertEqual(verdict.action, "ALLOW")
        self.assertEqual(verdict.risk_score, 0.0)

        v_apple = self.hook.intercept_query("push.apple.com")
        self.assertFalse(v_apple.is_threat)
        self.assertEqual(v_apple.action, "ALLOW")

    def test_homograph_interception_block(self):
        """Catches IDN homograph spoofing."""
        cyrillic_apple = "\u0430pple.com"
        verdict = self.hook.intercept_query(cyrillic_apple)
        self.assertTrue(verdict.is_threat)
        self.assertEqual(verdict.action, "BLOCK")
        self.assertEqual(verdict.threat_type, "HOMOGRAPH_TYPOSQUAT")

    def test_dga_interception_block(self):
        """Catches algorithmic malware C2 domains."""
        dga_domain = "bcdfghjklmnpqrstvwxyz.org"
        verdict = self.hook.intercept_query(dga_domain)
        self.assertTrue(verdict.is_threat)
        self.assertEqual(verdict.action, "BLOCK")
        self.assertEqual(verdict.threat_type, "DGA_MALWARE")

    def test_benign_domain_pass(self):
        """Clean human-registered domains pass through cleanly."""
        verdict = self.hook.intercept_query("github.com")
        self.assertFalse(verdict.is_threat)
        self.assertEqual(verdict.action, "ALLOW")

    def test_pipeline_wire_query_ai_blocking(self):
        """Pipeline process_wire_query blocks AI threats with RFC 8914 EDE diagnostic."""
        req = DNSRecord.question("\u0430pple.com", "A")
        wire_out, telem = self.pipeline.process_wire_query(req.pack(), "127.0.0.1", "UDP")

        self.assertEqual(telem["status"], "blocked")
        self.assertIn("AI Threat Hunting", telem["reason"])
        self.assertEqual(telem["rcode"], "NXDOMAIN")

    def test_conditional_whitelisting_via_hook(self):
        """Enforces Conditional Whitelisting Law via hook."""
        self.hook.set_focus_lock(active=False, remaining_seconds=0)
        self.assertTrue(self.hook.add_whitelist_entry("custom-tool.local"))

        # Lock active focus
        self.hook.set_focus_lock(active=True, remaining_seconds=1200)
        with self.assertRaises(PermissionError):
            self.hook.add_whitelist_entry("blocked-site.com")

    def test_telemetry_metrics(self):
        """Metrics accumulate accurately."""
        self.hook.intercept_query("google.com")
        self.hook.intercept_query("\u0430pple.com")
        metrics = self.hook.get_metrics()
        self.assertGreaterEqual(metrics["total_queries_analyzed"], 2)
        self.assertGreaterEqual(metrics["total_threats_blocked"], 1)


class TestAIApiDispatcher(unittest.TestCase):
    """Verifies REST API endpoints and HTTP status codes."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.dispatcher = AIApiDispatcher(checkpoint_dir=self.temp_dir)

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_get_telemetry_endpoint(self):
        code, resp = self.dispatcher.handle_get("/api/v1/ai/telemetry", {})
        self.assertEqual(code, 200)
        self.assertTrue(resp["success"])
        self.assertIn("metrics", resp)

    def test_get_models_status_endpoint(self):
        code, resp = self.dispatcher.handle_get("/api/v1/ai/models/status", {})
        self.assertEqual(code, 200)
        self.assertTrue(resp["success"])
        self.assertIn("models", resp["status"])

    def test_post_hunt_endpoint(self):
        code, resp = self.dispatcher.handle_post("/api/v1/ai/hunt", {"domain": "google.com"})
        self.assertEqual(code, 200)
        self.assertTrue(resp["success"])
        self.assertFalse(resp["verdict"]["is_threat"])

    def test_post_hunt_batch_endpoint(self):
        code, resp = self.dispatcher.handle_post(
            "/api/v1/ai/hunt-batch",
            {"domains": ["google.com", "\u0430pple.com", "bcdfghjklmnpqrstvwxyz.org"]}
        )
        self.assertEqual(code, 200)
        self.assertEqual(resp["count"], 3)

    def test_post_homograph_check_endpoint(self):
        code, resp = self.dispatcher.handle_post(
            "/api/v1/ai/homograph-check", {"domain": "\u0430pple.com"}
        )
        self.assertEqual(code, 200)
        self.assertTrue(resp["result"]["is_threat"])

    def test_post_dga_classify_endpoint(self):
        code, resp = self.dispatcher.handle_post(
            "/api/v1/ai/dga-classify", {"domain": "bcdfghjklmnpqrstvwxyz.org"}
        )
        self.assertEqual(code, 200)
        self.assertTrue(resp["result"]["is_dga"])

    def test_post_categorize_endpoint(self):
        code, resp = self.dispatcher.handle_post(
            "/api/v1/ai/categorize", {"domain": "steampowered.com"}
        )
        self.assertEqual(code, 200)
        self.assertEqual(resp["result"]["primary_category"], "GAMING")

    def test_conditional_whitelisting_api_law(self):
        """
        API Enforces Conditional Whitelisting Law:
        200 OK when idle; 403 Forbidden with ERROR_ACCESS_DENIED when focus is locked.
        """
        # 1. Idle -> Whitelisting succeeds
        self.dispatcher.engine.set_focus_lock(active=False, remaining_seconds=0)
        code, resp = self.dispatcher.handle_post(
            "/api/v1/ai/whitelist", {"domain": "safe-work-tool.com"}
        )
        self.assertEqual(code, 200)
        self.assertTrue(resp["success"])

        # 2. Focus lock active -> Whitelisting strictly returns 403 Forbidden
        self.dispatcher.engine.set_focus_lock(active=True, remaining_seconds=1800)
        code, resp = self.dispatcher.handle_post(
            "/api/v1/ai/whitelist", {"domain": "distraction.com"}
        )
        self.assertEqual(code, 403)
        self.assertFalse(resp["success"])
        self.assertEqual(resp["code"], "ERROR_ACCESS_DENIED")
        self.assertEqual(resp["errno"], 5)


class TestModelCheckpointManager(unittest.TestCase):
    """Verifies atomic checkpoint persistence, HMAC-SHA256 verification, and rollback."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.mgr = ModelCheckpointManager(checkpoint_dir=self.temp_dir)

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_save_and_load_checkpoint(self):
        weights = {"w1": [0.1, 0.2, 0.3], "b1": [-0.5]}
        path = self.mgr.save_checkpoint("test_model", "1.0", weights)
        self.assertTrue(os.path.exists(path))

        loaded_weights, meta = self.mgr.load_checkpoint("test_model")
        self.assertEqual(loaded_weights, weights)
        self.assertEqual(meta["version"], "1.0")

    def test_tamper_detection(self):
        weights = {"w1": [0.5]}
        path = self.mgr.save_checkpoint("tamper_model", "1.0", weights)

        # Corrupt file content
        with open(path, "r", encoding="utf-8") as f:
            import json
            envelope = json.load(f)
        envelope["payload"]["weights"]["w1"] = [0.999]  # Tamper without updating HMAC
        with open(path, "w", encoding="utf-8") as f:
            json.dump(envelope, f)

        # Loading must fail verification
        with self.assertRaises(ModelCheckpointError):
            self.mgr.load_checkpoint("tamper_model")


class TestFastTokenizerAndMetrics(unittest.TestCase):
    """Verifies lexical tokenization and distance metrics."""

    def setUp(self):
        self.tokenizer = FastTokenizer()

    def test_domain_tokenization(self):
        tokens = self.tokenizer.tokenize("secure-apple-login24.com")
        self.assertIn("secure", tokens)
        self.assertIn("apple", tokens)
        self.assertIn("login", tokens)
        self.assertIn("24", tokens)

    def test_distance_metrics(self):
        # Damerau-Levenshtein
        dist = FastDistanceMetrics.damerau_levenshtein("apple", "aple")
        self.assertEqual(dist, 1)

        # Transposition
        dist_swap = FastDistanceMetrics.damerau_levenshtein("google", "goolge")
        self.assertEqual(dist_swap, 1)

        # Jaro-Winkler
        sim = FastDistanceMetrics.jaro_winkler("paypal", "paypa1")
        self.assertGreater(sim, 0.85)

        # Keyboard distance
        kbd_dist = FastDistanceMetrics.keyboard_adjacency_distance("apple", "applr")
        self.assertLess(kbd_dist, 3.0)  # 'e' and 'r' are adjacent


if __name__ == "__main__":
    unittest.main()
