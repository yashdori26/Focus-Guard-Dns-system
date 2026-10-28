package com.focusdns.app

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.UserManager
import android.util.Log

/**
 * DevicePolicyProfileManager
 * ===========================
 * Orchestrates Android Enterprise user restrictions, safe boot locking, and multi-user
 * evasion prevention during active focus sessions.
 *
 * Anti-Circumvention Rule:
 * - When Focus Mode or Strict Countdown Timer is active:
 *     Enforces DISALLOW_SAFE_BOOT, DISALLOW_CONFIG_VPN, DISALLOW_ADD_USER
 *     to prevent users from rebooting into safe mode or switching user accounts.
 * - When Session is IDLE (canUninstall == true):
 *     All user restrictions are cleared completely, restoring default phone freedom.
 */
object DevicePolicyProfileManager {

    private const val TAG = "DevicePolicyProfile"

    private val GUARDED_RESTRICTIONS = listOf(
        UserManager.DISALLOW_SAFE_BOOT,
        UserManager.DISALLOW_CONFIG_VPN,
        UserManager.DISALLOW_ADD_USER,
        UserManager.DISALLOW_REMOVE_USER
    )

    private fun getDpm(context: Context): DevicePolicyManager? {
        return context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
    }

    private fun getAdmin(context: Context): ComponentName {
        return FocusDeviceAdminReceiver.getComponentName(context)
    }

    /**
     * Applies strict evasion-prevention restrictions if uninstallation is locked.
     * Clears all restrictions if uninstallation is allowed.
     */
    fun syncRestrictions(context: Context): Boolean {
        val dpm = getDpm(context) ?: return false
        val admin = getAdmin(context)

        if (!dpm.isAdminActive(admin)) {
            Log.d(TAG, "Device Administrator not active; skipping user restriction sync.")
            return false
        }

        val canUninstall = ProtectionStateCoordinator.canUninstall(context)

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                if (MdmPolicyEngine.isDeviceOwner(context) || MdmPolicyEngine.isProfileOwner(context)) {
                    if (!canUninstall) {
                        // Apply restrictions
                        for (restriction in GUARDED_RESTRICTIONS) {
                            try {
                                dpm.addUserRestriction(admin, restriction)
                            } catch (e: Exception) {
                                Log.d(TAG, "Restriction $restriction not supported on this device/profile")
                            }
                        }
                        Log.i(TAG, "Applied ${GUARDED_RESTRICTIONS.size} anti-evasion restrictions.")
                    } else {
                        // Clear restrictions
                        for (restriction in GUARDED_RESTRICTIONS) {
                            try {
                                dpm.clearUserRestriction(admin, restriction)
                            } catch (e: Exception) {
                                Log.d(TAG, "Could not clear restriction $restriction: ${e.message}")
                            }
                        }
                        Log.i(TAG, "Cleared anti-evasion user restrictions. User has full control.")
                    }
                    true
                } else {
                    false
                }
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to synchronize user restrictions: ${e.message}")
            false
        }
    }

    /**
     * Checks if a specific user restriction is currently active.
     */
    fun isRestrictionActive(context: Context, restrictionKey: String): Boolean {
        val userManager = context.getSystemService(Context.USER_SERVICE) as? UserManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            userManager.hasUserRestriction(restrictionKey)
        } else {
            false
        }
    }

    /**
     * Generates a telemetry report of all anti-evasion restrictions.
     */
    fun getRestrictionsReport(context: Context): Map<String, Boolean> {
        val report = mutableMapOf<String, Boolean>()
        for (res in GUARDED_RESTRICTIONS) {
            report[res] = isRestrictionActive(context, res)
        }
        return report
    }
}
