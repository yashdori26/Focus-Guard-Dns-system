package com.example.focus_dns

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class MainActivity: FlutterActivity() {

    companion object {
        private const val VPN_CHANNEL = "focus_dns/vpn"
        private const val BLOCKER_CHANNEL = "focus_dns/blocker"
        private const val VPN_REQUEST_CODE = 24601
        private const val NOTIFICATION_PERMISSION_CODE = 24602
    }

    private var pendingVpnResult: MethodChannel.Result? = null
    private var vpnMethodChannel: MethodChannel? = null
    private var blockerMethodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleRestoreVpnIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleRestoreVpnIntent(intent)
    }

    private fun handleRestoreVpnIntent(intent: Intent?) {
        if (intent?.action == BlockedActivity.ACTION_RESTORE_VPN) {
            requestNotificationPermissionIfNeeded()
            val prepareIntent = VpnService.prepare(this)
            if (prepareIntent != null) {
                startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
            } else {
                startFocusDnsVpn()
            }
        }
    }

    fun startFocusDnsVpn() {
        requestNotificationPermissionIfNeeded()
        val serverUrl = RulesStore.getServerUrl(this)
        val profileId = RulesStore.getProfileId(this)
        val apiToken = RulesStore.getApiToken(this)

        val startIntent = Intent(this, FocusDnsVpnService::class.java).apply {
            action = FocusDnsVpnService.ACTION_START
            putExtra(FocusDnsVpnService.EXTRA_SERVER_URL, serverUrl)
            putExtra(FocusDnsVpnService.EXTRA_PROFILE_ID, profileId)
            putExtra(FocusDnsVpnService.EXTRA_API_TOKEN, apiToken)
        }
        startService(startIntent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // --- VPN Method Channel ---
        vpnMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        requestNotificationPermissionIfNeeded()
                        val intent = VpnService.prepare(this@MainActivity)
                        if (intent != null) {
                            pendingVpnResult = result
                            startActivityForResult(intent, VPN_REQUEST_CODE)
                        } else {
                            result.success(true)
                        }
                    }
                    "startVpn" -> {
                        requestNotificationPermissionIfNeeded()
                        val serverUrl = call.argument<String>("serverUrl") ?: "http://10.0.2.2:8080/dns-query"
                        val profileId = call.argument<String>("profileId") ?: "a1b2c3"
                        val apiToken = call.argument<String>("apiToken") ?: ""

                        RulesStore.setServerUrl(this@MainActivity, serverUrl)
                        RulesStore.setProfileId(this@MainActivity, profileId)
                        RulesStore.setApiToken(this@MainActivity, apiToken)

                        startFocusDnsVpn()
                        result.success(true)
                    }
                    "stopVpn" -> {
                        val stopIntent = Intent(this@MainActivity, FocusDnsVpnService::class.java).apply {
                            action = FocusDnsVpnService.ACTION_STOP
                        }
                        startService(stopIntent)
                        result.success(true)
                    }
                    "isRunning" -> {
                        result.success(FocusDnsVpnService.isRunning)
                    }
                    "isBackendReachable" -> {
                        result.success(FocusDnsVpnService.isBackendReachable)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        FocusDnsVpnService.onStateChangeListener = { running, reachable ->
            runOnUiThread {
                vpnMethodChannel?.invokeMethod("onVpnStateChanged", mapOf(
                    "isRunning" to running,
                    "isBackendReachable" to reachable
                ))
            }
        }

        // --- App Blocker & Accessibility Method Channel ---
        blockerMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLOCKER_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessibilityServiceEnabled" -> {
                        result.success(checkAccessibilityEnabled())
                    }
                    "openAccessibilitySettings" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "openAppSettings" -> {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", packageName, null)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "setBlockedPackages" -> {
                        val packages = call.argument<List<String>>("packages") ?: emptyList()
                        RulesStore.setBlockedPackages(this@MainActivity, packages)
                        result.success(true)
                    }
                    "setStrictMode" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val durationMinutes = call.argument<Int>("durationMinutes")
                        if (enabled && durationMinutes != null && durationMinutes > 0) {
                            RulesStore.setTimedStrictMode(this@MainActivity, durationMinutes)
                        } else {
                            RulesStore.setStrictMode(this@MainActivity, enabled)
                        }
                        result.success(true)
                    }
                    "getStrictRemainingSeconds" -> {
                        result.success(RulesStore.getStrictRemainingSeconds(this@MainActivity))
                    }
                    "syncRules" -> {
                        val packages = call.argument<List<String>>("packages")
                        val isStrictMode = call.argument<Boolean>("isStrictMode")
                        val durationMinutes = call.argument<Int>("durationMinutes")

                        // Apply rules off the main thread
                        thread {
                            if (packages != null) {
                                RulesStore.setBlockedPackages(this@MainActivity, packages)
                            }
                            if (isStrictMode != null) {
                                if (isStrictMode && durationMinutes != null && durationMinutes > 0) {
                                    RulesStore.setTimedStrictMode(this@MainActivity, durationMinutes)
                                } else {
                                    RulesStore.setStrictMode(this@MainActivity, isStrictMode)
                                }
                            }
                            runOnUiThread {
                                result.success(true)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        FocusAccessibilityService.onStateChangeListener = { running ->
            runOnUiThread {
                blockerMethodChannel?.invokeMethod("onAccessibilityStateChanged", mapOf(
                    "isEnabled" to running
                ))
            }
        }
    }

    private fun checkAccessibilityEnabled(): Boolean {
        if (FocusAccessibilityService.isRunning) return true
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: ""
        val expectedComponentName = ComponentName(this, FocusAccessibilityService::class.java).flattenToString()
        return enabledServices.contains(expectedComponentName)
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_CODE
                )
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            val granted = (resultCode == Activity.RESULT_OK)
            pendingVpnResult?.success(granted)
            pendingVpnResult = null
            if (granted) {
                startFocusDnsVpn()
            }
        }
    }

    override fun onDestroy() {
        FocusDnsVpnService.onStateChangeListener = null
        FocusAccessibilityService.onStateChangeListener = null
        super.onDestroy()
    }
}
