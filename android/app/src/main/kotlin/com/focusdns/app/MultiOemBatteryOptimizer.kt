package com.focusdns.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log

/**
 * MultiOemBatteryOptimizer
 * ========================
 * Deep OEM-specific battery optimization & autostart bypass dispatcher.
 * Handles aggressive vendor task killers on Xiaomi MIUI/HyperOS, Samsung OneUI,
 * Huawei EMUI, OnePlus OxygenOS, Oppo ColorOS, and Vivo FuntouchOS.
 */
object MultiOemBatteryOptimizer {

    private const val TAG = "MultiOemBatteryOpt"

    enum class OemBrand {
        SAMSUNG,
        XIAOMI,
        HUAWEI,
        ONEPLUS,
        OPPO,
        VIVO,
        SONY,
        ASUS,
        GENERIC
    }

    fun detectOemBrand(): OemBrand {
        val manufacturer = Build.MANUFACTURER.lowercase()
        return when {
            manufacturer.contains("samsung") -> OemBrand.SAMSUNG
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") || manufacturer.contains("poco") -> OemBrand.XIAOMI
            manufacturer.contains("huawei") || manufacturer.contains("honor") -> OemBrand.HUAWEI
            manufacturer.contains("oneplus") -> OemBrand.ONEPLUS
            manufacturer.contains("oppo") || manufacturer.contains("realme") -> OemBrand.OPPO
            manufacturer.contains("vivo") || manufacturer.contains("iqoo") -> OemBrand.VIVO
            manufacturer.contains("sony") -> OemBrand.SONY
            manufacturer.contains("asus") -> OemBrand.ASUS
            else -> OemBrand.GENERIC
        }
    }

    /**
     * Checks if standard Android Doze mode exemption is granted.
     */
    fun isDozeExempted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            return pm?.isIgnoringBatteryOptimizations(context.packageName) ?: true
        }
        return true
    }

    /**
     * Dispatches deep-link intent to the manufacturer's specific battery / autostart manager.
     */
    fun openOemBatterySettings(context: Context): Boolean {
        val brand = detectOemBrand()
        Log.i(TAG, "Opening battery optimization settings for OEM: $brand")

        val intents = mutableListOf<Intent>()

        when (brand) {
            OemBrand.XIAOMI -> {
                // MIUI / HyperOS Autostart and Battery Saver
                intents.add(Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")))
                intents.add(Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.powercenter.PowerSettings")))
            }
            OemBrand.SAMSUNG -> {
                // Samsung Device Care / Sleeping Apps
                intents.add(Intent().setComponent(ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity")))
                intents.add(Intent().setComponent(ComponentName("com.samsung.android.sm", "com.samsung.android.sm.ui.battery.BatteryActivity")))
            }
            OemBrand.HUAWEI -> {
                // Huawei Protected Apps / App Launch
                intents.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity")))
                intents.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity")))
            }
            OemBrand.ONEPLUS -> {
                intents.add(Intent().setComponent(ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity")))
            }
            OemBrand.OPPO -> {
                intents.add(Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")))
                intents.add(Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")))
            }
            OemBrand.VIVO -> {
                intents.add(Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")))
                intents.add(Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")))
            }
            else -> {}
        }

        // Always fallback to standard Android Doze exemption intent
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            intents.add(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${context.packageName}")
            })
            intents.add(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }

        // Fallback to app details
        intents.add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
        })

        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return true
            } catch (e: Exception) {
                Log.d(TAG, "Intent failed: ${intent.component}, trying next...")
            }
        }

        return false
    }
}
