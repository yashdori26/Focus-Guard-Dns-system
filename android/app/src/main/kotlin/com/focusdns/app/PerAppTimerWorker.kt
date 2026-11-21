package com.focusdns.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log

/**
 * PerAppTimerWorker
 * =================
 * Handles high-precision AlarmManager wakeup events for independent per-app timers.
 * Guarantees that when an individual application's lock duration expires (e.g., YouTube after 2h),
 * it is automatically unblocked without requiring the user to open the FocusDNS app or wake the screen.
 */
class PerAppTimerWorker : BroadcastReceiver() {

    companion object {
        const val TAG = "PerAppTimerWorker"
        const val ACTION_APP_TIMER_EXPIRED = "com.focusdns.app.action.APP_TIMER_EXPIRED"
        const val EXTRA_APP_ID = "EXTRA_APP_ID"
        const val EXTRA_PACKAGE_NAME = "EXTRA_PACKAGE_NAME"

        /**
         * Schedules an exact non-wakeful or while-idle alarm for when an app lock duration completes.
         */
        fun scheduleAppLockExpiry(context: Context, appId: String, packageName: String, durationSeconds: Long) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, PerAppTimerWorker::class.java).apply {
                action = ACTION_APP_TIMER_EXPIRED
                putExtra(EXTRA_APP_ID, appId)
                putExtra(EXTRA_PACKAGE_NAME, packageName)
            }

            val requestCode = appId.hashCode()
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val pendingIntent = PendingIntent.getBroadcast(context, requestCode, intent, flags)
            val triggerAtMillis = SystemClock.elapsedRealtime() + (durationSeconds * 1000L)

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                } else {
                    alarmManager.setExact(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                }
                Log.i(TAG, "Scheduled exact lock expiration for $appId ($packageName) in ${durationSeconds}s.")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to schedule exact alarm for $appId: ${e.message}")
            }
        }

        /**
         * Cancels any pending expiry alarm for an app (e.g. if manually unlocked).
         */
        fun cancelAppLockExpiry(context: Context, appId: String) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, PerAppTimerWorker::class.java).apply {
                action = ACTION_APP_TIMER_EXPIRED
            }
            val requestCode = appId.hashCode()
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_NO_CREATE
            }
            val pendingIntent = PendingIntent.getBroadcast(context, requestCode, intent, flags)
            if (pendingIntent != null) {
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
                Log.i(TAG, "Canceled expiration alarm for $appId.")
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_APP_TIMER_EXPIRED) {
            val appId = intent.getStringExtra(EXTRA_APP_ID) ?: return
            val packageName = intent.getStringExtra(EXTRA_PACKAGE_NAME) ?: ""

            Log.i(TAG, "App lock timer expired for $appId ($packageName). Releasing block.")

            // 1. Remove package from native blocked packages list
            val currentBlocked = RulesStore.getBlockedPackages(context).toMutableList()
            if (currentBlocked.remove(packageName)) {
                RulesStore.setBlockedPackages(context, currentBlocked)
            }

            // 2. Resynchronize VPN rules without this package's domains
            val currentVpnRules = RulesStore.getBlockedDomains(context).toMutableList()
            RulesStore.setBlockedDomains(context, currentVpnRules)
        }
    }
}
