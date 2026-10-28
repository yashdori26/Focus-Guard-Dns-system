package com.focusdns.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

/**
 * FocusWatchdogService
 * ====================
 * Continuous background sentinel that ensures FocusDNS VPN and protection filters
 * are never silently killed by task killers or OS low-memory thrashing while
 * protection or strict focus countdown timers are active.
 */
class FocusWatchdogService : Service() {

    companion object {
        const val TAG = "FocusWatchdogService"
        const val NOTIFICATION_CHANNEL_ID = "focus_watchdog_channel"
        const val NOTIFICATION_ID = 9102
        const val HEARTBEAT_INTERVAL_MS = 15000L // 15 seconds
    }

    private val handler = Handler(Looper.getMainLooper())
    private var isWatchdogRunning = false

    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            checkServiceHealth()
            if (isWatchdogRunning) {
                handler.postDelayed(this, HEARTBEAT_INTERVAL_MS)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        isWatchdogRunning = true
        handler.post(heartbeatRunnable)
        Log.i(TAG, "FocusWatchdogService initialized and guarding.")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        isWatchdogRunning = false
        handler.removeCallbacks(heartbeatRunnable)
        Log.i(TAG, "FocusWatchdogService destroyed.")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun checkServiceHealth() {
        val shouldBeGuarded = ProtectionStateCoordinator.isProtectionActive(this) ||
            ProtectionStateCoordinator.isTimerActive(this)

        if (!shouldBeGuarded) {
            Log.i(TAG, "Protection and timers are idle. Standing down watchdog.")
            stopSelf()
            return
        }

        // Verify if FocusDnsVpnService is running
        if (!FocusDnsVpnService.isRunning) {
            Log.w(TAG, "Watchdog detected FocusDnsVpnService died while protection is active! Resurrecting...")
            try {
                val vpnIntent = Intent(this, FocusDnsVpnService::class.java).apply {
                    action = FocusDnsVpnService.ACTION_START
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(vpnIntent)
                } else {
                    startService(vpnIntent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Watchdog failed to revive VPN service: ${e.message}")
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Focus Sentinel Watchdog",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Monitors focus session integrity and self-healing protections."
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val remainingSec = ProtectionStateCoordinator.getRemainingTimerSeconds(this)
        val contentText = if (remainingSec > 0) {
            "Focus countdown active (${ProtectionStateCoordinator.formatRemainingTime(remainingSec)} remaining)"
        } else {
            "Active DNS protection guarded against interruption"
        }

        return builder
            .setContentTitle("Focus Guard Active Sentinel")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build()
    }
}
