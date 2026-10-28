package com.focusdns.app

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.UserManager
import android.util.Log

/**
 * DpcPolicyManager
 * ================
 * Advanced Android Enterprise Device Policy Controller (DPC) & Device Owner Policy Engine.
 *
 * Enforces deep OS-level protections when FocusDNS is provisioned as Device Owner:
 * - Conditional OS restrictions (DISALLOW_UNINSTALL_APPS, DISALLOW_APPS_CONTROL, DISALLOW_SAFE_BOOT)
 *   strictly enforcing the core FocusDNS law:
 *     * When Protection Mode is ON or Timer is active: Uninstallation & Task Manager Force Stop are OS-locked.
 *     * When Idle (Normal Mode): Restrictions are cleared, permitting 100% clean uninstallation.
 * - USB Debugging (ADB) killswitch preventing adb shell circumvention during focus sessions.
 * - Preserves native telecom emergency dialer exemptions at all times.
 */
class DpcPolicyManager(private val context: Context) {

    companion object {
        private const val TAG = "DpcPolicyManager"

        // Core Android Enterprise User Restrictions
        const val RESTRICTION_UNINSTALL_APPS = UserManager.DISALLOW_UNINSTALL_APPS
        const val RESTRICTION_APPS_CONTROL = UserManager.DISALLOW_APPS_CONTROL
        const val RESTRICTION_SAFE_BOOT = UserManager.DISALLOW_SAFE_BOOT
        const val RESTRICTION_CONFIG_VPN = UserManager.DISALLOW_CONFIG_VPN
        const val RESTRICTION_DEBUGGING_FEATURES = UserManager.DISALLOW_DEBUGGING_FEATURES
        const val RESTRICTION_FACTORY_RESET = UserManager.DISALLOW_FACTORY_RESET
        const val RESTRICTION_ADD_USER = UserManager.DISALLOW_ADD_USER
        const val RESTRICTION_MODIFY_ACCOUNTS = UserManager.DISALLOW_MODIFY_ACCOUNTS

        val CORE_FOCUS_RESTRICTIONS = listOf(
            RESTRICTION_UNINSTALL_APPS,
            RESTRICTION_APPS_CONTROL,
            RESTRICTION_SAFE_BOOT,
            RESTRICTION_CONFIG_VPN,
            RESTRICTION_DEBUGGING_FEATURES,
            RESTRICTION_FACTORY_RESET
        )
    }

    private val dpm: DevicePolicyManager? =
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager

    private val adminComponent: ComponentName =
        FocusDeviceAdminReceiver.getComponentName(context)

    /**
     * Returns true if FocusDNS is active as Android Enterprise Device Owner.
     */
    fun isDeviceOwner(): Boolean {
        return try {
            dpm?.isDeviceOwnerApp(context.packageName) ?: false
        } catch (e: Exception) {
            Log.w(TAG, "isDeviceOwner query failed: ${e.message}")
            false
        }
    }

    /**
     * Returns true if FocusDNS is active as Android Enterprise Profile Owner (Work Profile).
     */
    fun isProfileOwner(): Boolean {
        return try {
            dpm?.isProfileOwnerApp(context.packageName) ?: false
        } catch (e: Exception) {
            Log.w(TAG, "isProfileOwner query failed: ${e.message}")
            false
        }
    }

    /**
     * Returns true if FocusDNS has any DPC privileges (Device Owner or Profile Owner).
     */
    fun isEnterpriseDpcActive(): Boolean {
        return isDeviceOwner() || isProfileOwner()
    }

