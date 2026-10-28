"""
server/tests/test_engine_geofence.py
Comprehensive unit test suite for FocusDNS Geofenced Boundary Policy Engine.

Validates:
1. Spherical Haversine Distance Mathematics:
   - High-accuracy geospatial distance formula with meter-level resolution.
2. Conditional Uninstallation by Physical Location:
   - When inside a designated Focus Geofence (School, Campus, Corporate Office):
     * Focus lock is automatically armed.
     * can_uninstall == False (Uninstallation is strictly locked to prevent student/employee evasion).
   - When device exits all restricted geofenced zones:
     * Focus lock is disarmed.
     * can_uninstall == True (Normal mode is restored, clean uninstallation 100% permitted).
3. Life-Safety Exemption:
   - Emergency calling (911, 112, 999, 000) is NEVER affected or blocked inside any geofence.
"""

import unittest
from server.engine.geofence_engine import (
    haversine_distance_meters,
    GeofenceZone,
    GeofenceEngine,
)


class TestGeofenceEngine(unittest.TestCase):

    def setUp(self):
        self.engine = GeofenceEngine()

    def test_haversine_identical_points(self):
        dist = haversine_distance_meters(37.7937, -122.4000, 37.7937, -122.4000)
        self.assertAlmostEqual(dist, 0.0, places=2)

    def test_haversine_known_geographic_distance(self):
        # Distance between SF HQ (37.7937, -122.4000) and Ferry Building (37.7955, -122.3937)
        # Approximate distance is ~580-600 meters
        dist = haversine_distance_meters(37.7937, -122.4000, 37.7955, -122.3937)
        self.assertGreater(dist, 500.0)
        self.assertLess(dist, 700.0)

    def test_zone_contains_coordinate(self):
        zone = GeofenceZone(
            zone_id="geo_test_library",
            name="Campus Library",
            latitude=37.8722,
            longitude=-122.2590,
            radius_meters=150.0,
            enforce_focus_lock=True,
            strict_uninstall_lock=True,
        )

        # Center point -> inside
        inside, dist = zone.contains_coordinate(37.8722, -122.2590)
        self.assertTrue(inside)
        self.assertAlmostEqual(dist, 0.0, places=1)

        # Point 50 meters away -> inside
        inside_close, dist_close = zone.contains_coordinate(37.8724, -122.2590)
        self.assertTrue(inside_close)
        self.assertLess(dist_close, 150.0)

        # Point 2000 meters away -> outside
        inside_far, dist_far = zone.contains_coordinate(37.8900, -122.2590)
        self.assertFalse(inside_far)
        self.assertGreater(dist_far, 150.0)

    def test_conditional_uninstallation_inside_restricted_geofence(self):
        """
        Core Law: Inside restricted geofence, uninstallation is locked.
        """
        # Exactly at SF HQ coordinates (37.7937, -122.4000)
        eval_res = self.engine.evaluate_device_location(
            device_id="dev_student_pixel",
            latitude=37.7937,
            longitude=-122.4000,
        )

        self.assertTrue(eval_res["inside_restricted_geofence"])
        self.assertFalse(eval_res["can_uninstall"], "Must lock uninstallation inside restricted zone")
        self.assertEqual(eval_res["directive"], "LOCK_FOCUS")
        self.assertEqual(len(eval_res["matching_zones"]), 1)
        self.assertEqual(eval_res["matching_zones"][0]["zone_name"], "FocusGuard Global Headquarters")
        self.assertIn("100% exempt", eval_res["emergency_safety_law"])

    def test_conditional_uninstallation_outside_geofence(self):
        """
        Core Law: Outside all geofences, normal mode is restored and clean uninstallation is permitted.
        """
        # Far outside in Pacific Ocean / San Jose (37.3382, -121.8863)
        eval_res = self.engine.evaluate_device_location(
            device_id="dev_student_pixel",
            latitude=37.3382,
            longitude=-121.8863,
        )

        self.assertFalse(eval_res["inside_restricted_geofence"])
        self.assertTrue(eval_res["can_uninstall"], "Must permit clean uninstallation outside geofences")
        self.assertEqual(eval_res["directive"], "UNLOCK_FOCUS")
        self.assertEqual(len(eval_res["matching_zones"]), 0)
        self.assertIsNotNone(eval_res["closest_zone_name"])
        self.assertGreater(eval_res["closest_zone_distance_meters"], 10000.0)

    def test_custom_zone_crud(self):
        new_zone = GeofenceZone(
            zone_id="geo_exam_hall",
            name="Final Examination Hall A",
            latitude=40.7128,
            longitude=-74.0060,
            radius_meters=100.0,
            tenant_id="tenant_university",
            enforce_focus_lock=True,
            strict_uninstall_lock=True,
        )
        self.engine.create_or_update_zone(new_zone)

        fetched = self.engine.get_zone("geo_exam_hall")
        self.assertIsNotNone(fetched)
        self.assertEqual(fetched.name, "Final Examination Hall A")

        # Evaluate at exam hall
        res = self.engine.evaluate_device_location(
            device_id="dev_exam_01",
            latitude=40.7128,
            longitude=-74.0060,
            tenant_id="tenant_university",
        )
        self.assertTrue(res["inside_restricted_geofence"])
        self.assertFalse(res["can_uninstall"])

        # Delete zone
        del_res = self.engine.delete_zone("geo_exam_hall")
        self.assertTrue(del_res)
        self.assertIsNone(self.engine.get_zone("geo_exam_hall"))

    def test_non_restrictive_geofence_permits_uninstallation(self):
        # A zone with enforce_focus_lock=False (e.g., telemetry-only zone)
        info_zone = GeofenceZone(
            zone_id="geo_cafeteria",
            name="Cafeteria & Lounge",
            latitude=37.7937,
            longitude=-122.4000,
            radius_meters=50.0,
            enforce_focus_lock=False,
            strict_uninstall_lock=False,
        )
        engine = GeofenceEngine()
        engine._zones.clear()  # Clear default zones
        engine.create_or_update_zone(info_zone)

        res = engine.evaluate_device_location("dev_cafe", 37.7937, -122.4000)
        self.assertFalse(res["inside_restricted_geofence"])
        self.assertTrue(res["can_uninstall"], "Non-restrictive zone must permit clean uninstallation")


if __name__ == "__main__":
    unittest.main()
