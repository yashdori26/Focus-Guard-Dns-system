package com.focusdns.focus_dns

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

@Suppress("DEPRECATION")
class MainActivity : FlutterActivity() {

    private val reqVpn = 4711
    private val reqNotif = 4712
    private var pendingVpn: MethodChannel.Result? = null
    private var pendingNotif: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val vpn = MethodChannel(messenger, "focus_dns/vpn")
        Bridge.vpnChannel = vpn
        vpn.setMethodCallHandler { call, result -> handleVpn(call, result) }
        MethodChannel(messenger, "focus_dns/blocker").setMethodCallHandler { call, result -> handleBlocker(call, result) }

        val mdm = MethodChannel(messenger, "focus_dns/mdm")
        mdm.setMethodCallHandler { call, res ->
            when (call.method) {
                "isDeviceAdminActive" -> res.success(FocusDeviceAdminReceiver.isDeviceAdminActive(this))
                "requestDeviceAdmin" -> {
                    try {
                        startActivity(FocusDeviceAdminReceiver.createAddDeviceAdminIntent(this))
                        res.success(true)
                    } catch (e: Exception) {
                        res.success(false)
                    }
                }
                "deactivateDeviceAdmin" -> res.success(FocusDeviceAdminReceiver.requestDeactivate(this))
                "canUninstall" -> {
                    val rem = strictRemaining()
                    res.success(rem == 0)
                }
                "getLockStatus" -> {
                    val rem = strictRemaining()
                    val isRunning = FocusDnsVpnService.isRunning
                    val adminActive = FocusDeviceAdminReceiver.isDeviceAdminActive(this)
                    val canUn = (rem == 0)
                    val formatted = String.format("%02d:%02d", rem / 60, rem % 60)
                    res.success(mapOf(
                        "sessionState" to if (rem > 0) "STRICT_LOCKED" else if (isRunning) "ACTIVE" else "IDLE",
                        "isProtectionActive" to isRunning,
                        "isTimerActive" to (rem > 0),
                        "remainingSeconds" to rem,
                        "formattedRemainingTime" to formatted,
                        "canUninstall" to canUn,
                        "canDeactivateAdmin" to canUn,
                        "isDeviceAdminActive" to adminActive,
                        "isIntegrityValid" to true
                    ))
                }
                else -> res.success(null)
            }
        }

        val safeChannels = listOf(
            "focus_dns/geofence", "focus_dns/schedule",
            "focus_dns/router_advanced", "focus_dns/router_wfp", "focus_dns/macos_ebpf",
            "com.focusdns.app/oem_battery"
        )
        for (ch in safeChannels) {
            MethodChannel(messenger, ch).setMethodCallHandler { call, res ->
                when (call.method) {
                    "isDeviceOwner" -> res.success(false)
                    "isProfileOwner" -> res.success(false)
                    "isAttestationSupported" -> res.success(false)
                    "isBatteryOptimizationIgnored" -> res.success(true)
                    else -> res.success(null)
                }
            }
        }

