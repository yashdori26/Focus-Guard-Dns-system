package com.focusdns.app

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.telecom.TelecomManager
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.util.concurrent.ConcurrentHashMap

/**
 * RulesStore manages on-device blocking rules, VPN evasion blocklists,
 * Strict Mode flags, and monotonic timers.
 * Backed by EncryptedSharedPreferences for tamper-resistant offline security.
 */
object RulesStore {
    private const val TAG = "RulesStore"
    const val PREFS_NAME = "focus_dns_rules_prefs"

    const val KEY_BLOCKED_PACKAGES = "blocked_packages"
    const val KEY_STRICT_MODE = "is_strict_mode"
    const val KEY_VPN_LOST = "is_vpn_lost"
    const val KEY_PROFILE_ID = "profile_id"
    const val KEY_SERVER_URL = "server_url"
    const val KEY_API_TOKEN = "api_token"
    const val KEY_WAS_RUNNING = "was_running"
    const val KEY_STRICT_UNTIL_ELAPSED = "strict_until_elapsed"

    // In-memory temporary pass map (packageName -> expiryMonotonicMs)
    private val temporaryPassMap = ConcurrentHashMap<String, Long>()

    // Built-in package list for third-party VPN apps and proxies used to evade DNS filtering
    val KNOWN_VPN_PACKAGES = setOf(
        "com.nordvpn.android",
        "com.expressvpn.vpn",
        "ch.protonvpn.android",
        "com.psiphon3.subscription",
        "free.vpn.unblock.proxy.turbovpn",
        "com.windscribe.vpn",
        "com.surfshark.vpnclient.android",
        "de.mobileconcepts.cyberghost",
        "com.tunnelbear.android",
        "net.openvpn.openvpn",
        "com.wireguard.android",
        "com.cloudflare.onedotonedotonedtone",
        "hotspotshield.android.vpn",
        "com.mullvad.vpn",
        "org.torproject.torbrowser",
        "org.torproject.android"
    )

    val KNOWN_INSTALLER_PACKAGES = setOf(
        "com.android.packageinstaller",
        "com.google.android.packageinstaller"
    )

    val KNOWN_SETTINGS_PACKAGES = setOf(
        "com.android.settings",
        "com.samsung.android.settings",
        "com.miui.securitycenter",
        "com.coloros.safecenter",
        "com.huawei.systemmanager"
    )

    fun currentMonotonicMs(): Long {
        return try {
            android.os.SystemClock.elapsedRealtime()
        } catch (e: Exception) {
            System.currentTimeMillis()
        }
    }

