package com.focusdns.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * BootWatchdogReceiver
 * ====================
 * Restores FocusDNS VPN Protection and Strict Monotonic Timers across device reboots,
 * application updates, and network reconnections.
 */
class BootWatchdogReceiver : BroadcastReceiver() {

    companion object {
        const val TAG = "BootWatchdog"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        Log.i(TAG, "Watchdog received system event: $action")

        val shouldRevive = ProtectionStateCoordinator.isProtectionActive(context) ||
            ProtectionStateCoordinator.isTimerActive(context) ||
            RulesStore.getWasRunning(context)

        if (shouldRevive) {
            Log.w(TAG, "Protection or focus timer was active before system event ($action). Reviving VPN...")

            try {
                val vpnIntent = Intent(context, FocusDnsVpnService::class.java).apply {
                    this.action = FocusDnsVpnService.ACTION_START
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(vpnIntent)
                } else {
                    context.startService(vpnIntent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to auto-restart FocusDnsVpnService: ${e.message}")
            }

            try {
                val watchdogIntent = Intent(context, FocusWatchdogService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(watchdogIntent)
                } else {
                    context.startService(watchdogIntent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start FocusWatchdogService: ${e.message}")
            }
        } else {
            Log.i(TAG, "Session is idle. No automatic revival needed.")
        }
    }
}