        Rules.reload(this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        Bridge.vpnChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun db() = LocalDb.get(this)

    private fun strList(call: MethodCall, key: String): List<String> =
        (call.argument<List<*>>(key) ?: emptyList<Any>()).mapNotNull { it?.toString() }

    private fun strictRemaining(): Int {
        val until = db().getKv("strict_until", "0").toLongOrNull() ?: 0L
        val rem = (until - System.currentTimeMillis()) / 1000
        return if (rem > 0) rem.toInt() else 0
    }

    private fun startVpnService() {
        val i = Intent(this, FocusDnsVpnService::class.java).setAction(FocusDnsVpnService.ACTION_START)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
    }

    private fun handleVpn(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> {
                val intent = VpnService.prepare(this)
                if (intent == null) {
                    result.success(true)
                } else {
                    pendingVpn?.success(false)
                    pendingVpn = result
                    startActivityForResult(intent, reqVpn)
                }
            }
            "startVpn" -> {
                if (VpnService.prepare(this) != null) {
                    result.success(false)
                } else {
                    db().putKv("protection_paused", "0")
                    db().putKv("was_running", "1")
                    Rules.reload(this)
                    startVpnService()
                    result.success(true)
                }
            }
            "stopVpn" -> {
                if (strictRemaining() > 0) {
                    result.success(false)   // locked by strict mode
                } else {
                    db().putKv("protection_paused", "1")
                    db().putKv("was_running", "0")
                    Rules.reload(this)
                    startService(Intent(this, FocusDnsVpnService::class.java).setAction(FocusDnsVpnService.ACTION_STOP))
                    result.success(true)
                }
            }
            "isRunning" -> result.success(FocusDnsVpnService.isRunning)
            "isBackendReachable" -> result.success(true) // fully local: nothing remote to reach
            "getLiveTelemetry" -> result.success(DnsStats.snapshot())
            "updateDnsRules" -> {
                val src = call.argument<String>("source") ?: "default"
                val blocked = strList(call, "blockedDomains")
                val allowed = strList(call, "allowedDomains")
                val cats = strList(call, "blockedCategories")
                thread {
                    db().replaceRules(Rules.K_DOMAIN, src, blocked)
                    db().replaceRules(Rules.K_ALLOW, src, allowed)
                    db().replaceRules(Rules.K_CATEGORY, src, cats)
                    Rules.reload(this)
                    runOnUiThread { result.success(true) }
                }
            }
            "getDbLogs" -> {
                val limit = call.argument<Int>("limit") ?: 100
                val offset = call.argument<Int>("offset") ?: 0
                val filter = call.argument<String>("filter") ?: "ALL"
                thread {
                    val logs = db().getLogs(limit, offset, filter)
                    runOnUiThread { result.success(logs) }
                }
            }
            "getDbStats" -> {
                val hours = call.argument<Int>("timeframeHours") ?: 168
                thread {
                    val stats = db().getAggregatedStats(hours)
                    runOnUiThread { result.success(stats) }
                }
            }
            "clearDbLogs" -> {
                thread {
                    db().clearLogs()
                    runOnUiThread { result.success(true) }
                }
            }
            "updateSecuritySettings" -> {
                val safeSearch = call.argument<Boolean>("safesearch")
                val threatIntel = call.argument<Boolean>("threatIntel")
                val adblock = call.argument<Boolean>("adblock")
                val antiVpnBypass = call.argument<Boolean>("antiVpnBypass")
                thread {
                    if (safeSearch != null) db().putKv("sec_safesearch", if (safeSearch) "1" else "0")
                    if (threatIntel != null) db().putKv("sec_threat_intel", if (threatIntel) "1" else "0")
                    if (adblock != null) db().putKv("sec_adblock", if (adblock) "1" else "0")
                    if (antiVpnBypass != null) db().putKv("sec_anti_vpn_bypass", if (antiVpnBypass) "1" else "0")
                    Rules.reload(this)
                    runOnUiThread { result.success(true) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun handleBlocker(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAccessibilityServiceEnabled" -> {
                val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
                val cn = ComponentName(this, FocusAccessibilityService::class.java)
                result.success(enabled.contains(cn.flattenToString()) || enabled.contains(cn.flattenToShortString()))
            }
            "openAccessibilitySettings" -> {
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(true)
            }
            "openAppSettings" -> {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(true)
            }
            "setBlockedPackages" -> {
                val src = call.argument<String>("source") ?: "default"
                val pk = strList(call, "packages")
                thread {
                    db().replaceRules(Rules.K_PACKAGE, src, pk)
                    Rules.reload(this)
                    runOnUiThread { result.success(true) }
                }
            }
            "setBlockedCategories" -> {
                val cats = strList(call, "categories")
                thread {
                    db().replaceRules(Rules.K_CATEGORY, "categories_api", cats)
                    Rules.reload(this)
                    runOnUiThread { result.success(true) }
                }
            }
            "setFeedFilters" -> {
                db().putKv("feed_instagram_reels", if (call.argument<Boolean>("instagramReels") == true) "1" else "0")
                db().putKv("feed_youtube_shorts", if (call.argument<Boolean>("youtubeShorts") == true) "1" else "0")
                Rules.reload(this)
                result.success(true)
            }
            "setProtectionEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                thread {
                    db().putKv("protection_paused", if (enabled) "0" else "1")
                    db().putKv("was_running", if (enabled) "1" else "0")
                    Rules.reload(this)
                    if (enabled) {
                        if (VpnService.prepare(this) == null) {
                            startVpnService()
                        }
                    } else {
                        if (strictRemaining() == 0) {
                            startService(Intent(this, FocusDnsVpnService::class.java).setAction(FocusDnsVpnService.ACTION_STOP))
                        }
                    }
                    runOnUiThread { result.success(true) }
                }
            }
            "setStrictMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val mins = call.argument<Int>("durationMinutes") ?: 0
                applyStrict(enabled, mins)
                result.success(true)
            }
            "getStrictRemainingSeconds" -> result.success(strictRemaining())
            "syncRules" -> {
                val packages = call.argument<List<*>>("packages")?.mapNotNull { it?.toString() }
                val strict = call.argument<Boolean>("isStrictMode")
                val mins = call.argument<Int>("durationMinutes") ?: 0
                thread {
                    if (packages != null) {
                        db().replaceRules(Rules.K_PACKAGE, "sync", packages)
                        Rules.reload(this)
                    }
                    if (strict != null) applyStrict(strict, mins)
                    runOnUiThread { result.success(true) }
                }
            }
            "closeActiveBlockedApp" -> result.success(FocusAccessibilityService.instance?.goHome() ?: false)
            "isBatteryOptimizationIgnored" -> {
                val pm = getSystemService(POWER_SERVICE) as PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(packageName))
            }
            "requestIgnoreBatteryOptimizations" -> {
                try {
                    startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "isNotificationPermissionGranted" -> {
                result.success(Build.VERSION.SDK_INT < 33 ||
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
            }
            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else {
                    pendingNotif?.success(false)
                    pendingNotif = result
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), reqNotif)
                }
            }
            "isDeviceAdminActive" -> {
                result.success(FocusDeviceAdminReceiver.isDeviceAdminActive(this))
            }
            "requestDeviceAdmin" -> {
                try {
                    startActivity(FocusDeviceAdminReceiver.createAddDeviceAdminIntent(this))
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "removeDeviceAdmin" -> {
                result.success(FocusDeviceAdminReceiver.requestDeactivate(this))
            }
            "putKv" -> {
                val key = call.argument<String>("key") ?: ""
                val value = call.argument<String>("value") ?: ""
                if (key.isNotEmpty()) {
                    db().putKv(key, value)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "getKv" -> {
                val key = call.argument<String>("key") ?: ""
                val def = call.argument<String>("default") ?: ""
                result.success(db().getKv(key, def))
            }
            else -> result.notImplemented()
        }
    }

    private fun applyStrict(enabled: Boolean, minutes: Int) {
        if (enabled && minutes > 0) {
            db().putKv("strict_until", (System.currentTimeMillis() + minutes * 60_000L).toString())
        } else if (!enabled) {
            db().putKv("strict_until", "0")
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == reqVpn) {
            pendingVpn?.success(resultCode == Activity.RESULT_OK)
            pendingVpn = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == reqNotif) {
            pendingNotif?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingNotif = null
        }
    }
}
