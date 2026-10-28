package com.focusdns.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * FocusLockOverlayService
 * =======================
 * Floating System Alert Window (TYPE_APPLICATION_OVERLAY) for FocusDNS.
 *
 * Displays a non-dismissible, calm Wabi-Sabi digital countdown HUD overlay
 * when the user attempts to circumvent a strict focus session or force-stop
 * the device administration service.
 *
 * Critical Guarantees:
 * 1. Prominently provides an emergency SOS button allowing direct access to the native dialer.
 * 2. Automatically removes itself and terminates when `canUninstall()` becomes true (timer reaches 00:00:00).
 */
class FocusLockOverlayService : Service() {

    companion object {
        private const val TAG = "FocusLockOverlay"
        private const val NOTIFICATION_ID = 9102
        private const val CHANNEL_ID = "focus_lock_overlay_channel"

        const val ACTION_SHOW_OVERLAY = "com.focusdns.app.action.SHOW_OVERLAY"
        const val ACTION_HIDE_OVERLAY = "com.focusdns.app.action.HIDE_OVERLAY"
        const val EXTRA_REASON = "EXTRA_REASON"

        @Volatile
        var isOverlayShowing: Boolean = false
            private set

        fun show(context: Context, reason: String = "FOCUS_SESSION_ACTIVE") {
            if (!OverlayPermissionHelper.canDrawOverlays(context)) {
                Log.w(TAG, "Cannot show overlay: SYSTEM_ALERT_WINDOW permission missing.")
                return
            }
            val intent = Intent(context, FocusLockOverlayService::class.java).apply {
                action = ACTION_SHOW_OVERLAY
                putExtra(EXTRA_REASON, reason)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun hide(context: Context) {
            val intent = Intent(context, FocusLockOverlayService::class.java).apply {
                action = ACTION_HIDE_OVERLAY
            }
            context.startService(intent)
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private var updateRunnable: Runnable? = null
    private var stateChangeListener: ProtectionStateCoordinator.StateChangeListener? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildForegroundNotification())

        windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        val listener = object : ProtectionStateCoordinator.StateChangeListener {
            override fun onProtectionStateChanged(
                sessionState: ProtectionStateCoordinator.SessionState,
                canUninstall: Boolean,
                remainingSeconds: Long
            ) {
                checkAutoDismiss()
            }
        }
        stateChangeListener = listener
        ProtectionStateCoordinator.registerListener(listener)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_SHOW_OVERLAY
        if (action == ACTION_HIDE_OVERLAY) {
            removeOverlay()
            stopSelf()
            return START_NOT_STICKY
        }

        val reason = intent?.getStringExtra(EXTRA_REASON) ?: "FOCUS_SESSION_ACTIVE"
        displayOverlay(reason)
        return START_STICKY
    }

    private fun displayOverlay(reason: String) {
        if (overlayView != null) {
            updateViews(reason)
            return
        }

        val wm = windowManager ?: return

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        val rootLayout = createOverlayLayout(reason)
        try {
            wm.addView(rootLayout, params)
            overlayView = rootLayout
            isOverlayShowing = true
            startCountdownTimer()
            Log.i(TAG, "Floating HUD overlay view added to WindowManager.")
        } catch (e: Exception) {
            Log.e(TAG, "Failed adding overlay view: ${e.message}")
        }
    }

    private fun createOverlayLayout(reason: String): View {
        val context = this
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#E6141416")) // 90% opaque dark obsidian
            setPadding(48, 64, 48, 64)

            // 1. Icon & Header
            val titleView = TextView(context).apply {
                text = "🔒 Focus Lock Engaged"
                textSize = 22f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
            }
            addView(titleView)

            // 2. Reason Subtitle
            val reasonView = TextView(context).apply {
                tag = "tag_reason"
                text = "Uninstallation and settings evasion are guarded.\nReason: $reason"
                textSize = 14f
                setTextColor(Color.parseColor("#888888"))
                gravity = Gravity.CENTER
                setPadding(0, 16, 0, 32)
            }
            addView(reasonView)

            // 3. Digital Countdown Display
            val timerView = TextView(context).apply {
                tag = "tag_timer"
                val remainingSec = ProtectionStateCoordinator.getRemainingTimerSeconds(context)
                text = formatRemainingTime(remainingSec)
                textSize = 48f
                typeface = Typeface.MONOSPACE
                setTextColor(Color.parseColor("#E5A93C")) // Wabi-Sabi Amber
                gravity = Gravity.CENTER
                setPadding(0, 16, 0, 32)
            }
            addView(timerView)

            // 4. Calming Philosophical Message
            val quoteView = TextView(context).apply {
                text = "\"Simplicity is the ultimate sophistication.\nLet this moment pass naturally.\""
                textSize = 13f
                typeface = Typeface.DEFAULT
                setTextColor(Color.parseColor("#666666"))
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, 48)
            }
            addView(quoteView)

            // 5. Emergency SOS Exemption Button
            val sosButton = Button(context).apply {
                text = "🆘 Emergency SOS (112)"
                textSize = 14f
                setTextColor(Color.WHITE)
                setBackgroundColor(Color.parseColor("#D32F2F"))
                setOnClickListener {
                    EmergencyCallExemptionManager.launchEmergencyDialer(context, "112")
                }
            }
            addView(sosButton)
        }
    }

