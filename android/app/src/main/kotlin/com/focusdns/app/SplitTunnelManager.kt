package com.focusdns.app

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.VpnService
import android.util.Log

/**
 * SplitTunnelManager
 * ==================
 * Provides per-application split-tunneling routing for FocusDNS VPN and DNS interception.
 *
 * Modes:
 * - DISALLOW_LIST (Default): All applications are filtered through FocusDNS VPN except
 *   explicitly exempted packages (e.g. Banking, Google Pay, Enterprise Intranet).
 * - ALLOW_LIST: Only explicitly selected applications are routed through FocusDNS VPN;
 *   all other device traffic bypasses the tunnel.
 */
object SplitTunnelManager {

    private const val TAG = "SplitTunnelManager"
    private const val PREFS_NAME = "focus_dns_split_tunnel_prefs"

    const val KEY_TUNNEL_MODE = "tunnel_mode"
    const val KEY_SELECTED_PACKAGES = "selected_packages"

    val DEFAULT_EXEMPT_PACKAGES = setOf(
        "com.google.android.apps.nbu.paisa.user",
        "com.phonepe.app",
        "net.one97.paytm",
        "com.sbi.lotusintouch",
        "com.snapwork.hdfc",
        "com.csam.icici.bank.imobile",
        "com.whatsapp"
    )

    enum class TunnelMode(val value: String) {
        DISALLOW_LIST("disallow_list"), // Selected apps BYPASS the VPN
        ALLOW_LIST("allow_list")        // Only selected apps ENTER the VPN
    }

    data class AppInfoItem(
        val packageName: String,
        val appName: String,
        val isSystemApp: Boolean,
        val isSelected: Boolean
    )

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun getTunnelMode(context: Context): TunnelMode {
        val raw = getPrefs(context).getString(KEY_TUNNEL_MODE, TunnelMode.DISALLOW_LIST.value)
        return if (raw == TunnelMode.ALLOW_LIST.value) TunnelMode.ALLOW_LIST else TunnelMode.DISALLOW_LIST
    }

    fun setTunnelMode(context: Context, mode: TunnelMode) {
        getPrefs(context).edit().putString(KEY_TUNNEL_MODE, mode.value).apply()
        Log.i(TAG, "Split-tunneling mode set to: ${mode.value}")
    }

    fun getSelectedPackages(context: Context): Set<String> {
        return getPrefs(context).getStringSet(KEY_SELECTED_PACKAGES, emptySet()) ?: emptySet()
    }

    fun setSelectedPackages(context: Context, packages: Set<String>) {
        getPrefs(context).edit().putStringSet(KEY_SELECTED_PACKAGES, packages).apply()
        Log.i(TAG, "Updated split-tunneling selected packages (${packages.size} apps)")
    }

    fun addPackage(context: Context, packageName: String) {
        val current = getSelectedPackages(context).toMutableSet()
        current.add(packageName)
        setSelectedPackages(context, current)
    }

    fun removePackage(context: Context, packageName: String) {
        val current = getSelectedPackages(context).toMutableSet()
        current.remove(packageName)
        setSelectedPackages(context, current)
    }

    /**
     * Pure function determining whether an app's traffic is routed into FocusDNS VPN.
     */
    fun shouldRouteThroughVpn(packageName: String, mode: TunnelMode, selectedPackages: Set<String>): Boolean {
        return when (mode) {
            TunnelMode.DISALLOW_LIST -> !selectedPackages.contains(packageName)
            TunnelMode.ALLOW_LIST -> selectedPackages.contains(packageName)
        }
    }

    /**
     * Applies split-tunneling configurations to an Android VpnService.Builder.
     */
    fun applyToVpnBuilder(context: Context, builder: VpnService.Builder): Int {
        val mode = getTunnelMode(context)
        val selected = getSelectedPackages(context)
        var appliedCount = 0

        val pm = context.packageManager

        when (mode) {
            TunnelMode.DISALLOW_LIST -> {
                // Disallow selected apps from entering the VPN (they bypass directly to the network)
                for (pkg in selected) {
                    try {
                        pm.getPackageInfo(pkg, 0)
                        builder.addDisallowedApplication(pkg)
                        appliedCount++
                    } catch (e: PackageManager.NameNotFoundException) {
                        Log.d(TAG, "Package $pkg not installed; skipping split-tunnel bypass")
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to disallow application $pkg: ${e.message}")
                    }
                }
                Log.i(TAG, "Configured $appliedCount apps to bypass FocusDNS VPN tunnel")
            }
            TunnelMode.ALLOW_LIST -> {
                // Only allow selected apps to enter the VPN tunnel
                for (pkg in selected) {
                    try {
                        pm.getPackageInfo(pkg, 0)
                        builder.addAllowedApplication(pkg)
                        appliedCount++
                    } catch (e: PackageManager.NameNotFoundException) {
                        Log.d(TAG, "Package $pkg not installed; skipping split-tunnel allowance")
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to allow application $pkg: ${e.message}")
                    }
                }
                Log.i(TAG, "Configured $appliedCount apps to route exclusively through FocusDNS VPN tunnel")
            }
        }
        return appliedCount
    }

    /**
     * Queries all installed applications on the device for the Flutter UI app picker.
     */
    fun getInstalledApps(context: Context): List<AppInfoItem> {
        val pm = context.packageManager
        val selected = getSelectedPackages(context)
        val installedApps = pm.getInstalledApplications(PackageManager.GET_META_DATA)

        val resultList = mutableListOf<AppInfoItem>()

        for (app in installedApps) {
            val pkg = app.packageName
            // Skip our own package from split tunneling list
            if (pkg == context.packageName) continue

            val appName = try {
                pm.getApplicationLabel(app).toString()
            } catch (e: Exception) {
                pkg
            }

            val isSystem = (app.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            val isSelected = selected.contains(pkg)

            resultList.add(
                AppInfoItem(
                    packageName = pkg,
                    appName = appName,
                    isSystemApp = isSystem,
                    isSelected = isSelected
                )
            )
        }

        // Sort: user apps first, then alphabetically by app name
        return resultList.sortedWith(
            compareBy<AppInfoItem> { it.isSystemApp }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.appName }
        )
    }

    /**
     * Exports summary telemetry map for Flutter MethodChannel.
     */
    fun getTelemetry(context: Context): Map<String, Any> {
        val mode = getTunnelMode(context)
        val selected = getSelectedPackages(context)

        return mapOf(
            "tunnelMode" to mode.value,
            "selectedCount" to selected.size,
            "selectedPackages" to selected.toList()
        )
    }
}
