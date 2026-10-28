package com.focusdns.app

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.util.Log

/**
 * AppQuarantineManager
 * ====================
 * Manages native OS-level application suspension and quarantine during active focus timers.
 *
 * Capabilities:
 * - Uses DevicePolicyManager.setPackagesSuspended to physically grey out distracting apps
 *   on the device launcher during active focus sessions.
 * - Automatically unsuspends all applications as soon as the timer expires.
 */
object AppQuarantineManager {

    private const val TAG = "AppQuarantine"
    private const val PREFS_NAME = "focus_dns_quarantine_prefs"
    private const val KEY_QUARANTINED_PACKAGES = "quarantined_packages"

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private fun getDpm(context: Context): DevicePolicyManager? {
        return context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
    }

    private fun getAdmin(context: Context): ComponentName {
        return FocusDeviceAdminReceiver.getComponentName(context)
    }

    fun getQuarantinedPackages(context: Context): Set<String> {
        return getPrefs(context).getStringSet(KEY_QUARANTINED_PACKAGES, emptySet()) ?: emptySet()
    }

    fun setQuarantinedPackages(context: Context, packages: Set<String>) {
        getPrefs(context).edit().putStringSet(KEY_QUARANTINED_PACKAGES, packages).apply()
    }

    /**
     * Suspends distracting packages at the Android OS launcher level.
     */
    fun suspendDistractingApps(context: Context, packages: Collection<String>): Boolean {
        setQuarantinedPackages(context, packages.toSet())
        val dpm = getDpm(context) ?: return false
        val admin = getAdmin(context)

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                if (MdmPolicyEngine.isDeviceOwner(context) || MdmPolicyEngine.isProfileOwner(context)) {
                    val packageArray = packages.toTypedArray()
                    val failedToSuspend = dpm.setPackagesSuspended(admin, packageArray, true)
                    Log.i(TAG, "Suspended ${packages.size - failedToSuspend.size} apps at launcher level.")
                    true
                } else {
                    Log.d(TAG, "Not Device Owner; launcher app suspension skipped.")
                    false
                }
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to suspend packages: ${e.message}")
            false
        }
    }

    /**
     * Unsuspends all quarantined packages, restoring normal access and launcher colors.
     */
    fun unsuspendAll(context: Context): Boolean {
        val packages = getQuarantinedPackages(context)
        if (packages.isEmpty()) return true

        val dpm = getDpm(context)
        val admin = getAdmin(context)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && dpm != null) {
                if (MdmPolicyEngine.isDeviceOwner(context) || MdmPolicyEngine.isProfileOwner(context)) {
                    val packageArray = packages.toTypedArray()
                    dpm.setPackagesSuspended(admin, packageArray, false)
                    Log.i(TAG, "Successfully unsuspended ${packages.size} apps.")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to unsuspend packages: ${e.message}")
        }

        setQuarantinedPackages(context, emptySet())
        return true
    }

    /**
     * Telemetry map.
     */
    fun getTelemetry(context: Context): Map<String, Any> {
        val quarantined = getQuarantinedPackages(context)
        return mapOf(
            "quarantinedCount" to quarantined.size,
            "quarantinedPackages" to quarantined.toList()
        )
    }
}
