package com.focusdns.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * ProtectionLockWarningActivity
 * ==============================
 * Displayed when an uninstallation, force-stop, or device admin deactivation is attempted
 * while FocusDNS Protection Mode or a Strict Countdown Timer is active.
 *
 * Provides a serene, focused interface with a live ticking countdown and explains
 * that uninstallation unlocks automatically when the timer reaches zero.
 */
class ProtectionLockWarningActivity : Activity() {

    companion object {
        fun launch(context: Context, reason: String = "FOCUS_ACTIVE") {
            val intent = Intent(context, ProtectionLockWarningActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("EXTRA_REASON", reason)
            }
            context.startActivity(intent)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var timerTextView: TextView? = null
    private var statusDescTextView: TextView? = null

    private val tickerRunnable = object : Runnable {
        override fun run() {
            updateCountdownUI()
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Set window to dark Wabi-Sabi theme
        window.statusBarColor = Color.parseColor("#121212")
        window.navigationBarColor = Color.parseColor("#121212")

        val rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#121212"))
            setPadding(dp(28), dp(40), dp(28), dp(40))
        }

        // Shield Icon
        val icon = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_lock_lock)
            setColorFilter(Color.parseColor("#E0E0E0"))
            val iconSize = dp(64)
            layoutParams = LinearLayout.LayoutParams(iconSize, iconSize).apply {
                bottomMargin = dp(24)
            }
        }
        rootLayout.addView(icon)

        // Title
        val titleText = TextView(this).apply {
            text = "Focus Protection Active"
            textSize = 24f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.parseColor("#FFFFFF"))
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = dp(16)
            }
        }
        rootLayout.addView(titleText)

        // Digital Countdown Clock
        timerTextView = TextView(this).apply {
            text = "00:00"
            textSize = 48f
            typeface = Typeface.MONOSPACE
            setTextColor(Color.parseColor("#4CAF50"))
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = dp(20)
            }
        }
        rootLayout.addView(timerTextView)

        // Description / Explanation
        statusDescTextView = TextView(this).apply {
            textSize = 15f
            setTextColor(Color.parseColor("#B0B0B0"))
            gravity = Gravity.CENTER
            setLineSpacing(dp(4).toFloat(), 1.1f)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = dp(36)
            }
        }
        rootLayout.addView(statusDescTextView)

        // Action Button: Return to Home
        val homeButton = Button(this).apply {
            text = "Return to Home Screen"
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.parseColor("#121212"))
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(Color.parseColor("#FFFFFF"))
            }
            layoutParams = LinearLayout.LayoutParams(
                dp(240),
                dp(48)
            )
            setOnClickListener {
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(homeIntent)
                finish()
            }
        }
        rootLayout.addView(homeButton)

        setContentView(rootLayout)
    }

    override fun onResume() {
        super.onResume()
        updateCountdownUI()
        handler.post(tickerRunnable)
    }

    override fun onPause() {
        super.onPause()
        handler.removeCallbacks(tickerRunnable)
    }

    private fun updateCountdownUI() {
        val remainingSec = ProtectionStateCoordinator.getRemainingTimerSeconds(this)
        val formattedTime = ProtectionStateCoordinator.formatRemainingTime(remainingSec)
        val isProtectionOn = ProtectionStateCoordinator.isProtectionActive(this)
        val canUninstall = ProtectionStateCoordinator.canUninstall(this)

        if (canUninstall) {
            // Both timer and protection are done! Auto-finish
            finish()
            return
        }

        timerTextView?.text = formattedTime

        if (remainingSec > 0) {
            timerTextView?.setTextColor(Color.parseColor("#FFB74D")) // Warm amber during focus timer
            statusDescTextView?.text =
                "Uninstallation and application deactivation are locked to protect your focus session.\n\n" +
                "The lock will release automatically when your countdown timer reaches 00:00."
        } else if (isProtectionOn) {
            timerTextView?.text = "ACTIVE"
            timerTextView?.setTextColor(Color.parseColor("#64B5F6")) // Blue for active protection
            statusDescTextView?.text =
                "Focus Guard DNS Protection is currently active.\n\n" +
                "To uninstall, please open the Focus Guard app and toggle protection OFF first."
        }
    }

    override fun onBackPressed() {
        // Prevent back press from bypassing the lock screen
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(homeIntent)
        finish()
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics
        ).toInt()
    }
}
