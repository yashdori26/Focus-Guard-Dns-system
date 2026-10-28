package com.focusdns.app

import org.junit.Assert.*
import org.junit.Test
import java.util.Calendar

/**
 * GeofenceAndScheduleIntegrationTest
 * ===================================
 * Composite policy integration test coordinating spatial geofences with temporal calendar schedules.
 *
 * Enforces the Inviolable FocusDNS Anti-Bypass Laws:
 * 1. Dual-State Conditional Uninstallation:
 *    - Locked if (InsideRestrictedGeofence == true OR InsideActiveSchedule == true).
 *    - 100% Friction-Free Uninstallation permitted ONLY when (OutsideGeofences == true AND OutsideSchedules == true).
 * 2. Life Safety Invariance:
 *    - Even under simultaneous spatial geofence lockdown and schedule enforcement,
 *      telecom emergency dialing (911, 112, 999, 000, 100, 108, 988) and dialer packages
 *      are NEVER restricted or intercepted.
 */
class GeofenceAndScheduleIntegrationTest {

    private val campusZone = GeofencePolicyEnforcer.GeofenceZoneData(
        zoneId = "zone_campus_lockdown",
        name = "Academic Exam Center",
        latitude = 37.7937,
        longitude = -122.4000,
        radiusMeters = 300.0,
        enforceLock = true
    )

    private val workSchedule = EnterpriseScheduleEngine.ScheduleInterval(
        intervalId = "interval_work_hours",
        title = "Enterprise Focus Hours",
        startHour = 9,
        startMinute = 0,
        endHour = 17,
        endMinute = 0,
        daysOfWeek = setOf(Calendar.MONDAY, Calendar.TUESDAY, Calendar.WEDNESDAY, Calendar.THURSDAY, Calendar.FRIDAY),
        enforceLock = true
    )

    private fun evaluateCompositePolicy(
        deviceLat: Double,
        deviceLon: Double,
        dayOfWeek: Int,
        hour: Int,
        minute: Int
    ): Pair<Boolean, Boolean> {
        // Evaluate Geofence
        val geofenceDist = GeofencePolicyEnforcer.calculateDistanceMeters(
            campusZone.latitude, campusZone.longitude,
            deviceLat, deviceLon
        )
        val insideGeofence = (geofenceDist <= campusZone.radiusMeters) && campusZone.enforceLock

        // Evaluate Schedule
        val inScheduleDays = workSchedule.daysOfWeek.contains(dayOfWeek)
        val currentMins = hour * 60 + minute
        val startMins = workSchedule.startHour * 60 + workSchedule.startMinute
        val endMins = workSchedule.endHour * 60 + workSchedule.endMinute
        val insideSchedule = inScheduleDays && (currentMins in startMins until endMins) && workSchedule.enforceLock

        val protectionActive = insideGeofence || insideSchedule
        val canUninstall = !protectionActive

        return Pair(protectionActive, canUninstall)
    }

    @Test
    fun testDualActiveStateStrictlyLocksUninstallation() {
        // Monday 10:00 AM (during work) AND on campus (50m from center)
        val (protectionActive, canUninstall) = evaluateCompositePolicy(
            deviceLat = 37.7938,
            deviceLon = -122.4000,
            dayOfWeek = Calendar.MONDAY,
            hour = 10,
            minute = 0
        )
        assertTrue("Protection must be active when both geofence and schedule match", protectionActive)
        assertFalse("Uninstallation must be strictly locked under dual active state", canUninstall)
    }

    @Test
    fun testGeofenceOnlyLocksUninstallationOffHours() {
        // Sunday 2:00 PM (weekend, off schedule) BUT student visits exam center (50m away)
        val (protectionActive, canUninstall) = evaluateCompositePolicy(
            deviceLat = 37.7938,
            deviceLon = -122.4000,
            dayOfWeek = Calendar.SUNDAY,
            hour = 14,
            minute = 0
        )
        assertTrue("Geofence containment must activate protection even outside business hours", protectionActive)
        assertFalse("Uninstallation must be locked when inside geofence", canUninstall)
    }

    @Test
    fun testScheduleOnlyLocksUninstallationRemoteWork() {
        // Tuesday 11:00 AM (work hours) BUT employee is at home (10 km away)
        val (protectionActive, canUninstall) = evaluateCompositePolicy(
            deviceLat = 37.7000,
            deviceLon = -122.4000,
            dayOfWeek = Calendar.TUESDAY,
            hour = 11,
            minute = 0
        )
        assertTrue("Enterprise schedule must activate protection during business hours even off-campus", protectionActive)
        assertFalse("Uninstallation must be locked during scheduled focus hours", canUninstall)
    }

    @Test
    fun testDualInactiveStatePermitsCleanUninstallation() {
        // Saturday 8:00 PM (weekend, off schedule) AND at home (outside campus)
        val (protectionActive, canUninstall) = evaluateCompositePolicy(
            deviceLat = 37.7000,
            deviceLon = -122.4000,
            dayOfWeek = Calendar.SATURDAY,
            hour = 20,
            minute = 0
        )
        assertFalse("Protection must be disarmed outside geofence and off schedule", protectionActive)
        assertTrue("Clean uninstallation is 100% permitted when both policies are inactive", canUninstall)
    }

    @Test
    fun testLifeSafetyExemptionUnderMaximumLockdown() {
        // Maximum lockdown: inside geofence + during work hours
        val (_, canUninstall) = evaluateCompositePolicy(
            deviceLat = 37.7937,
            deviceLon = -122.4000,
            dayOfWeek = Calendar.WEDNESDAY,
            hour = 14,
            minute = 30
        )
        assertFalse("Uninstallation is locked", canUninstall)

        // Emergency numbers are ALWAYS exempt
        val emergencyNumbers = listOf("911", "112", "999", "000", "100", "108", "988")
        for (num in emergencyNumbers) {
            assertTrue("Emergency number $num must remain unblocked", EmergencyCallExemptionManager.isEmergencyNumber(num))
        }

        // Emergency packages are ALWAYS exempt
        val dialers = listOf(
            "com.android.dialer",
            "com.google.android.dialer",
            "com.samsung.android.dialer",
            "com.android.server.telecom"
        )
        for (pkg in dialers) {
            assertTrue("Telecom dialer $pkg must remain exempt", EmergencyCallExemptionManager.isEmergencyPackage(pkg))
        }
    }

    @Test
    fun testNonEnforcingGeofenceDoesNotLockUninstallation() {
        val informationalZone = GeofencePolicyEnforcer.GeofenceZoneData(
            zoneId = "zone_info",
            name = "Public Library (Informational Only)",
            latitude = 37.7937,
            longitude = -122.4000,
            radiusMeters = 500.0,
            enforceLock = false
        )
        assertFalse(informationalZone.enforceLock)
        val dist = GeofencePolicyEnforcer.calculateDistanceMeters(
            informationalZone.latitude, informationalZone.longitude,
            37.7937, -122.4000
        )
        assertTrue(dist <= informationalZone.radiusMeters)
        // enforceLock is false -> should not arm uninstallation lock
        val locksApp = (dist <= informationalZone.radiusMeters) && informationalZone.enforceLock
        assertFalse(locksApp)
    }
}
