package com.focusdns.app.per_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Manages high-priority exact alarms for per-app timer expiration, immune to Doze mode and OEM battery task-killers.
 */
class DozeResilientAlarmScheduler(private val context: Context) {
    companion object {
        private const val TAG = "DozeResilientAlarmScheduler"
        const val ACTION_APP_TIMER_EXPIRED = "com.focusdns.app.ACTION_APP_TIMER_EXPIRED"
        const val EXTRA_APP_ID = "extra_app_id"
        const val EXTRA_PACKAGE_NAME = "extra_package_name"
    }

    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    /**
     * Schedules an exact alarm guaranteed to wake the system even in deep Doze mode.
     */
    fun scheduleExactExpiry(appId: String, packageName: String, triggerAtMillis: Long) {
        val intent = Intent(context, AppTimerBroadcastReceiver::class.java).apply {
            action = ACTION_APP_TIMER_EXPIRED
            putExtra(EXTRA_APP_ID, appId)
            putExtra(EXTRA_PACKAGE_NAME, packageName)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            appId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // setAlarmClock gives highest priority and bypasses all Doze restrictions
                val alarmClockInfo = AlarmManager.AlarmClockInfo(triggerAtMillis, pendingIntent)
                alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
                Log.d(TAG, "Scheduled AlarmClock for $appId at $triggerAtMillis")
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Exact alarm permission missing: ${e.message}")
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        }
    }

    /**
     * Cancels an existing alarm for an app.
     */
    fun cancelAlarm(appId: String) {
        val intent = Intent(context, AppTimerBroadcastReceiver::class.java).apply {
            action = ACTION_APP_TIMER_EXPIRED
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            appId.hashCode(),
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            Log.d(TAG, "Cancelled alarm for $appId")
        }
    }
}
