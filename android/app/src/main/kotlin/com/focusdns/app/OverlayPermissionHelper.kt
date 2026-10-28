package com.focusdns.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * OverlayPermissionHelper
 * =======================
 * Manages SYSTEM_ALERT_WINDOW (display over other apps) permission checks
 * and intent dispatching for the FocusDNS floating HUD lock overlay.
 */
object OverlayPermissionHelper {

    private const val TAG = "OverlayHelper"

    /**
     * Checks if the app has permission to draw system overlays.
     */
    fun canDrawOverlays(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true // Granted at install time prior to Android M
        }
    }

    /**
     * Creates intent to open system Settings where the user can grant overlay permissions.
     */
    fun createOverlaySettingsIntent(context: Context): Intent {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        } else {
            Intent(Settings.ACTION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }
    }

    /**
     * Launches the system overlay permission screen if not yet granted.
     */
    fun requestOverlayPermission(context: Context): Boolean {
        if (canDrawOverlays(context)) {
            Log.i(TAG, "Overlay permission already granted.")
            return true
        }

        return try {
            val intent = createOverlaySettingsIntent(context)
            context.startActivity(intent)
            Log.i(TAG, "Launched overlay permission request screen.")
            false
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch overlay settings: ${e.message}")
            false
        }
    }
}
