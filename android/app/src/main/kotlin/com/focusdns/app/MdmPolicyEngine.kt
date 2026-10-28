package com.focusdns.app

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.util.Log

/**
 * MdmPolicyEngine
 * ===============
 * Enterprise Mobile Device Management (MDM) & Device Owner Policy Orchestrator.
 *
 * Provides deep OS-level policy controls when enrolled as a Device Administrator,
 * Profile Owner, or Enterprise Device Owner.
 */
object MdmPolicyEngine {

    private const val TAG = "MdmPolicyEngine"

    fun getDevicePolicyManager(context: Context): DevicePolicyManager? {
        return context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
    }

    fun getAdminComponent(context: Context): ComponentName {
        return FocusDeviceAdminReceiver.getComponentName(context)
    }

    /**
     * Checks if FocusDNS is provisioned as the Enterprise Device Owner.
     */
    fun isDeviceOwner(context: Context): Boolean {
        val dpm = getDevicePolicyManager(context) ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            dpm.isDeviceOwnerApp(context.packageName)
        } else {
            false
        }
    }

    /**
     * Checks if FocusDNS is provisioned as a Profile Owner (e.g. Work Profile).
     */
    fun isProfileOwner(context: Context): Boolean {
        val dpm = getDevicePolicyManager(context) ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            dpm.isProfileOwnerApp(context.packageName)
        } else {
            false
        }
    }

    /**
     * Sets native OS-level uninstallation block using DevicePolicyManager.
     * Only available if provisioned as Device Owner or Profile Owner.
     */
    fun setUninstallBlocked(context: Context, packageName: String, blocked: Boolean): Boolean {
        val dpm = getDevicePolicyManager(context) ?: return false
        val admin = getAdminComponent(context)

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                if (isDeviceOwner(context) || isProfileOwner(context)) {
                    dpm.setUninstallBlocked(admin, packageName, blocked)
                    Log.i(TAG, "Native OS setUninstallBlocked($packageName, $blocked) applied successfully.")
                    true
                } else {
                    Log.d(TAG, "Device Owner / Profile Owner not active; native setUninstallBlocked skipped.")
                    false
                }
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply setUninstallBlocked: ${e.message}")
            false
        }
    }

    /**
     * Synchronizes native uninstallation block with current ProtectionStateCoordinator.canUninstall().
     */
    fun syncUninstallLock(context: Context) {
        val canUninstall = ProtectionStateCoordinator.canUninstall(context)
        val shouldBlock = !canUninstall
        setUninstallBlocked(context, context.packageName, shouldBlock)
    }

    /**
     * Configures Android Lock Task (Kiosk) mode packages.
     */
    fun setLockTaskPackages(context: Context, packages: Array<String>): Boolean {
        val dpm = getDevicePolicyManager(context) ?: return false
        val admin = getAdminComponent(context)

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                if (isDeviceOwner(context)) {
                    dpm.setLockTaskPackages(admin, packages)
                    Log.i(TAG, "Configured ${packages.size} Lock Task (Kiosk) packages.")
                    true
                } else {
                    false
                }
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set lock task packages: ${e.message}")
            false
        }
    }

    /**
     * Disables or enables hardware camera during high-security work sessions.
     */
    fun setCameraDisabled(context: Context, disabled: Boolean): Boolean {
        val dpm = getDevicePolicyManager(context) ?: return false
        val admin = getAdminComponent(context)

        return try {
            if (dpm.isAdminActive(admin)) {
                dpm.setCameraDisabled(admin, disabled)
                Log.i(TAG, "Hardware camera disabled set to: $disabled")
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set camera disabled: ${e.message}")
            false
        }
    }

    /**
     * Forces immediate lock screen.
     */
    fun lockNow(context: Context): Boolean {
        val dpm = getDevicePolicyManager(context) ?: return false
        val admin = getAdminComponent(context)

        return try {
            if (dpm.isAdminActive(admin)) {
                dpm.lockNow()
                Log.i(TAG, "Device locked immediately via MDM policy.")
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to lock device: ${e.message}")
            false
        }
    }

    /**
     * Gathers complete MDM capability status for Flutter UI.
     */
    fun getMdmCapabilities(context: Context): Map<String, Any> {
        val dpm = getDevicePolicyManager(context)
        val admin = getAdminComponent(context)
        val isAdminActive = dpm?.isAdminActive(admin) ?: false
        val isOwner = isDeviceOwner(context)
        val isProfile = isProfileOwner(context)

        val isCameraDisabled = try {
            if (isAdminActive && dpm != null) dpm.getCameraDisabled(admin) else false
        } catch (e: Exception) {
            false
        }

        return mapOf(
            "isDeviceAdminActive" to isAdminActive,
            "isDeviceOwner" to isOwner,
            "isProfileOwner" to isProfile,
            "isCameraDisabled" to isCameraDisabled,
            "canBlockUninstallNatively" to (isOwner || isProfile)
        )
    }
}
