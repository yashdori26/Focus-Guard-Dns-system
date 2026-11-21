package com.focusdns.app.daemon

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log

/**
 * OemSpecificWatchdog
 * ===================
 * Adapts watchdog wakeup intervals based on OEM background killer hostility.
 * For example: Xiaomi HyperOS and Huawei EMUI require high-frequency keepalives
 * and AlarmClock deep-Doze piercers to survive aggressive RAM reclaimers.
 */
object OemSpecificWatchdog {

    private const val TAG = "OemSpecificWatchdog"
    private const val WATCHDOG_ACTION = "com.focusdns.app.action.OEM_HEARTBEAT"
    private const val REQUEST_CODE = 8841

    fun scheduleAdaptiveKeepalive(context: Context, intervalSeconds: Long = 180) {
        val alarmManager = context.getSystemService(Context.POWER_SERVICE) as? AlarmManager
            ?: context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: return

        val intent = Intent(WATCHDOG_ACTION).apply {
            setPackage(context.packageName)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)

        val triggerAtMillis = SystemClock.elapsedRealtime() + (intervalSeconds * 1000)

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
            Log.d(TAG, "Adaptive keepalive scheduled in $intervalSeconds seconds.")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to schedule adaptive keepalive: ${e.message}")
        }
    }

    fun cancelKeepalive(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(WATCHDOG_ACTION).apply { setPackage(context.packageName) }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_NO_CREATE
        }
        val pendingIntent = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            Log.d(TAG, "Adaptive keepalive cancelled.")
        }
    }
}
