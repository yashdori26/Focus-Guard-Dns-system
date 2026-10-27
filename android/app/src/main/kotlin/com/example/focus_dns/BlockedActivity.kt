package com.example.focus_dns

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * BlockedActivity displays an unbypassable full-screen overlay when a blocked app,
 * third-party VPN, or protected settings screen is opened.
 * Shows the remaining strict-mode timer and
 * a direct action to restore the FocusDNS VPN service.
 */
class BlockedActivity : Activity() {

    companion object {
        const val EXTRA_PACKAGE_NAME = "extra_package_name"
        const val EXTRA_REASON = "extra_reason"
        const val ACTION_RESTORE_VPN = "com.example.focus_dns.ACTION_RESTORE_VPN"
    }

    private var blockedPackage: String = ""
    private var blockedReason: String = ""
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        blockedPackage = intent.getStringExtra(EXTRA_PACKAGE_NAME) ?: ""
        blockedReason = intent.getStringExtra(EXTRA_REASON) ?: "App blocked by FocusDNS"

        val appLabel = getAppName(blockedPackage)

        // Root Scroll & Container
        val scrollView = ScrollView(this).apply {
            setBackgroundColor(Color.parseColor("#0D0E11"))
            isFillViewport = true
        }

        val rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(48), dp(24), dp(32))
        }

        // Shield Icon Text
        val iconView = TextView(this).apply {
            text = "🛡️"
            textSize = 54f
            gravity = Gravity.CENTER
        }
        rootLayout.addView(iconView)

        // Title
        val titleView = TextView(this).apply {
            text = "Blocked by FocusDNS"
            textSize = 24f
            setTypeface(null, Typeface.BOLD)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, dp(16), 0, dp(6))
        }
        rootLayout.addView(titleView)

        // Subtitle / App Name
        val subtitleView = TextView(this).apply {
            text = if (appLabel.isNotEmpty()) "$appLabel\n($blockedPackage)" else blockedPackage
            textSize = 14f
            setTextColor(Color.parseColor("#8E8E93"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(12))
        }
        rootLayout.addView(subtitleView)

        // Reason Badge Card
        val badgeLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            val bg = GradientDrawable().apply {
                setColor(Color.parseColor("#1C1C1E"))
                cornerRadius = dp(8).toFloat()
                setStroke(dp(1), Color.parseColor("#FF453A"))
            }
            background = bg
            setPadding(dp(12), dp(6), dp(12), dp(6))
        }
        val reasonView = TextView(this).apply {
            text = "⚠️ $blockedReason"
            textSize = 12f
            setTextColor(Color.parseColor("#FF453A"))
            setTypeface(null, Typeface.BOLD)
        }
        badgeLayout.addView(reasonView)
        rootLayout.addView(badgeLayout)

        // Spacer
        rootLayout.addView(View(this).apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(32))
        })

        // Strict Mode card (timer-only: no manual unlock until the timer ends)
        val unlockCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val bg = GradientDrawable().apply {
                setColor(Color.parseColor("#16181D"))
                cornerRadius = dp(16).toFloat()
                setStroke(dp(1), Color.parseColor("#2C2C2E"))
            }
            background = bg
            setPadding(dp(20), dp(20), dp(20), dp(20))
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        }

        val cardTitle = TextView(this).apply {
            text = "🔒 Strict Mode Active"
            textSize = 16f
            setTypeface(null, Typeface.BOLD)
            setTextColor(Color.parseColor("#64D2FF"))
        }
        unlockCard.addView(cardTitle)

        val cardDesc = TextView(this).apply {
            textSize = 12f
            setTextColor(Color.parseColor("#8E8E93"))
            setPadding(0, dp(4), 0, dp(16))
        }
        unlockCard.addView(cardDesc)

        val continueButton = Button(this).apply {
            text = "CONTINUE"
            textSize = 13f
            setTypeface(null, Typeface.BOLD)
            setTextColor(Color.WHITE)
            val btnBg = GradientDrawable().apply {
                setColor(Color.parseColor("#007AFF"))
                cornerRadius = dp(10).toFloat()
            }
            background = btnBg
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(48)).apply {
                topMargin = dp(14)
            }
            visibility = View.GONE
            setOnClickListener {
                RulesStore.grantTemporaryPass(blockedPackage, 5 * 60 * 1000L)
                val launchIntent = packageManager.getLaunchIntentForPackage(blockedPackage)
                if (launchIntent != null) {
                    startActivity(launchIntent)
                }
                finish()
            }
        }
        unlockCard.addView(continueButton)
        rootLayout.addView(unlockCard)

        fun formatTime(sec: Int): String {
            val m = sec / 60
            val s = sec % 60
            return if (m >= 60) {
                String.format("%02dh %02dm %02ds", m / 60, m % 60, s)
            } else {
                String.format("%02dm %02ds", m, s)
            }
        }

        fun showEnded() {
            cardDesc.text = "Strict Mode timer has ended. You may now continue."
            continueButton.visibility = View.VISIBLE
        }

        val timedStrictRemaining = RulesStore.getStrictRemainingSeconds(this)
        if (timedStrictRemaining > 0) {
            cardDesc.text = "In Strict Mode you cannot access blocked apps until the timer runs out.\n\n⏳ Time remaining: ${formatTime(timedStrictRemaining)}"
            val tickerRunnable = object : Runnable {
                override fun run() {
                    val rem = RulesStore.getStrictRemainingSeconds(this@BlockedActivity)
                    if (rem > 0) {
                        cardDesc.text = "In Strict Mode you cannot access blocked apps until the timer runs out.\n\n⏳ Time remaining: ${formatTime(rem)}"
                        mainHandler.postDelayed(this, 1000L)
                    } else {
                        showEnded()
                    }
                }
            }
            mainHandler.postDelayed(tickerRunnable, 1000L)
        } else {
            showEnded()
        }

        // Restore FocusDNS VPN Button (Appears when VPN is lost or foreign tunnel detected)
        val isVpnRelated = RulesStore.isVpnLost(this) ||
            blockedPackage == "vpn.tunnel.detected" ||
            blockedPackage == "com.android.vpndialogs" ||
            blockedReason.contains("VPN", ignoreCase = true)

        if (isVpnRelated) {
            val restoreButton = Button(this).apply {
                text = "RESTORE FOCUSDNS VPN"
                textSize = 13f
                setTypeface(null, Typeface.BOLD)
                setTextColor(Color.WHITE)
                val btnBg = GradientDrawable().apply {
                    setColor(Color.parseColor("#34C759"))
                    cornerRadius = dp(10).toFloat()
                }
                background = btnBg
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(48)).apply {
                    topMargin = dp(16)
                }
                setOnClickListener {
                    restoreVpn()
                }
            }
            rootLayout.addView(restoreButton)
        }

        // Return Home Button
        val homeButton = Button(this).apply {
            text = "RETURN HOME"
            textSize = 13f
            setTypeface(null, Typeface.BOLD)
            setTextColor(Color.parseColor("#8E8E93"))
            val btnBg = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                cornerRadius = dp(10).toFloat()
                setStroke(dp(1), Color.parseColor("#2C2C2E"))
            }
            background = btnBg
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(48)).apply {
                topMargin = dp(16)
            }
            setOnClickListener {
                goHome()
            }
        }
        rootLayout.addView(homeButton)

        scrollView.addView(rootLayout)
        setContentView(scrollView)

    }

    private fun restoreVpn() {
        val restoreIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_RESTORE_VPN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(restoreIntent)
        finish()
    }

    private fun getAppName(packageName: String): String {
        return try {
            val pm = packageManager
            val info = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(info).toString()
        } catch (e: Exception) {
            ""
        }
    }

    private fun goHome() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(homeIntent)
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        super.onBackPressed()
        goHome()
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics
        ).toInt()
    }
}
