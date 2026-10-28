package com.focusdns.app

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
        private const val MDM_CHANNEL = "focus_dns/mdm"
        private const val VPN_REQUEST_CODE = 24601
        private const val NOTIFICATION_PERMISSION_CODE = 24602
        private const val DEVICE_ADMIN_REQUEST_CODE = 24603
    }

    private var pendingVpnResult: MethodChannel.Result? = null
    private var vpnMethodChannel: MethodChannel? = null
    private var blockerMethodChannel: MethodChannel? = null
    private var mdmMethodChannel: MethodChannel? = null

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
                        val serverUrl = call.argument<String>("serverUrl") ?: "http://127.0.0.1:8080/dns-query"
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

        // --- MDM & Device Administrator Channel ---
        mdmMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MDM_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDeviceAdminActive" -> {
                        result.success(FocusDeviceAdminReceiver.isDeviceAdminActive(this@MainActivity))
                    }
                    "requestDeviceAdmin" -> {
                        val intent = FocusDeviceAdminReceiver.createAddDeviceAdminIntent(this@MainActivity)
                        startActivity(intent)
                        result.success(true)
                    }
                    "deactivateDeviceAdmin" -> {
                        val deactivated = FocusDeviceAdminReceiver.requestDeactivate(this@MainActivity)
                        result.success(deactivated)
                    }
                    "canUninstall" -> {
                        result.success(ProtectionStateCoordinator.canUninstall(this@MainActivity))
                    }
                    "getLockStatus" -> {
                        result.success(ProtectionStateCoordinator.getTelemetry(this@MainActivity))
                    }
                    "setStrictLockTimer" -> {
                        val durationSeconds = call.argument<Int>("durationSeconds") ?: 0
                        ProtectionStateCoordinator.setStrictTimer(this@MainActivity, durationSeconds.toLong())
                        result.success(true)
                    }
                    "getSplitTunnelApps" -> {
                        thread {
                            val apps = SplitTunnelManager.getInstalledApps(this@MainActivity).map { app ->
                                mapOf(
                                    "packageName" to app.packageName,
                                    "appName" to app.appName,
                                    "isSystemApp" to app.isSystemApp,
                                    "isSelected" to app.isSelected
                                )
                            }
                            runOnUiThread {
                                result.success(apps)
                            }
                        }
                    }
                    "setSplitTunnelPackages" -> {
                        val packages = call.argument<List<String>>("packages") ?: emptyList()
                        SplitTunnelManager.setSelectedPackages(this@MainActivity, packages.toSet())
                        result.success(true)
                    }
                    "setSplitTunnelMode" -> {
                        val modeStr = call.argument<String>("mode") ?: "disallow_list"
                        val mode = if (modeStr == "allow_list") SplitTunnelManager.TunnelMode.ALLOW_LIST else SplitTunnelManager.TunnelMode.DISALLOW_LIST
                        SplitTunnelManager.setTunnelMode(this@MainActivity, mode)
                        result.success(true)
                    }
                    "getSplitTunnelTelemetry" -> {
                        result.success(SplitTunnelManager.getTelemetry(this@MainActivity))
                    }
                    "getMdmCapabilities" -> {
                        result.success(MdmPolicyEngine.getMdmCapabilities(this@MainActivity))
                    }
                    "getHardwareAttestation" -> {
                        val att = HardwareKeyStoreAttestation.inspectAttestation()
                        result.success(mapOf(
                            "alias" to att.alias,
                            "securityLevel" to att.securityLevel.name,
                            "publicKeyBase64" to att.publicKeyBase64,
                            "certificateChainLength" to att.certificateChainLength,
                            "isHardwareBacked" to att.isHardwareBacked
                        ))
                    }
                    "signAttestationPayload" -> {
                        val payload = call.argument<String>("payload") ?: ""
                        val nonce = call.argument<String>("nonce") ?: SecureNonceManager.generateNonce()
                        val assertion = HardwareKeyStoreAttestation.signPayload(payload, nonce)
                        result.success(mapOf(
                            "payload" to assertion.payload,
                            "nonce" to assertion.nonce,
                            "signatureBase64" to assertion.signatureBase64,
                            "timestampMs" to assertion.timestampMs,
                            "keyAlias" to assertion.keyAlias
                        ))
                    }
                    "getPrivateDnsStatus" -> {
                        val status = PrivateDnsProtectionGuard.getStatus(this@MainActivity)
                        result.success(mapOf(
                            "mode" to status.mode.rawValue,
                            "hostnameSpecifier" to status.hostnameSpecifier,
                            "isCompliant" to status.isCompliant,
                            "reason" to status.reason
                        ))
                    }
                    "canDrawOverlays" -> {
                        result.success(OverlayPermissionHelper.canDrawOverlays(this@MainActivity))
                    }
                    "requestOverlayPermission" -> {
                        result.success(OverlayPermissionHelper.requestOverlayPermission(this@MainActivity))
                    }
                    "triggerEmergencyCall" -> {
                        val number = call.argument<String>("number") ?: "112"
                        EmergencyCallExemptionManager.launchEmergencyDialer(this@MainActivity, number)
                        result.success(true)
                    }
                    "isDeviceOwner" -> {
                        result.success(DpcPolicyManager(this@MainActivity).isDeviceOwner())
                    }
                    "isProfileOwner" -> {
                        result.success(DpcPolicyManager(this@MainActivity).isProfileOwner())
                    }
                    "getDpcDiagnostics" -> {
                        result.success(DpcPolicyManager(this@MainActivity).getDpcDiagnosticReport())
                    }
                    "applyConditionalFocusPolicy" -> {
                        val isProtected = call.argument<Boolean>("isProtected") ?: false
                        result.success(DpcPolicyManager(this@MainActivity).applyConditionalFocusPolicy(isProtected))
                    }
                    "setUsbDebuggingDisabled" -> {
                        val disabled = call.argument<Boolean>("disabled") ?: false
                        result.success(DpcPolicyManager(this@MainActivity).setUsbDebuggingDisabled(disabled))
                    }
                    "startKioskMode" -> {
                        val pkgs = call.argument<List<String>>("packages") ?: emptyList()
                        val orchestrator = LockTaskKioskOrchestrator(this@MainActivity)
                        result.success(orchestrator.startKioskMode(this@MainActivity, pkgs))
                    }
                    "stopKioskMode" -> {
                        val orchestrator = LockTaskKioskOrchestrator(this@MainActivity)
                        result.success(orchestrator.stopKioskMode(this@MainActivity))
                    }
                    "isKioskModeActive" -> {
                        val orchestrator = LockTaskKioskOrchestrator(this@MainActivity)
                        result.success(orchestrator.isKioskModeActive())
                    }
                    "getManagedConfiguration" -> {
                        val mg = ManagedConfigManager(this@MainActivity)
                        result.success(mg.getConfiguration().toMap())
                    }
                    else -> result.notImplemented()
                }
            }
        }

        ProtectionStateCoordinator.registerListener(object : ProtectionStateCoordinator.StateChangeListener {
            override fun onProtectionStateChanged(sessionState: ProtectionStateCoordinator.SessionState, canUninstall: Boolean, remainingSeconds: Long) {
                runOnUiThread {
                    mdmMethodChannel?.invokeMethod("onLockStatusChanged", mapOf(
                        "sessionState" to sessionState.name,
                        "canUninstall" to canUninstall,
                        "remainingSeconds" to remainingSeconds,
                        "formattedRemainingTime" to ProtectionStateCoordinator.formatRemainingTime(remainingSeconds)
                    ))
                }
            }
        })
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
