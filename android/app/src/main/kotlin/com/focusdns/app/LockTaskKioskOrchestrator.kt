package com.focusdns.app

import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * LockTaskKioskOrchestrator
 * =========================
 * Manages Android Enterprise LockTask (Dedicated Single-App / Multi-App Kiosk Mode).
 *
 * Implements strict focus session containment:
 * - Locks the screen to FocusDNS and whitelisted utility apps during active focus.
 * - Suppresses Home, Recents, and Status Bar notifications.
 * - Inviolable Life-Safety Guarantee: Standard telecom emergency phone dialers
 *   (com.android.phone, com.google.android.dialer, com.samsung.incallui) are ALWAYS
 *   whitelisted and permitted in LockTask packages so 911/112 emergency calls can never be blocked.
 * - When Focus session finishes (or Normal Mode is active): LockTask mode is cleanly exited,
 *   uninstallation is unlocked, and normal device operation resumes.
 */
class LockTaskKioskOrchestrator(private val context: Context) {

    companion object {
        private const val TAG = "LockTaskOrchestrator"

        // Default permitted telecom packages for emergency safety
        val ESSENTIAL_SAFETY_PACKAGES = setOf(
            "com.android.phone",
            "com.google.android.dialer",
            "com.samsung.incallui",
            "com.android.server.telecom"
        )
    }

    private val dpm: DevicePolicyManager? =
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager

    private val activityManager: ActivityManager? =
        context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager

    private val adminComponent: ComponentName =
        FocusDeviceAdminReceiver.getComponentName(context)

    /**
     * Checks if LockTask mode can be automatically entered without user prompt (Device Owner only).
     */
    fun isLockTaskPermitted(packageName: String = context.packageName): Boolean {
        if (dpm == null) return false
        return try {
            dpm.isLockTaskPermitted(packageName)
        } catch (e: Exception) {
            Log.w(TAG, "isLockTaskPermitted check failed: ${e.message}")
            false
        }
    }

    /**
     * Configures the list of apps permitted to run inside LockTask mode.
     * Always merges [additionalPackages] with FocusDNS and emergency dialers.
     */
    fun configurePermittedPackages(additionalPackages: List<String> = emptyList()): Boolean {
        if (dpm == null) return false
        val dpcManager = DpcPolicyManager(context)
        if (!dpcManager.isDeviceOwner()) {
            Log.w(TAG, "Cannot setLockTaskPackages: Not Device Owner")
            return false
        }

        val allPermitted = mutableSetOf(context.packageName)
        allPermitted.addAll(ESSENTIAL_SAFETY_PACKAGES)
        allPermitted.addAll(additionalPackages.filter { it.isNotBlank() })

        return try {
            dpm.setLockTaskPackages(adminComponent, allPermitted.toTypedArray())
            Log.i(TAG, "LockTask packages configured: ${allPermitted.size} packages")
            true
        } catch (e: SecurityException) {
            Log.e(TAG, "Failed setLockTaskPackages: ${e.message}")
            false
        }
    }

    /**
     * Configures LockTask system UI features on Android 9+ (Pie).
     */
    fun configureLockTaskFeatures(
        allowSystemInfo: Boolean = true,
        allowKeyguard: Boolean = true,
        allowNotifications: Boolean = false
    ): Boolean {
        if (dpm == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        val dpcManager = DpcPolicyManager(context)
        if (!dpcManager.isDeviceOwner()) return false

        var flags = DevicePolicyManager.LOCK_TASK_FEATURE_NONE
        if (allowSystemInfo) flags = flags or DevicePolicyManager.LOCK_TASK_FEATURE_SYSTEM_INFO
        if (allowKeyguard) flags = flags or DevicePolicyManager.LOCK_TASK_FEATURE_KEYGUARD
        if (allowNotifications) flags = flags or DevicePolicyManager.LOCK_TASK_FEATURE_NOTIFICATIONS

        return try {
            dpm.setLockTaskFeatures(adminComponent, flags)
            true
        } catch (e: SecurityException) {
            Log.e(TAG, "Failed setLockTaskFeatures: ${e.message}")
            false
        }
    }

    /**
     * Enters LockTask mode for the specified activity.
     */
    fun startKioskMode(activity: Activity, additionalPackages: List<String> = emptyList()): Boolean {
        configurePermittedPackages(additionalPackages)
        configureLockTaskFeatures(allowSystemInfo = true, allowKeyguard = true)

        return try {
            activity.startLockTask()
            Log.i(TAG, "startLockTask initiated successfully.")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed starting LockTask mode: ${e.message}")
            false
        }
    }

    /**
     * Exits LockTask mode cleanly when the timer expires or normal mode is active.
     */
    fun stopKioskMode(activity: Activity): Boolean {
        return try {
            activity.stopLockTask()
            Log.i(TAG, "stopLockTask executed successfully.")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed stopping LockTask mode: ${e.message}")
            false
        }
    }

    /**
     * Returns true if LockTask mode is currently active.
     */
    fun isKioskModeActive(): Boolean {
        if (activityManager == null) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            activityManager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            @Suppress("DEPRECATION")
            activityManager.isInLockTaskMode
        }
    }

    /**
     * Clears all LockTask packages when returning to Normal Mode, ensuring no residue restrictions.
     */
    fun clearKioskConfiguration(): Boolean {
        if (dpm == null) return false
        val dpcManager = DpcPolicyManager(context)
        if (!dpcManager.isDeviceOwner()) return false

        return try {
            dpm.setLockTaskPackages(adminComponent, arrayOf(context.packageName))
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Dispatches intent to launch the native dialer during kiosk mode (emergency bypass).
     */
    fun launchEmergencyDialer(): Boolean {
        return EmergencyCallExemptionManager.launchEmergencyDialer(context, "112")
    }
}
