package com.focusdns.app

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.UserHandle
import android.util.Log

/**
 * FocusDeviceAdminReceiver
 * ========================
 * Implements Android Enterprise Device Administration (android.app.admin.DeviceAdminReceiver).
 *
 * Responsibilities:
 * 1. Blocks Device Administrator deactivation whenever Protection Mode or a Strict Countdown Timer is active.
 * 2. Allows clean, effortless deactivation once protection is stopped and the timer has expired.
 * 3. Launches the countdown overlay dialog whenever an unauthorized deactivation attempt is made.
 */
class FocusDeviceAdminReceiver : DeviceAdminReceiver() {

    companion object {
        const val TAG = "FocusDeviceAdmin"

        /**
         * Returns the ComponentName identifying this DeviceAdminReceiver.
         */
        fun getComponentName(context: Context): ComponentName {
            return ComponentName(context, FocusDeviceAdminReceiver::class.java)
        }

        /**
         * Checks whether FocusDNS is currently registered as an active Device Administrator.
         */
        fun isDeviceAdminActive(context: Context): Boolean {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
            val adminComponent = getComponentName(context)
            return dpm?.isAdminActive(adminComponent) ?: false
        }

        /**
         * Creates an Intent to prompt the user to activate FocusDNS as a Device Administrator.
         */
        fun createAddDeviceAdminIntent(context: Context): Intent {
            val adminComponent = getComponentName(context)
            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "Focus Guard requires Device Administrator permission to protect active focus sessions " +
                    "and prevent accidental or impulsive uninstallation while focus timers are running."
                )
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            return intent
        }

        /**
         * Deactivates Device Administrator privileges.
         * Only succeeds if ProtectionStateCoordinator.canDeactivateDeviceAdmin(context) is TRUE.
         */
        fun requestDeactivate(context: Context): Boolean {
            if (!ProtectionStateCoordinator.canDeactivateDeviceAdmin(context)) {
                Log.w(TAG, "Deactivation rejected: Focus session or protection is still active.")
                return false
            }
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
            val adminComponent = getComponentName(context)
            dpm?.removeActiveAdmin(adminComponent)
            ProtectionStateCoordinator.setDeviceAdminActive(context, false)
            Log.i(TAG, "Device Administrator removed cleanly by user request.")
            return true
        }
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        ProtectionStateCoordinator.setDeviceAdminActive(context, true)
        Log.i(TAG, "FocusDNS Device Administrator successfully enabled.")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        ProtectionStateCoordinator.setDeviceAdminActive(context, false)
        Log.i(TAG, "FocusDNS Device Administrator successfully disabled.")
    }

    /**
     * Called when the user attempts to deactivate FocusDNS in Android Settings.
     *
     * Core Rule:
     * - If Protection or Timer is active: Returns warning message and opens countdown warning screen.
     * - If Protection is OFF and Timer is 0: Returns null (allows clean deactivation).
     */
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence? {
        val canDeactivate = ProtectionStateCoordinator.canDeactivateDeviceAdmin(context)

        if (!canDeactivate) {
            val remainingSec = ProtectionStateCoordinator.getRemainingTimerSeconds(context)
            val formattedTime = ProtectionStateCoordinator.formatRemainingTime(remainingSec)
            val isProtectionOn = ProtectionStateCoordinator.isProtectionActive(context)

            Log.w(TAG, "Device Admin deactivation attempted while locked! Remaining: $formattedTime, Protection: $isProtectionOn")

            // Launch the ProtectionLockWarningActivity to display real-time countdown
            try {
                val warningIntent = Intent(context, ProtectionLockWarningActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra("EXTRA_REMAINING_SECONDS", remainingSec)
                    putExtra("EXTRA_REASON", "ADMIN_DEACTIVATION_BLOCKED")
                }
                context.startActivity(warningIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch warning activity: ${e.message}")
            }

            return if (remainingSec > 0) {
                "⚠️ FOCUS SESSION IN PROGRESS ($formattedTime remaining)\n\n" +
                "Uninstallation and Device Administrator deactivation are locked until your countdown timer expires."
            } else {
                "⚠️ PROTECTION MODE ACTIVE\n\n" +
                "Focus Guard DNS protection is currently running. Please turn off protection in the app first to uninstall."
            }
        }

        // Allowed! Return null to allow unhindered deactivation
        Log.i(TAG, "Device Admin deactivation authorized (Session is idle).")
        return null
    }

    override fun onPasswordFailed(context: Context, intent: Intent, user: UserHandle) {
        super.onPasswordFailed(context, intent, user)
        Log.w(TAG, "Device unlock password failed on user: $user")
    }

    override fun onPasswordSucceeded(context: Context, intent: Intent, user: UserHandle) {
        super.onPasswordSucceeded(context, intent, user)
        Log.i(TAG, "Device unlock password succeeded on user: $user")
    }

    override fun onLockTaskModeEntering(context: Context, intent: Intent, pkg: String) {
        super.onLockTaskModeEntering(context, intent, pkg)
        Log.i(TAG, "Device entered Lock Task (Kiosk) Mode for package: $pkg")
    }

    override fun onLockTaskModeExiting(context: Context, intent: Intent) {
        super.onLockTaskModeExiting(context, intent)
        Log.i(TAG, "Device exited Lock Task Mode.")
    }
}
