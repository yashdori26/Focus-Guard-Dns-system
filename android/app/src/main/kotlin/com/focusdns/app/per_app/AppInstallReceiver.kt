package com.focusdns.app.per_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Intercepts new package installations (ACTION_PACKAGE_ADDED) to auto-apply category focus rules.
 */
class AppInstallReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "AppInstallReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_PACKAGE_ADDED) {
            val dataUri = intent.data ?: return
            val packageName = dataUri.schemeSpecificPart ?: return

            val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
            if (replacing) return // Skip updates

            Log.i(TAG, "New application installed: $packageName. Enforcing auto-scan...")

            val scanIntent = Intent("com.focusdns.app.AUTO_SCAN_NEW_APP").apply {
                putExtra("package_name", packageName)
                setPackage(context.packageName)
            }
            context.sendBroadcast(scanIntent)
        }
    }
}
