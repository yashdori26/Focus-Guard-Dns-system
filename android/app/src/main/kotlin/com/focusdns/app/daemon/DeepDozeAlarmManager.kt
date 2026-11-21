package com.focusdns.app.daemon

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * DeepDozeAlarmManager
 * ====================
 * High-precision exact alarm scheduler that pierces Android 6.0+ deep Doze mode
 * and App Standby Buckets using `AlarmManager.setAlarmClock()`.
 *
 * `setAlarmClock()` is an official Android API designed for time-critical alarms.
 * It wakes the CPU from deep idle at the exact designated millisecond, bypassing
 * battery saver throttling and Doze maintenance windows.
 */
object DeepDozeAlarmManager {

    private const val TAG = "DeepDozeAlarmManager"
    const val ACTION_DOZE_TICK = "com.focusdns.app.action.DOZE_ALARM_TICK"

    fun scheduleDeepDozeAlarm(
        context: Context,
        triggerAtMillis: Long,
        requestCode: Int = 9021
    ): Boolean {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false

        val intent = Intent(ACTION_DOZE_TICK).apply {
            setPackage(context.packageName)
            putExtra("trigger_timestamp", triggerAtMillis)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getBroadcast(context, requestCode, intent, flags)

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val alarmClockInfo = AlarmManager.AlarmClockInfo(triggerAtMillis, pendingIntent)
                alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
                Log.d(TAG, "Scheduled setAlarmClock at $triggerAtMillis (Pierces Deep Doze)")
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
                Log.d(TAG, "Scheduled setExact at $triggerAtMillis")
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "setAlarmClock failed, falling back to setExactAndAllowWhileIdle: ${e.message}")
            tryFallback(alarmManager, triggerAtMillis, pendingIntent)
        }
    }

    private fun tryFallback(alarmManager: AlarmManager, triggerAtMillis: Long, pendingIntent: PendingIntent): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
                Log.d(TAG, "Scheduled setExactAndAllowWhileIdle fallback at $triggerAtMillis")
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Fallback alarm failed: ${e.message}")
            false
        }
    }

    fun cancelAlarm(context: Context, requestCode: Int = 9021) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(ACTION_DOZE_TICK).apply { setPackage(context.packageName) }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_NO_CREATE
        }
        val pendingIntent = PendingIntent.getBroadcast(context, requestCode, intent, flags)
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            Log.d(TAG, "Deep Doze alarm cancelled.")
        }
    }
}
