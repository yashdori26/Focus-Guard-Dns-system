package com.focusdns.app.per_app

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * High-performance Lockout HUD overlay drawn above restricted apps using TYPE_APPLICATION_OVERLAY.
 */
class PerAppOverlayWindow(private val context: Context) {
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var overlayView: View? = null
    private var isShowing = false

    fun show(
        appName: String,
        remainingMinutes: Int,
        blockedAttempts: Int,
        productiveAppName: String,
        productiveAppPackage: String
    ) {
        if (!Settings.canDrawOverlays(context) || isShowing) return

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#E6090D16"))
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
        }

        val title = TextView(context).apply {
            text = "🛡️ Focus Shield Active"
            textSize = 24f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 16)
        }

        val appLockedText = TextView(context).apply {
            text = "$appName is strictly locked"
            textSize = 18f
            setTextColor(Color.parseColor("#FF5252"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 24)
        }

        val countdownText = TextView(context).apply {
            text = "Time Remaining: $remainingMinutes mins"
            textSize = 16f
            setTextColor(Color.parseColor("#90CAF9"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 12)
        }

        val attemptsText = TextView(context).apply {
            text = "Blocked launch attempts: $blockedAttempts"
            textSize = 14f
            setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 32)
        }

        val productiveBtn = Button(context).apply {
            text = "Open $productiveAppName instead"
            setBackgroundColor(Color.parseColor("#2E7D32"))
            setTextColor(Color.WHITE)
            setOnClickListener {
                val intent = context.packageManager.getLaunchIntentForPackage(productiveAppPackage)
                    ?: Intent(Intent.ACTION_VIEW, Uri.parse("https://google.com"))
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                hide()
            }
        }

        val homeBtn = Button(context).apply {
            text = "Return to Home Screen"
            setBackgroundColor(Color.parseColor("#37474F"))
            setTextColor(Color.WHITE)
            setOnClickListener {
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(homeIntent)
                hide()
            }
        }

        root.addView(title)
        root.addView(appLockedText)
        root.addView(countdownText)
        root.addView(attemptsText)
        root.addView(productiveBtn)
        root.addView(homeBtn)

        windowManager.addView(root, layoutParams)
        overlayView = root
        isShowing = true
    }

    fun hide() {
        if (isShowing && overlayView != null) {
            windowManager.removeView(overlayView)
            overlayView = null
            isShowing = false
        }
    }
}
