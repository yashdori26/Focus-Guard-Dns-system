package com.focusdns.app.daemon

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.focusdns.app.FocusDnsVpnService
import com.focusdns.app.FocusWatchdogService
import com.focusdns.app.ProtectionStateCoordinator

/**
 * DeviceBootReceiver
 * ==================
 * Multi-broadcast boot receiver listening for cold boot, locked boot, app upgrade,
 * and OEM quick-boot events.
 *
 * Guarantees that active strict timers and DNS filtering cannot be bypassed
 * simply by rebooting the smartphone.
 */
class DeviceBootReceiver : BroadcastReceiver() {

    companion object {
        const val TAG = "DeviceBootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.i(TAG, "DeviceBootReceiver triggered with action: $action")

        val shouldGuard = ProtectionStateCoordinator.isProtectionActive(context) ||
            ProtectionStateCoordinator.isTimerActive(context)

        if (!shouldGuard) {
            Log.d(TAG, "Protection was inactive before reboot. No action required.")
            return
        }

        Log.i(TAG, "Active focus protection detected post-boot! Resurrecting daemon services...")

        try {
            // 1. Resurrect VPN Service
            val vpnIntent = Intent(context, FocusDnsVpnService::class.java).apply {
                this.action = FocusDnsVpnService.ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(vpnIntent)
            } else {
                context.startService(vpnIntent)
            }

            // 2. Resurrect Watchdog Service
            val watchdogIntent = Intent(context, FocusWatchdogService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(watchdogIntent)
            } else {
                context.startService(watchdogIntent)
            }

            // 3. Reschedule Doze Alarm
            val remainingSec = ProtectionStateCoordinator.getRemainingTimerSeconds(context)
            if (remainingSec > 0) {
                val triggerAt = System.currentTimeMillis() + (remainingSec * 1000)
                DeepDozeAlarmManager.scheduleDeepDozeAlarm(context, triggerAt)
            }

            Log.i(TAG, "All background daemons restored successfully after boot.")
        } catch (e: Exception) {
            Log.e(TAG, "Error resurrecting services on boot: ${e.message}")
        }
    }
}
