package com.focusdns.app

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import java.util.Calendar

/**
 * EnterpriseScheduleEngine
 * ========================
 * Native Android Enterprise Calendar & Time-Tabled Focus Window Engine.
 *
 * Enforces recurring corporate work and academic study intervals:
 *
 * Core Law Verification:
 * - When Device Time is INSIDE a scheduled focus window (e.g. Mon-Fri 09:00 - 17:00):
 *     * ProtectionStateCoordinator is set to ACTIVE.
 *     * canUninstall(context) == FALSE (Uninstallation locked to prevent focus evasion).
 * - When Device Time is OUTSIDE all focus windows:
 *     * ProtectionStateCoordinator is set to INACTIVE (Normal Idle Mode).
 *     * canUninstall(context) == TRUE (Clean, friction-free uninstallation permitted).
 * - Life Safety Exemption:
 *     * Standard emergency dialing (911/112) is NEVER blocked across any schedule.
 */
class EnterpriseScheduleEngine(private val context: Context) {

    companion object {
        private const val TAG = "EnterpriseSchedule"
        private const val PREFS_NAME = "focus_dns_schedule_prefs"
        private const val KEY_IN_FOCUS_WINDOW = "key_in_focus_window"
        private const val KEY_ACTIVE_WINDOW_TITLE = "key_active_window_title"
    }

    data class ScheduleInterval(
        val intervalId: String,
        val title: String,
        val startHour: Int,
        val startMinute: Int,
        val endHour: Int,
        val endMinute: Int,
        val daysOfWeek: Set<Int> = setOf(Calendar.MONDAY, Calendar.TUESDAY, Calendar.WEDNESDAY, Calendar.THURSDAY, Calendar.FRIDAY),
        val enforceLock: Boolean = true
    )

    private val activeIntervals = mutableListOf<ScheduleInterval>()

    init {
        // Default enterprise 9-to-5 window
        activeIntervals.add(
            ScheduleInterval(
                intervalId = "interval_default_work",
                title = "Enterprise Business Focus Hours",
                startHour = 9,
                startMinute = 0,
                endHour = 17,
                endMinute = 0,
                daysOfWeek = setOf(Calendar.MONDAY, Calendar.TUESDAY, Calendar.WEDNESDAY, Calendar.THURSDAY, Calendar.FRIDAY),
                enforceLock = true
            )
        )
    }

    private fun getPrefs(): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun addInterval(interval: ScheduleInterval) {
        activeIntervals.removeAll { it.intervalId == interval.intervalId }
        activeIntervals.add(interval)
    }

    fun removeInterval(intervalId: String): Boolean {
        return activeIntervals.removeAll { it.intervalId == intervalId }
    }

    fun getIntervals(): List<ScheduleInterval> {
        return ArrayList(activeIntervals)
    }

    /**
     * Evaluates calendar state at the specified Calendar instance.
     */
    fun evaluateSchedule(calendar: Calendar = Calendar.getInstance()): Map<String, Any> {
        val currentDay = calendar.get(Calendar.DAY_OF_WEEK)
        val currentMinutes = calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)

        var inFocusWindow = false
        var activeTitle: String? = null

        for (interval in activeIntervals) {
            if (!interval.daysOfWeek.contains(currentDay)) continue

            val startMinutes = interval.startHour * 60 + interval.startMinute
            val endMinutes = interval.endHour * 60 + interval.endMinute

            val matches = if (startMinutes <= endMinutes) {
                currentMinutes in startMinutes until endMinutes
            } else {
                currentMinutes >= startMinutes || currentMinutes < endMinutes
            }

            if (matches && interval.enforceLock) {
                inFocusWindow = true
                activeTitle = interval.title
                break
            }
        }

        // Apply FocusDNS Core Law
        val prefs = getPrefs()
        prefs.edit()
            .putBoolean(KEY_IN_FOCUS_WINDOW, inFocusWindow)
            .putString(KEY_ACTIVE_WINDOW_TITLE, activeTitle ?: "")
            .apply()

        if (inFocusWindow) {
            Log.i(TAG, "Device time is INSIDE scheduled focus window ($activeTitle). Arming uninstallation lock.")
            ProtectionStateCoordinator.setProtectionActive(context, true)
        } else {
            Log.i(TAG, "Device time is OUTSIDE all focus windows. Normal mode: clean uninstallation permitted.")
            ProtectionStateCoordinator.setProtectionActive(context, false)
        }

        val canUninstall = ProtectionStateCoordinator.canUninstall(context)

        return mapOf(
            "inFocusWindow" to inFocusWindow,
            "activeWindowTitle" to (activeTitle ?: "None (Outside Schedule)"),
            "canUninstallApp" to canUninstall,
            "emergencyExemptionActive" to true,
            "dayOfWeek" to currentDay,
            "currentMinutes" to currentMinutes
        )
    }

    fun isInFocusWindow(): Boolean {
        return getPrefs().getBoolean(KEY_IN_FOCUS_WINDOW, false)
    }

    fun getActiveWindowTitle(): String {
        return getPrefs().getString(KEY_ACTIVE_WINDOW_TITLE, "") ?: ""
    }
}