    private fun startCountdownTimer() {
        updateRunnable?.let { handler.removeCallbacks(it) }
        val runnable = object : Runnable {
            override fun run() {
                val remainingSec = ProtectionStateCoordinator.getRemainingTimerSeconds(this@FocusLockOverlayService)
                val timerView = overlayView?.findViewWithTag<TextView>("tag_timer")
                timerView?.text = formatRemainingTime(remainingSec)

                if (remainingSec <= 0 && !ProtectionStateCoordinator.isProtectionActive(this@FocusLockOverlayService)) {
                    Log.i(TAG, "Focus timer reached zero! Auto-dismissing overlay.")
                    removeOverlay()
                    stopSelf()
                } else {
                    handler.postDelayed(this, 1000L)
                }
            }
        }
        updateRunnable = runnable
        handler.post(runnable)
    }

    private fun checkAutoDismiss() {
        val canUninstall = ProtectionStateCoordinator.canUninstall(this)
        if (canUninstall) {
            handler.post {
                removeOverlay()
                stopSelf()
            }
        }
    }

    private fun updateViews(reason: String) {
        val reasonView = overlayView?.findViewWithTag<TextView>("tag_reason")
        reasonView?.text = "Uninstallation and settings evasion are guarded.\nReason: $reason"
    }

    private fun removeOverlay() {
        updateRunnable?.let { handler.removeCallbacks(it) }
        updateRunnable = null
        if (overlayView != null && windowManager != null) {
            try {
                windowManager?.removeView(overlayView)
                Log.i(TAG, "Floating HUD overlay removed from WindowManager.")
            } catch (e: Exception) {
                Log.d(TAG, "Error removing overlay view: ${e.message}")
            }
            overlayView = null
            isOverlayShowing = false
        }
    }

    private fun formatRemainingTime(seconds: Long): String {
        val s = if (seconds < 0) 0 else seconds
        val hours = s / 3600
        val minutes = (s % 3600) / 60
        val secs = s % 60
        return if (hours > 0) {
            String.format("%02d:%02d:%02d", hours, minutes, secs)
        } else {
            String.format("%02d:%02d", minutes, secs)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Focus Lock Overlay",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Displays floating countdown HUD during guarded focus sessions."
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Focus Guard Active")
            .setContentText("Focus session is actively guarded.")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        removeOverlay()
        stateChangeListener?.let {
            ProtectionStateCoordinator.unregisterListener(it)
        }
        stateChangeListener = null
        super.onDestroy()
        Log.i(TAG, "FocusLockOverlayService destroyed.")
    }
}
