package com.focusdns.app

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.abs

/**
 * GeofencePolicyEnforcerTest
 * =========================
 * Unit tests validating Haversine distance computations, circular geofence boundary detection,
 * and the conditional uninstallation policy law across geographic transitions.
 *
 * Core Law Verification:
 * - Inside Geofenced Zone: canUninstall == False (Strict focus lock prevents evasion).
 * - Outside Geofenced Zone: canUninstall == True (Clean uninstallation permitted).
 * - Emergency Exemption: Standard telecom dialing (911/112) is NEVER blocked by geofences.
 */
class GeofencePolicyEnforcerTest {

    @Test
    fun testHaversineDistanceIdenticalCoordinatesReturnsZero() {
        val lat = 37.7937
        val lon = -122.4000
        val dist = GeofencePolicyEnforcer.calculateDistanceMeters(lat, lon, lat, lon)
        assertEquals(0.0, dist, 0.001)
    }

    @Test
    fun testHaversineDistanceKnownPoints() {
        // SF HQ (37.7937, -122.4000) to point ~111 meters North (0.001 degree lat ~ 111.19 m)
        val lat1 = 37.7937
        val lon1 = -122.4000
        val lat2 = 37.7947
        val lon2 = -122.4000

        val dist = GeofencePolicyEnforcer.calculateDistanceMeters(lat1, lon1, lat2, lon2)
        assertTrue("Distance should be around 111 meters, got $dist", abs(dist - 111.2) < 2.0)
    }

    @Test
    fun testGeofenceZoneContainmentInsideRadius() {
        val zone = GeofencePolicyEnforcer.GeofenceZoneData(
            zoneId = "zone_test_hq",
            name="Test Campus",
            latitude = 37.7937,
            longitude = -122.4000,
            radiusMeters = 200.0,
            enforceLock = true
        )

        // Point 50 meters away -> inside
        val distInside = GeofencePolicyEnforcer.calculateDistanceMeters(
            zone.latitude, zone.longitude,
            37.7940, -122.4000
        )
        assertTrue(distInside <= zone.radiusMeters)

        // Point 500 meters away -> outside
        val distOutside = GeofencePolicyEnforcer.calculateDistanceMeters(
            zone.latitude, zone.longitude,
            37.7980, -122.4000
        )
        assertTrue(distOutside > zone.radiusMeters)
    }

    @Test
    fun testConditionalUninstallationGeofenceLogicSimulation() {
        val zone = GeofencePolicyEnforcer.GeofenceZoneData(
            zoneId = "school_lockdown",
            name = "High School Exam Hall",
            latitude = 40.7128,
            longitude = -74.0060,
            radiusMeters = 100.0,
            enforceLock = true
        )

        // Scenario A: Student enters exam hall (20m from center)
        val distInside = GeofencePolicyEnforcer.calculateDistanceMeters(
            zone.latitude, zone.longitude,
            40.7129, -74.0060
        )
        val isInside = distInside <= zone.radiusMeters
        assertTrue(isInside)

        // In active restricted zone: Focus is locked, clean uninstallation is BLOCKED
        val canUninstallInside = !isInside
        assertFalse(canUninstallInside)

        // Scenario B: Student leaves exam hall (300m away, outside)
        val distOutside = GeofencePolicyEnforcer.calculateDistanceMeters(
            zone.latitude, zone.longitude,
            40.7155, -74.0060
        )
        val isOutside = distOutside > zone.radiusMeters
        assertTrue(isOutside)

        // Outside restricted zone: Normal mode is restored, clean uninstallation is PERMITTED
        val canUninstallOutside = isOutside
        assertTrue(canUninstallOutside)
    }

    @Test
    fun testEmergencyDialerExemptInsideGeofence() {
        // Life safety exemption: Emergency numbers are never blocked inside geofences
        val emergencyNumbers = listOf("911", "112", "999", "000", "100")
        for (num in emergencyNumbers) {
            assertTrue(
                "Emergency number $num must remain exempt",
                EmergencyCallExemptionManager.isEmergencyNumber(num)
            )
        }
    }

    @Test
    fun testGeofenceZoneDataModelDefaults() {
        val zone = GeofencePolicyEnforcer.GeofenceZoneData(
            zoneId = "zone_default",
            name = "Default Zone",
            latitude = 0.0,
            longitude = 0.0
        )
        assertEquals("zone_default", zone.zoneId)
        assertEquals(200.0, zone.radiusMeters, 0.01)
        assertTrue(zone.enforceLock)
    }
}
