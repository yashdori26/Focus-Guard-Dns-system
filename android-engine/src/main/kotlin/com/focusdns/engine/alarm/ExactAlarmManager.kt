package com.focusdns.engine.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.focusdns.engine.session.SessionStateMachineEngine

/**
 * Manages exact power-efficient OS wakeup alarms.
 * Note: Correctness NEVER depends on alarms firing on time; alarms merely wake the device.
 */
class ExactAlarmManager(private val context: Context) {

    companion object {
        const val TAG = "FocusExactAlarm"
        const val ACTION_SESSION_WAKEUP = "com.focusdns.engine.ACTION_SESSION_WAKEUP"
        const val REQUEST_CODE = 44201

        var stateMachineEngine: SessionStateMachineEngine? = null
    }

    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager

    /**
     * Arms a wakeup alarm for the specified target epoch.
     */
    fun scheduleWakeup(targetEpochMs: Long) {
        val am = alarmManager ?: return
        val now = System.currentTimeMillis()
        if (targetEpochMs <= now) {
            // Already expired; run catchup immediately
            stateMachineEngine?.evaluateCatchUp()
            return
        }

        val intent = Intent(context, SessionAlarmReceiver::class.java).apply {
            action = ACTION_SESSION_WAKEUP
            putExtra("targetEpochMs", targetEpochMs)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, targetEpochMs, pendingIntent)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, targetEpochMs, pendingIntent)
            }
            Log.i(TAG, "Scheduled exact wakeup for ${targetEpochMs - now}ms from now.")
        } catch (e: SecurityException) {
            Log.w(TAG, "SCHEDULE_EXACT_ALARM permission not granted, falling back to inexact alarm: ${e.message}")
            am.set(AlarmManager.RTC_WAKEUP, targetEpochMs, pendingIntent)
        }
    }

    fun cancelWakeup() {
        val am = alarmManager ?: return
        val intent = Intent(context, SessionAlarmReceiver::class.java).apply {
            action = ACTION_SESSION_WAKEUP
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_NO_CREATE
        }
        val pendingIntent = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
        if (pendingIntent != null) {
            am.cancel(pendingIntent)
            pendingIntent.cancel()
            Log.i(TAG, "Canceled session wakeup alarm.")
        }
    }
}

/**
 * BroadcastReceiver triggered by AlarmManager.
 */
class SessionAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        Log.i(ExactAlarmManager.TAG, "Exact alarm wakeup received. Executing catch-up evaluation.")
        ExactAlarmManager.stateMachineEngine?.evaluateCatchUp()
    }
}

/**
 * Handles device boot, package upgrades, and system clock adjustments.
 */
class BootWatchdogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        Log.i("FocusBootWatchdog", "System event received: $action. Evaluating engine state.")

        // Run catch-up evaluation on reboot / clock change
        ExactAlarmManager.stateMachineEngine?.evaluateCatchUp()
    }
}
