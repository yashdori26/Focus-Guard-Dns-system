package com.focusdns.app.per_app

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.util.Log

/**
 * High-precision foreground app usage monitor querying UsageStatsManager with milli-resolution.
 */
class PerAppUsageStatsManager(private val context: Context) {
    companion object {
        private const val TAG = "PerAppUsageStatsManager"
    }

    private val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
    private var lastForegroundPackage: String? = null
    private var foregroundStartTimeMs: Long = 0

    /**
     * Inspects UsageEvents to determine the currently active foreground package name.
     */
    fun getForegroundPackageName(): String? {
        if (usageStatsManager == null) return null

        val now = System.currentTimeMillis()
        val events = usageStatsManager.queryEvents(now - 10_000, now) ?: return null
        val event = UsageEvents.Event()

        var latestPackage: String? = null
        var latestTimestamp: Long = 0

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED && event.timeStamp > latestTimestamp) {
                latestPackage = event.packageName
                latestTimestamp = event.timeStamp
            }
        }

        return latestPackage ?: lastForegroundPackage
    }

    /**
     * Tracks delta usage for the current foreground application.
     */
    fun pollUsageDelta(): Pair<String, Long>? {
        val current = getForegroundPackageName() ?: return null
        val now = System.currentTimeMillis()

        if (current != lastForegroundPackage) {
            val prevPackage = lastForegroundPackage
            val duration = if (foregroundStartTimeMs > 0) now - foregroundStartTimeMs else 0
            lastForegroundPackage = current
            foregroundStartTimeMs = now

            if (prevPackage != null && duration > 500) {
                return Pair(prevPackage, duration / 1000)
            }
        }
        return null
    }
}
