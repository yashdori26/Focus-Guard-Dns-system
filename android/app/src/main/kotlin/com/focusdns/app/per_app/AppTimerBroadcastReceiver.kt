package com.focusdns.app.per_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * BroadcastReceiver triggered by DozeResilientAlarmScheduler when an individual app lock timer expires.
 */
class AppTimerBroadcastReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "AppTimerReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val appId = intent.getStringExtra(DozeResilientAlarmScheduler.EXTRA_APP_ID) ?: return
        val packageName = intent.getStringExtra(DozeResilientAlarmScheduler.EXTRA_PACKAGE_NAME) ?: return

        Log.i(TAG, "Exact timer expired for app: $appId ($packageName). Unlocking...")

        // Send local broadcast to Flutter engine to notify PerAppCoordinator
        val unlockIntent = Intent("com.focusdns.app.LOCAL_APP_UNLOCKED").apply {
            putExtra("app_id", appId)
            putExtra("package_name", packageName)
            setPackage(context.packageName)
        }
        context.sendBroadcast(unlockIntent)
    }
}
