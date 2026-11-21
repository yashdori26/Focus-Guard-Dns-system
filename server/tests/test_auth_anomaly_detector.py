"""
Unit tests for FocusDNS AuthAnomalyDetector and GeoVelocityEngine.
"""

import unittest
import time
from server.engine.auth_anomaly_detector import (
    AuthAnomalyDetector,
    GeoVelocityEngine,
    SimSwapHeuristicEngine,
    TokenBucketLimiter,
    RiskLevel,
    RecommendedAction
)


class TestAuthAnomalyDetector(unittest.TestCase):
    def setUp(self):
        self.detector = AuthAnomalyDetector()

    def test_haversine_distance_known_points(self):
        # Distance between London (GB) ~ (55.3781, -3.4360) and New Delhi (IN) ~ (20.5937, 78.9629)
        # Should be roughly 6,700 - 7,000 km
        dist = GeoVelocityEngine.haversine_distance(55.3781, -3.4360, 20.5937, 78.9629)
        self.assertGreater(dist, 6000.0)
        self.assertLess(dist, 8000.0)

    def test_geo_velocity_calculation(self):
        # 7000 km in 1 hour = 7000 km/h (impossible, supersonic/orbital)
        dist, vel = GeoVelocityEngine.compute_velocity("GB", "IN", 3600.0)
        self.assertGreater(dist, 6000.0)
        self.assertGreater(vel, 6000.0)

        # Same country
        dist_same, vel_same = GeoVelocityEngine.compute_velocity("US", "US", 3600.0)
        self.assertEqual(dist_same, 0.0)
        self.assertEqual(vel_same, 0.0)

    def test_impossible_travel_detection(self):
        phone = "+12025550199"
        # Initial login in US
        self.detector.record_login_attempt(phone, "1.1.1.1", "US", "device-A")

        # Login from IN 60 seconds later -> impossible supersonic travel
        res = self.detector.evaluate_request(phone, "2.2.2.2", "IN", "device-B")
        self.assertIn("IMPOSSIBLE_TRAVEL_ORBITAL_VELOCITY", res.anomaly_flags)
        self.assertIn("DEVICE_FINGERPRINT_MISMATCH", res.anomaly_flags)
        self.assertGreaterEqual(res.risk_score, 0.70)
        self.assertEqual(res.recommended_action, RecommendedAction.BLOCK)

    def test_token_bucket_rate_limiter(self):
        limiter = TokenBucketLimiter(capacity=2, fill_rate_per_second=0.0)
        self.assertTrue(limiter.check_and_consume("user1")[0])
        self.assertTrue(limiter.check_and_consume("user1")[0])
        # Third attempt should be rejected
        self.assertFalse(limiter.check_and_consume("user1")[0])

    def test_sim_swap_synthetic_entropy(self):
        # Repetitive digits: +1111111111
        desc, risk = SimSwapHeuristicEngine.analyze_carrier_type("+1111111111", "US")
        self.assertEqual(desc, "SYNTHETIC_REPETITIVE_DIGITS")
        self.assertGreater(risk, 0.4)

        # Normal random-like mobile number
        desc_norm, risk_norm = SimSwapHeuristicEngine.analyze_carrier_type("+19174829381", "US")
        self.assertEqual(desc_norm, "STANDARD_CELLULAR_MNO")
        self.assertLess(risk_norm, 0.1)

    def test_audit_trail_recording(self):
        self.detector.record_login_attempt("+19998887777", "10.0.0.1", "US", "dev1", True)
        audit = self.detector.get_audit_trail(10)
        self.assertGreaterEqual(len(audit), 1)
        self.assertEqual(audit[-1]["phone"], "+19998887777")


if __name__ == "__main__":
    unittest.main()
