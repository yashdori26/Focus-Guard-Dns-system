package com.focusdns.focus_dns

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class BlockedActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val domain = intent.getStringExtra("domain")
        val pkg = intent.getStringExtra("pkg")
        val reason = intent.getStringExtra("reason")
        val detail = when {
            domain != null && reason != null -> "$domain\n\nBlocked: $reason"
            domain != null -> "$domain is restricted by your Focus Shield."
            pkg != null -> "$pkg is locked during active focus."
            else -> "This content is blocked by your Focus Shield."
        }

        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#121214"))
            setPadding(64, 64, 64, 64)
        }
        box.addView(TextView(this).apply {
            text = "🛡️ Blocked by Focus Shield"
            textSize = 22f
            setTextColor(Color.parseColor("#F7F6F2"))
            gravity = Gravity.CENTER
        })
        box.addView(TextView(this).apply {
            text = detail
            textSize = 15f
            setTextColor(Color.parseColor("#A0A0A5"))
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 48)
        })
        box.addView(Button(this).apply {
            text = "Return to Focus"
            setBackgroundColor(Color.parseColor("#27272A"))
            setTextColor(Color.WHITE)
            setOnClickListener { finish() }
        })
        setContentView(box)
    }
}
