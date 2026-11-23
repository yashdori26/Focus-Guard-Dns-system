package com.focusdns.focus_dns

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * FocusDeviceAdminReceiver
 * ========================
 * Implements Android Enterprise Device Administration.
 * Prevents accidental or impulsive uninstallation during active strict focus sessions.
 */
class FocusDeviceAdminReceiver : DeviceAdminReceiver() {

    companion object {
        const val TAG = "FocusDeviceAdmin"

        fun getComponentName(context: Context): ComponentName {
            return ComponentName(context, FocusDeviceAdminReceiver::class.java)
        }

        fun isDeviceAdminActive(context: Context): Boolean {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
            return dpm?.isAdminActive(getComponentName(context)) ?: false
        }

        fun createAddDeviceAdminIntent(context: Context): Intent {
            return Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, getComponentName(context))
                putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "FocusDNS requires Device Administrator privileges to lock active focus sessions " +
                    "and prevent accidental uninstallation while strict timers are running."
                )
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
        }

        fun requestDeactivate(context: Context): Boolean {
            val db = LocalDb.get(context)
            val until = db.getKv("strict_until", "0").toLongOrNull() ?: 0L
            val remaining = (until - System.currentTimeMillis()) / 1000
            if (remaining > 0 || FocusDnsVpnService.isRunning) {
                Log.w(TAG, "Deactivation rejected: Strict mode or VPN is still active.")
                return false
            }
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
            dpm?.removeActiveAdmin(getComponentName(context))
            return true
        }
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence? {
        val db = LocalDb.get(context)
        val until = db.getKv("strict_until", "0").toLongOrNull() ?: 0L
        val remaining = (until - System.currentTimeMillis()) / 1000
        val isRunning = FocusDnsVpnService.isRunning

        if (remaining > 0) {
            val mins = (remaining / 60) + 1
            return "⚠️ FOCUS SESSION IN PROGRESS ($mins min remaining)\n\n" +
                   "Uninstallation and Device Administrator deactivation are locked until your strict timer expires."
        }
        if (isRunning) {
            return "⚠️ PROTECTION ACTIVE\n\n" +
                   "FocusDNS protection is currently running. Please turn off protection in the app first to uninstall."
        }
        return null
    }
}
