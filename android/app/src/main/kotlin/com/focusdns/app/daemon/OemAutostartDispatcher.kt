package com.focusdns.app.daemon

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log

/**
 * OemAutostartDispatcher
 * ======================
 * Enterprise-grade Android native autostart and battery exemption intent dispatcher.
 * Handles OEM proprietary intent formats across Xiaomi MIUI/HyperOS, Samsung OneUI,
 * Huawei EMUI, OnePlus OxygenOS, Oppo ColorOS, Vivo OriginOS, Asus ZenUI, and Transsion.
 */
object OemAutostartDispatcher {

    private const val TAG = "OemAutostartDispatcher"

    data class DeviceInfo(
        val manufacturer: String,
        val brand: String,
        val model: String,
        val hardware: String,
        val fingerprint: String,
        val romVersion: String,
        val sdkInt: Int,
        val isDozeExempted: Boolean,
        val isAutostartGranted: Boolean,
        val isLockedInRecents: Boolean
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "manufacturer" to manufacturer,
            "brand" to brand,
            "model" to model,
            "hardware" to hardware,
            "fingerprint" to fingerprint,
            "romVersion" to romVersion,
            "sdkInt" to sdkInt,
            "isDozeExempted" to isDozeExempted,
            "isAutostartGranted" to isAutostartGranted,
            "isLockedInRecents" to isLockedInRecents
        )
    }

    fun getDeviceInfo(context: Context): DeviceInfo {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val isExempted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pm?.isIgnoringBatteryOptimizations(context.packageName) ?: false
        } else {
            true
        }

        val romVersion = resolveRomVersion()

        return DeviceInfo(
            manufacturer = Build.MANUFACTURER,
            brand = Build.BRAND,
            model = Build.MODEL,
            hardware = Build.HARDWARE,
            fingerprint = Build.FINGERPRINT,
            romVersion = romVersion,
            sdkInt = Build.VERSION.SDK_INT,
            isDozeExempted = isExempted,
            isAutostartGranted = isExempted, // Heuristic default
            isLockedInRecents = false
        )
    }

    private fun resolveRomVersion(): String {
        return try {
            val miui = getSystemProperty("ro.miui.ui.version.name")
            if (miui.isNotBlank()) return "MIUI $miui"

            val hyperOs = getSystemProperty("ro.mi.os.version.name")
            if (hyperOs.isNotBlank()) return "HyperOS $hyperOs"

            val emui = getSystemProperty("ro.build.version.emui")
            if (emui.isNotBlank()) return emui

            val oneUi = getSystemProperty("ro.build.version.oneui")
            if (oneUi.isNotBlank()) return "One UI $oneUi"

            val colorOs = getSystemProperty("ro.build.version.opporom")
            if (colorOs.isNotBlank()) return "ColorOS $colorOs"

            "Android ${Build.VERSION.RELEASE}"
        } catch (_: Exception) {
            "Android ${Build.VERSION.RELEASE}"
        }
    }

    private fun getSystemProperty(propName: String): String {
        return try {
            val process = Runtime.getRuntime().exec("getprop $propName")
            process.inputStream.bufferedReader().readLine()?.trim() ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    /**
     * Attempts to launch a specific OEM activity with safety checks.
     */
    fun launchActivity(
        context: Context,
        packageName: String,
        activityName: String,
        action: String = Intent.ACTION_MAIN,
        extras: Map<String, String> = emptyMap()
    ): Boolean {
        Log.i(TAG, "Attempting to launch OEM activity: $packageName/$activityName")
        return try {
            val intent = Intent().apply {
                component = ComponentName(packageName, activityName)
                this.action = action
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                for ((key, value) in extras) {
                    putExtra(key, value)
                }
            }

            val pm = context.packageManager
            val activities = pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            if (activities.isEmpty()) {
                Log.w(TAG, "Activity not resolvable on this device: $packageName/$activityName")
                return false
            }

            context.startActivity(intent)
            Log.i(TAG, "Successfully launched OEM activity: $packageName/$activityName")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch $packageName/$activityName: ${e.message}")
            false
        }
    }

    /**
     * Launches standard AOSP battery optimization dialog.
     */
    fun launchStandardBatteryOptimization(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intents = listOf(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:${context.packageName}")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                },
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                },
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${context.packageName}")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            )

            for (intent in intents) {
                try {
                    context.startActivity(intent)
                    return true
                } catch (e: Exception) {
                    Log.d(TAG, "Battery intent failed: ${e.message}")
                }
            }
        }
        return false
    }
}
