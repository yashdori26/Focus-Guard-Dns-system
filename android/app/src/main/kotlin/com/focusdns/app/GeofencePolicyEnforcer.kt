package com.focusdns.app

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import kotlin.math.*

/**
 * GeofencePolicyEnforcer
 * ======================
 * Native Android Geofence & Location-Based Focus Policy Enforcer for FocusDNS.
 *
 * Implements OS-level location boundary monitoring for schools, campuses, and workplaces.
 *
 * Core Law Verification:
 * - When Device ENTERS a restricted geofence:
 *     * ProtectionStateCoordinator is set to ACTIVE.
 *     * canUninstall(context) == FALSE (Uninstallation is locked to prevent evasion).
 * - When Device EXITS all restricted geofences:
 *     * ProtectionStateCoordinator is set to INACTIVE (Normal Idle Mode).
 *     * canUninstall(context) == TRUE (Clean, friction-free uninstallation permitted).
 * - Life Safety Exemption:
 *     * Emergency calls (911, 112, etc.) and native telecom packages are ALWAYS unhindered.
 */
class GeofencePolicyEnforcer(private val context: Context) {

    companion object {
        private const val TAG = "GeofenceEnforcer"
        private const val PREFS_NAME = "focus_dns_geofence_prefs"
        private const val KEY_INSIDE_GEOFENCE = "key_inside_geofence"
        private const val KEY_ACTIVE_ZONE_NAME = "key_active_zone_name"
        private const val KEY_LAST_LAT = "key_last_lat"
        private const val KEY_LAST_LON = "key_last_lon"

        // Mean Earth radius in meters
        const val EARTH_RADIUS_METERS = 6371000.0

        /**
         * Calculates spherical distance between two GPS coordinates using Haversine formula.
         */
        fun calculateDistanceMeters(
            lat1: Double, lon1: Double,
            lat2: Double, lon2: Double
        ): Double {
            val phi1 = Math.toRadians(lat1)
            val phi2 = Math.toRadians(lat2)
            val deltaPhi = Math.toRadians(lat2 - lat1)
            val deltaLambda = Math.toRadians(lon2 - lon1)

            val a = sin(deltaPhi / 2.0).pow(2.0) +
                    cos(phi1) * cos(phi2) * sin(deltaLambda / 2.0).pow(2.0)
            val c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
            return EARTH_RADIUS_METERS * c
        }
    }

    data class GeofenceZoneData(
        val zoneId: String,
        val name: String,
        val latitude: Double,
        val longitude: Double,
        val radiusMeters: Double = 200.0,
        val enforceLock: Boolean = true
    )

    private val activeZones = mutableListOf<GeofenceZoneData>()

    init {
        // Initialize default enterprise HQ geofence
        activeZones.add(
            GeofenceZoneData(
                zoneId = "geo_sf_hq",
                name = "FocusGuard Enterprise Campus",
                latitude = 37.7937,
                longitude = -122.4000,
                radiusMeters = 250.0,
                enforceLock = true
            )
        )
    }

    private fun getPrefs(): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun addZone(zone: GeofenceZoneData) {
        activeZones.removeAll { it.zoneId == zone.zoneId }
        activeZones.add(zone)
    }

    fun removeZone(zoneId: String): Boolean {
        return activeZones.removeAll { it.zoneId == zoneId }
    }

    fun getZones(): List<GeofenceZoneData> {
        return ArrayList(activeZones)
    }

    /**
     * Evaluates current device GPS coordinates against registered geofence zones.
     * Updates ProtectionStateCoordinator based on proximity:
     * - Inside restricted zone -> Arms protection, locks uninstallation.
     * - Outside restricted zones -> Disarms protection, enables clean uninstallation.
     */
    fun evaluateLocation(latitude: Double, longitude: Double): Map<String, Any> {
        var insideRestricted = false
        var matchedZoneName: String? = null
        var closestDistance = Double.MAX_VALUE
        var closestZoneName: String? = null

        for (zone in activeZones) {
            val dist = calculateDistanceMeters(zone.latitude, zone.longitude, latitude, longitude)
            if (dist < closestDistance) {
                closestDistance = dist
                closestZoneName = zone.name
            }

            if (dist <= zone.radiusMeters) {
                if (zone.enforceLock) {
                    insideRestricted = true
                    matchedZoneName = zone.name
                }
            }
        }

        // Apply FocusDNS Core Law
        val prefs = getPrefs()
        prefs.edit()
            .putBoolean(KEY_INSIDE_GEOFENCE, insideRestricted)
            .putString(KEY_ACTIVE_ZONE_NAME, matchedZoneName ?: "")
            .putFloat(KEY_LAST_LAT, latitude.toFloat())
            .putFloat(KEY_LAST_LON, longitude.toFloat())
            .apply()

        if (insideRestricted) {
            Log.i(TAG, "Device ENTERED restricted geofence: $matchedZoneName. Arming focus protection lock.")
            ProtectionStateCoordinator.setProtectionActive(context, true)
        } else {
            Log.i(TAG, "Device OUTSIDE all restricted geofences. Restoring normal mode (clean uninstallation permitted).")
            ProtectionStateCoordinator.setProtectionActive(context, false)
        }

        val canUninstall = ProtectionStateCoordinator.canUninstall(context)

        return mapOf(
            "latitude" to latitude,
            "longitude" to longitude,
            "insideRestrictedGeofence" to insideRestricted,
            "matchedZoneName" to (matchedZoneName ?: "None (Outside)"),
            "closestZoneName" to (closestZoneName ?: "None"),
            "closestDistanceMeters" to if (closestDistance != Double.MAX_VALUE) closestDistance else 0.0,
            "canUninstallApp" to canUninstall,
            "emergencyExemptionActive" to true
        )
    }

    fun isInsideRestrictedGeofence(): Boolean {
        return getPrefs().getBoolean(KEY_INSIDE_GEOFENCE, false)
    }

    fun getActiveZoneName(): String {
        return getPrefs().getString(KEY_ACTIVE_ZONE_NAME, "") ?: ""
    }
}