    /**
     * Enforces the Core Inviolable Conditional Law:
     * - [isProtected] = true: Enforces DISALLOW_UNINSTALL_APPS, DISALLOW_APPS_CONTROL, etc.
     * - [isProtected] = false: Clears all uninstallation and control restrictions, allowing clean removal.
     */
    fun applyConditionalFocusPolicy(isProtected: Boolean): Map<String, Boolean> {
        val results = mutableMapOf<String, Boolean>()
        if (dpm == null || !isEnterpriseDpcActive()) {
            Log.i(TAG, "Not a DPC owner, skipping OS user restriction updates.")
            return results
        }

        for (restriction in CORE_FOCUS_RESTRICTIONS) {
            results[restriction] = try {
                if (isProtected) {
                    dpm.addUserRestriction(adminComponent, restriction)
                } else {
                    dpm.clearUserRestriction(adminComponent, restriction)
                }
                true
            } catch (e: SecurityException) {
                Log.w(TAG, "Failed modifying restriction $restriction: ${e.message}")
                false
            }
        }

        // Also control USB debugging specifically
        setUsbDebuggingDisabled(isProtected)

        return results
    }

    /**
     * Enables or disables USB Debugging (ADB) on device level.
     */
    fun setUsbDebuggingDisabled(disabled: Boolean): Boolean {
        if (dpm == null || !isDeviceOwner()) return false
        return try {
            if (disabled) {
                dpm.addUserRestriction(adminComponent, RESTRICTION_DEBUGGING_FEATURES)
            } else {
                dpm.clearUserRestriction(adminComponent, RESTRICTION_DEBUGGING_FEATURES)
            }
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "Failed toggling USB debugging restriction: ${e.message}")
            false
        }
    }

    /**
     * Returns live status of all core DPC restrictions.
     */
    fun getActiveRestrictionsStatus(): Map<String, Boolean> {
        val userManager = context.getSystemService(Context.USER_SERVICE) as? UserManager
        val status = mutableMapOf<String, Boolean>()
        if (userManager == null) return status

        for (restriction in CORE_FOCUS_RESTRICTIONS) {
            status[restriction] = try {
                userManager.hasUserRestriction(restriction)
            } catch (e: Exception) {
                false
            }
        }
        return status
    }

    /**
     * Suspends distraction packages while strictly exempting emergency telephone dialer.
     */
    fun setDistractionAppsSuspended(packageNames: List<String>, suspended: Boolean): List<String> {
        if (dpm == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.N || !isEnterpriseDpcActive()) {
            return emptyList()
        }

        // Filter out emergency dialer and system critical packages
        val safePackagesToSuspend = packageNames.filter { pkg ->
            !EmergencyCallExemptionManager.isTelecomPackage(pkg) &&
                    pkg != context.packageName &&
                    pkg != "android" &&
                    pkg != "com.android.systemui"
        }.toTypedArray()

        return try {
            val failed = dpm.setPackagesSuspended(adminComponent, safePackagesToSuspend, suspended)
            failed?.toList() ?: emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "setPackagesSuspended failed: ${e.message}")
            safePackagesToSuspend.toList()
        }
    }

    /**
     * Checks if uninstallation of FocusDNS is currently permitted under DPC policy.
     */
    fun canUninstallApp(): Boolean {
        // If uninstallation restriction is set, removal is blocked
        val userManager = context.getSystemService(Context.USER_SERVICE) as? UserManager
        val isUninstallRestricted = userManager?.hasUserRestriction(RESTRICTION_UNINSTALL_APPS) ?: false
        return !isUninstallRestricted
    }

    /**
     * Provides comprehensive diagnostic summary of DPC posture.
     */
    fun getDpcDiagnosticReport(): Map<String, Any> {
        val isDo = isDeviceOwner()
        val isPo = isProfileOwner()
        val restrictions = getActiveRestrictionsStatus()

        return mapOf(
            "isDeviceOwner" to isDo,
            "isProfileOwner" to isPo,
            "isEnterpriseDpcActive" to (isDo || isPo),
            "canUninstallApp" to canUninstallApp(),
            "activeRestrictions" to restrictions,
            "coreRestrictionsEnforced" to restrictions.values.all { it }
        )
    }
}