    fun getSecurePrefs(context: Context): SharedPreferences {
        return try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                context,
                PREFS_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        } catch (e: Exception) {
            Log.w(TAG, "EncryptedSharedPreferences unavailable; fallback to standard prefs: ${e.message}")
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }
    }

    // --- Blocked Packages Configuration ---

    fun setBlockedPackages(context: Context, packages: Collection<String>) {
        getSecurePrefs(context).edit()
            .putStringSet(KEY_BLOCKED_PACKAGES, packages.toSet())
            .apply()
    }

    fun getBlockedPackages(context: Context): Set<String> {
        return getSecurePrefs(context).getStringSet(KEY_BLOCKED_PACKAGES, emptySet()) ?: emptySet()
    }

    // --- Strict Mode Configuration ---

    fun setStrictMode(context: Context, enabled: Boolean) {
        val editor = getSecurePrefs(context).edit()
            .putBoolean(KEY_STRICT_MODE, enabled)
        if (!enabled) {
            editor.putLong(KEY_STRICT_UNTIL_ELAPSED, 0L)
        }
        editor.apply()
    }

    fun setTimedStrictMode(context: Context, durationMinutes: Int) {
        val editor = getSecurePrefs(context).edit()
        if (durationMinutes > 0) {
            val lockedUntilElapsed = currentMonotonicMs() + (durationMinutes * 60 * 1000L)
            editor.putBoolean(KEY_STRICT_MODE, true)
                .putLong(KEY_STRICT_UNTIL_ELAPSED, lockedUntilElapsed)
        } else {
            editor.putBoolean(KEY_STRICT_MODE, false)
                .putLong(KEY_STRICT_UNTIL_ELAPSED, 0L)
        }
        editor.apply()
    }

    fun getStrictRemainingSeconds(context: Context): Int {
        val prefs = getSecurePrefs(context)
        if (!prefs.getBoolean(KEY_STRICT_MODE, false)) return 0
        val strictUntilElapsed = prefs.getLong(KEY_STRICT_UNTIL_ELAPSED, 0L)
        if (strictUntilElapsed <= 0L) return 0
        val diffMs = strictUntilElapsed - currentMonotonicMs()
        return if (diffMs > 0) maxOf(1, (diffMs / 1000L).toInt()) else 0
    }

    fun evaluateTimedStrictState(nowElapsed: Long, strictUntilElapsed: Long, isEnabled: Boolean): Pair<Boolean, Int> {
        if (!isEnabled) return Pair(false, 0)
        if (strictUntilElapsed <= 0L) return Pair(true, 0)
        val diffMs = strictUntilElapsed - nowElapsed
        return if (diffMs > 0L) {
            Pair(true, maxOf(1, (diffMs / 1000L).toInt()))
        } else {
            Pair(false, 0)
        }
    }

    fun isStrictMode(context: Context): Boolean {
        val prefs = getSecurePrefs(context)
        val enabled = prefs.getBoolean(KEY_STRICT_MODE, false)
        if (!enabled) return false

        val strictUntilElapsed = prefs.getLong(KEY_STRICT_UNTIL_ELAPSED, 0L)
        if (strictUntilElapsed > 0L) {
            if (currentMonotonicMs() >= strictUntilElapsed) {
                // Auto-expire!
                prefs.edit()
                    .putBoolean(KEY_STRICT_MODE, false)
                    .putLong(KEY_STRICT_UNTIL_ELAPSED, 0L)
                    .apply()
                return false
            }
        }
        return true
    }

    // --- VPN Lost Flag (Triggered on VPN revocation) ---

    fun setVpnLost(context: Context, lost: Boolean) {
        getSecurePrefs(context).edit()
            .putBoolean(KEY_VPN_LOST, lost)
            .apply()
    }

    fun isVpnLost(context: Context): Boolean {
        return getSecurePrefs(context).getBoolean(KEY_VPN_LOST, false)
    }

    // --- Unified VPN & Profile Credentials ---

    fun setServerUrl(context: Context, url: String) {
        getSecurePrefs(context).edit().putString(KEY_SERVER_URL, url).apply()
    }

    fun getServerUrl(context: Context): String {
        return getSecurePrefs(context).getString(KEY_SERVER_URL, "http://127.0.0.1:8080/dns-query")
            ?: "http://127.0.0.1:8080/dns-query"
    }

    fun setProfileId(context: Context, profileId: String) {
        getSecurePrefs(context).edit().putString(KEY_PROFILE_ID, profileId).apply()
    }

    fun getProfileId(context: Context): String {
        return getSecurePrefs(context).getString(KEY_PROFILE_ID, "a1b2c3") ?: "a1b2c3"
    }

    fun setApiToken(context: Context, apiToken: String) {
        getSecurePrefs(context).edit().putString(KEY_API_TOKEN, apiToken).apply()
    }

    fun getApiToken(context: Context): String {
        return getSecurePrefs(context).getString(KEY_API_TOKEN, "") ?: ""
    }

    fun setWasRunning(context: Context, wasRunning: Boolean) {
        getSecurePrefs(context).edit().putBoolean(KEY_WAS_RUNNING, wasRunning).apply()
    }

    fun getWasRunning(context: Context): Boolean {
        return getSecurePrefs(context).getBoolean(KEY_WAS_RUNNING, false)
    }

    // --- Monotonic Temporary Pass (5-Minute Unlock Window) ---

    fun grantTemporaryPass(packageName: String, durationMs: Long = 5 * 60 * 1000L) {
        val expiry = currentMonotonicMs() + durationMs
        temporaryPassMap[packageName] = expiry
    }

    fun isTemporaryPassActive(packageName: String): Boolean {
        val expiry = temporaryPassMap[packageName] ?: return false
        if (currentMonotonicMs() < expiry) {
            return true
        }
        temporaryPassMap.remove(packageName)
        return false
    }

    fun clearTemporaryPass(packageName: String) {
        temporaryPassMap.remove(packageName)
    }

    fun clearAllTemporaryPasses() {
        temporaryPassMap.clear()
    }

    // --- Core Blocking Decisions ---

    fun isVpnApp(packageName: String): Boolean {
        return KNOWN_VPN_PACKAGES.contains(packageName)
    }

    /**
     * Determines whether [packageName] should be intercepted and covered.
     */
    fun isBlocked(context: Context, packageName: String): Boolean {
        return evaluateIsBlocked(
            packageName = packageName,
            blockedPackages = getBlockedPackages(context),
            isStrict = isStrictMode(context),
            isVpnLost = isVpnLost(context),
            isOurApp = (packageName == context.packageName),
            isSystemWhitelisted = isSystemWhitelisted(context, packageName)
        )
    }

    fun evaluateIsBlocked(
        packageName: String,
        blockedPackages: Set<String>,
        isStrict: Boolean,
        isVpnLost: Boolean,
        isOurApp: Boolean = false,
        isSystemWhitelisted: Boolean = false
    ): Boolean {
        if (isOurApp) return false
        if (isTemporaryPassActive(packageName)) return false
        if (isVpnLost && isStrict) {
            if (!isSystemWhitelisted) return true
        }
        if (blockedPackages.contains(packageName)) return true
        if (isStrict && isVpnApp(packageName)) return true
        return false
    }

    /**
     * Evaluates whether a VPN consent confirmation dialog should be guarded.
     * Allows FocusDNS's own consent dialog so user can restore/re-enable the VPN,
     * while blocking foreign 3rd-party VPN consent dialogs.
     */
    fun evaluateShouldGuardVpnConsent(
        packageName: String,
        nodeTexts: List<String>,
        isStrict: Boolean
    ): Boolean {
        if (!isStrict) return false
        if (packageName != "com.android.vpndialogs") return false

        // If the consent dialog belongs to FocusDNS, ALLOW IT!
        val isFocusDnsConsent = nodeTexts.any {
            val lower = it.lowercase()
            lower.contains("focusdns") || lower.contains("focus dns") || lower.contains("focus_dns")
        }
        if (isFocusDnsConsent) {
            return false
        }

        // 3rd-party VPN requesting permission -> Block it!
        return true
    }

    /**
     * Identifies whether the current window event corresponds to a protected Settings page.
     */
    fun shouldGuardSettings(
        context: Context,
        packageName: String,
        className: String?,
        nodeTexts: List<String>
    ): Boolean {
        return evaluateShouldGuardSettings(
            packageName = packageName,
            className = className,
            nodeTexts = nodeTexts,
            isStrict = isStrictMode(context)
        )
    }

    fun evaluateShouldGuardSettings(
        packageName: String,
        className: String?,
        nodeTexts: List<String>,
        isStrict: Boolean
    ): Boolean {
        if (!isStrict) return false

        // 1. Android VPN consent / establishment dialogs
        if (packageName == "com.android.vpndialogs") {
            return evaluateShouldGuardVpnConsent(packageName, nodeTexts, isStrict)
        }

        // 2. Android System Settings or OEM Settings (Samsung, MIUI, ColorOS, Huawei)
        if (KNOWN_SETTINGS_PACKAGES.contains(packageName)) {
            val cls = className ?: ""
            val isTargetSection = cls.contains("Vpn", ignoreCase = true) ||
                cls.contains("Accessibility", ignoreCase = true) ||
                cls.contains("SubSettings", ignoreCase = true) ||
                cls.contains("AppDetail", ignoreCase = true) ||
                cls.contains("InstalledApp", ignoreCase = true) ||
                cls.contains("ManageApplications", ignoreCase = true) ||
                cls.contains("Security", ignoreCase = true) ||
                cls.contains("DateTime", ignoreCase = true) ||
                cls.contains("ZonePicker", ignoreCase = true) ||
                cls.contains("Development", ignoreCase = true)

            // Date & Time settings guard to prevent wall-clock manipulation
            val isDateTimeTampering = cls.contains("DateTime", ignoreCase = true) ||
                cls.contains("ZonePicker", ignoreCase = true) ||
                nodeTexts.any {
                    val l = it.lowercase()
                    l.contains("date & time") || l.contains("date and time") ||
                        l.contains("set time automatically") || l.contains("use network-provided time")
                }
            if (isDateTimeTampering) {
                return true
            }

            // Developer options & USB debugging guard to prevent adb uninstall evasion
            val isDeveloperOptions = cls.contains("Development", ignoreCase = true) ||
                nodeTexts.any {
                    val l = it.lowercase()
                    l.contains("developer options") || l.contains("usb debugging")
                }
            if (isDeveloperOptions) {
                return true
            }

            val hasFocusDns = nodeTexts.any {
                val l = it.lowercase()
                l.contains("focusdns") || l.contains("focus dns") || l.contains("focus_dns")
            }

            if (isTargetSection) {
                if (hasFocusDns) {
                    return true
                }
                for (text in nodeTexts) {
                    val lower = text.lowercase()
                    if (lower.contains("always-on vpn") ||
                        (lower.contains("vpn") && (lower.contains("disconnect") || lower.contains("turn off") || lower.contains("forget")))
                    ) {
                        return true
                    }
                }
            } else if (hasFocusDns) {
                val hasGuardedAction = nodeTexts.any {
                    val lower = it.lowercase()
                    lower.contains("accessibility") ||
                        lower.contains("use service") ||
                        lower.contains("turn off") ||
                        lower.contains("stop") ||
                        lower.contains("disable") ||
                        lower.contains("uninstall") ||
                        lower.contains("force stop")
                }
                if (hasGuardedAction) {
                    return true
                }
            }
        }

        return false
    }

    fun shouldGuardInstaller(
        context: Context,
        packageName: String,
        className: String?,
        nodeTexts: List<String>
    ): Boolean {
        return evaluateShouldGuardInstaller(
            packageName = packageName,
            className = className,
            nodeTexts = nodeTexts,
            isStrict = isStrictMode(context)
        )
    }

    fun evaluateShouldGuardInstaller(
        packageName: String,
        className: String?,
        nodeTexts: List<String>,
        isStrict: Boolean
    ): Boolean {
        if (!isStrict) return false

        // Package installer attempting to uninstall FocusDNS
        if (KNOWN_INSTALLER_PACKAGES.contains(packageName)) {
            val cls = className ?: ""
            val isUninstallScreen = cls.contains("Uninstall", ignoreCase = true) ||
                cls.contains("Delete", ignoreCase = true) ||
                cls.contains("PackageInstaller", ignoreCase = true)

            val mentionsFocusDns = nodeTexts.any {
                val lower = it.lowercase()
                lower.contains("focusdns") || lower.contains("focus dns") || lower.contains("focus_dns")
            }
            val mentionsUninstall = nodeTexts.any {
                val lower = it.lowercase()
                lower.contains("uninstall") || lower.contains("delete") || lower.contains("remove")
            }

            if (mentionsFocusDns && (isUninstallScreen || mentionsUninstall)) {
                return true
            }
        }

        return false
    }

    /**
     * Real-time resolution of critical system components:
     * Home Launcher, Default Dialer, Emergency Telephony (tel:911), Android OS, and System UI.
     */
    fun isSystemWhitelisted(context: Context?, packageName: String): Boolean {
        // 1. Android core OS framework and system UI
        if (packageName == "android" ||
            packageName == "com.android.systemui" ||
            packageName.startsWith("com.android.systemui.") ||
            packageName == "com.android.phone" ||
            packageName == "com.android.server.telecom" ||
            packageName == "com.android.incallui" ||
            packageName == "com.samsung.android.incallui" ||
            packageName == "com.google.android.dialer" ||
            packageName.contains("incallui", ignoreCase = true)) {
            return true
        }

        if (context == null) {
            return packageName.startsWith("com.google.android.apps.nexuslauncher") ||
                packageName.startsWith("com.android.launcher3")
        }

        return try {
            val pm = context.packageManager

            // 2. Default Home Launcher
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
            }
            val homeResolve = pm.resolveActivity(homeIntent, PackageManager.MATCH_DEFAULT_ONLY)
            if (homeResolve?.activityInfo?.packageName == packageName) {
                return true
            }

            // 3. Default Dialer via TelecomManager
            val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            val defaultDialer = telecomManager?.defaultDialerPackage
            if (defaultDialer == packageName) {
                return true
            }

            // 4. Emergency Telephony intent (tel:911)
            val dialIntent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:911"))
            val dialResolve = pm.resolveActivity(dialIntent, PackageManager.MATCH_DEFAULT_ONLY)
            if (dialResolve?.activityInfo?.packageName == packageName) {
                return true
            }

            false
        } catch (e: Exception) {
            packageName.startsWith("com.google.android.apps.nexuslauncher") ||
                packageName.startsWith("com.android.launcher3")
        }
    }
}
