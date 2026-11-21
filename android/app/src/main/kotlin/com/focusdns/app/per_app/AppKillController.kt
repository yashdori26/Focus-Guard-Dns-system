package com.focusdns.app.per_app

import android.accessibilityservice.AccessibilityService
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Controller executing aggressive app suppression, HOME redirection, and background process termination.
 */
class AppKillController(private val context: Context) {
    companion object {
        private const val TAG = "AppKillController"
    }

    private val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

    /**
     * Terminate the target background process and redirect user to launcher.
     */
    fun suppressRestrictedApp(packageName: String, accessibilityService: AccessibilityService? = null) {
        Log.w(TAG, "Suppressing restricted package: $packageName")

        // 1. Send HOME intent to dismiss from foreground
        if (accessibilityService != null) {
            accessibilityService.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
        } else {
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            }
            context.startActivity(homeIntent)
        }

        // 2. Kill background processes
        try {
            activityManager.killBackgroundProcesses(packageName)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to kill background process: $packageName", e)
        }
    }
}
