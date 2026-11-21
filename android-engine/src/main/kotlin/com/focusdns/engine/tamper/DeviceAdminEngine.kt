package com.focusdns.engine.tamper

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.focusdns.engine.session.SessionStateMachineEngine

/**
 * Device Admin Receiver guarding uninstallation and admin deactivation
 * during active Strict Mode or Focus Cycles routines.
 */
class FocusDeviceAdminReceiver : DeviceAdminReceiver() {

    companion object {
        const val TAG = "FocusDeviceAdmin"
        var stateMachineEngine: SessionStateMachineEngine? = null
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(TAG, "FocusDNS Device Admin successfully enabled.")
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence? {
        val isLocked = stateMachineEngine?.currentSnapshot?.isStrictLockout == true

        if (isLocked) {
            Log.w(TAG, "Anti-Tamper Warning: Device Admin deactivation attempted during strict lockout. REJECTED.")
            return "FocusDNS Strict Mode is currently ACTIVE and unbreakable! Device Admin cannot be disabled until your session completes."
        }

        return "Warning: Disabling FocusDNS Device Admin removes uninstallation protection and shield enforcement."
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.w(TAG, "FocusDNS Device Admin was disabled by user.")
    }
}
