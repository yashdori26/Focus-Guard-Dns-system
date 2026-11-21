package com.focusdns.app.daemon

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.util.Log

/**
 * LowMemoryKillerShield
 * =====================
 * Protects FocusDNS background daemon services from Android's Low Memory Killer (LMK).
 *
 * Strategies:
 * 1. oom_adj Score Elevation: Uses ongoing Foreground Service with IMPORTANCE_LOW channel.
 * 2. Memory Trimming: Implements ComponentCallbacks2 to release memory during TRIM_MEMORY events,
 *    preventing the kernel from targeting FocusDNS for termination.
 */
class LowMemoryKillerShield(private val context: Context) : ComponentCallbacks2 {

    companion object {
        const val TAG = "LowMemoryKillerShield"
        const val CHANNEL_ID = "focus_daemon_channel"
        const val NOTIFICATION_ID = 9180
    }

    private var onTrimMemoryCallback: ((Int) -> Unit)? = null

    fun initialize(onTrimCallback: ((Int) -> Unit)? = null) {
        this.onTrimMemoryCallback = onTrimCallback
        createNotificationChannel()
        context.registerComponentCallbacks(this)
        Log.i(TAG, "LowMemoryKillerShield initialized.")
    }

    fun release() {
        try {
            context.unregisterComponentCallbacks(this)
        } catch (_: Exception) {}
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Focus Daemon Background Protection",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps DNS filtering daemon running with zero battery drain."
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    fun buildSilentNotification(statusText: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        return builder
            .setContentTitle("FocusDNS Active Shield")
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_LOW)
            .build()
    }

    override fun onTrimMemory(level: Int) {
        Log.w(TAG, "OS Memory Pressure Warning! Trim level: $level")
        when (level) {
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL,
            ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> {
                Log.e(TAG, "Critical memory threshold reached. Releasing transient buffers.")
                onTrimMemoryCallback?.invoke(level)
                System.gc()
            }
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW,
            ComponentCallbacks2.TRIM_MEMORY_MODERATE -> {
                onTrimMemoryCallback?.invoke(level)
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {}
    override fun onLowMemory() {
        Log.e(TAG, "onLowMemory received! Performing emergency buffer dump.")
        onTrimMemoryCallback?.invoke(ComponentCallbacks2.TRIM_MEMORY_COMPLETE)
        System.gc()
    }
}
