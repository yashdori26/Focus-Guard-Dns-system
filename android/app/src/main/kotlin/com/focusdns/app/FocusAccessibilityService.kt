package com.focusdns.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * FocusAccessibilityService monitors foreground window state and dynamic content changes
 * to enforce instant app blocking, prevent third-party VPN circumvention, guard package
 * installation/uninstallation, and protect critical settings screens during Strict Mode.
 */
class FocusAccessibilityService : AccessibilityService() {

    companion object {
        const val TAG = "FocusAccessibility"

        @Volatile
        var isRunning: Boolean = false
            private set

        var onStateChangeListener: ((Boolean) -> Unit)? = null
    }

    private val handler = Handler(Looper.getMainLooper())
    private var pendingContentRunnable: Runnable? = null
    private var pendingVpnDialogRunnable: Runnable? = null
    private var connectivityManager: ConnectivityManager? = null
    private var vpnNetworkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        isRunning = true
        onStateChangeListener?.invoke(true)
        registerVpnNetworkCallback()
        Log.i(TAG, "FocusDNS Accessibility Service connected and active.")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val eventType = event.eventType
        val pkg = event.packageName?.toString() ?: return
        val className = event.className?.toString()

        if (eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            pendingContentRunnable?.let { handler.removeCallbacks(it) }
            pendingContentRunnable = null
            pendingVpnDialogRunnable?.let { handler.removeCallbacks(it) }
            pendingVpnDialogRunnable = null
            handleWindowCheck(event, pkg, className)
        } else if (eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            // Only inspect content changes in Strict Mode and when targeting sensitive packages
            if (!RulesStore.isStrictMode(this)) return

            val isGuardedTarget = pkg == "com.android.vpndialogs" ||
                RulesStore.KNOWN_SETTINGS_PACKAGES.contains(pkg) ||
                RulesStore.KNOWN_INSTALLER_PACKAGES.contains(pkg)

            if (!isGuardedTarget) return

            pendingContentRunnable?.let { handler.removeCallbacks(it) }
            val runnable = Runnable {
                handleWindowCheck(event, pkg, className)
            }
            pendingContentRunnable = runnable
            handler.postDelayed(runnable, 250L)
        }
    }

    private fun handleWindowCheck(event: AccessibilityEvent?, pkg: String, className: String?) {
        // 1. Never intercept FocusDNS's own activities
        if (pkg == packageName) return

        // 2. Strict Mode Protection for VPN Dialogs, Installer, & Settings
        if (RulesStore.isStrictMode(this)) {
            val isGuardedTarget = pkg == "com.android.vpndialogs" ||
                RulesStore.KNOWN_SETTINGS_PACKAGES.contains(pkg) ||
                RulesStore.KNOWN_INSTALLER_PACKAGES.contains(pkg)

            if (isGuardedTarget) {
                val texts = extractWindowTexts(event)

                // Intercept VPN approval / connection dialogs (whitelist FocusDNS consent, block 3rd-party)
                if (pkg == "com.android.vpndialogs") {
                    if (texts.isEmpty()) {
                        pendingVpnDialogRunnable?.let { handler.removeCallbacks(it) }
                        val runnable = Runnable {
                            if (RulesStore.isStrictMode(this)) {
                                val delayedTexts = extractWindowTexts(null)
                                if (delayedTexts.isNotEmpty() && RulesStore.evaluateShouldGuardVpnConsent(pkg, delayedTexts, isStrict = true)) {
                                    Log.w(TAG, "Strict Mode: Blocked third-party VPN confirmation dialog after delay ($pkg)")
                                    performGlobalAction(GLOBAL_ACTION_HOME)
                                    launchBlockedScreen(pkg, "Third-Party VPN Consent Dialog Blocked in Strict Mode")
                                }
                            }
                        }
                        pendingVpnDialogRunnable = runnable
                        handler.postDelayed(runnable, 100L)
                        return
                    }

                    if (RulesStore.evaluateShouldGuardVpnConsent(pkg, texts, isStrict = true)) {
                        Log.w(TAG, "Strict Mode: Blocked third-party VPN confirmation dialog ($pkg)")
                        performGlobalAction(GLOBAL_ACTION_HOME)
                        launchBlockedScreen(pkg, "Third-Party VPN Consent Dialog Blocked in Strict Mode")
                        return
                    } else {
                        Log.i(TAG, "Strict Mode: Permitted FocusDNS VPN consent dialog")
                        return
                    }
                }

                // Guard System Settings, OEM Security Centers, Date/Time, & Developer Options
                if (RulesStore.shouldGuardSettings(this, pkg, className, texts)) {
                    Log.w(TAG, "Strict Mode: Guarded settings screen accessed ($className)")
                    performGlobalAction(GLOBAL_ACTION_HOME)
                    launchBlockedScreen(pkg, "Settings Page Protected in Strict Mode")
                    return
                }

                // Guard against uninstallation / deletion of FocusDNS
                if (RulesStore.shouldGuardInstaller(this, pkg, className, texts)) {
                    Log.w(TAG, "Strict Mode: Guarded package installer tampering ($className)")
                    performGlobalAction(GLOBAL_ACTION_HOME)
                    launchBlockedScreen(pkg, "Uninstalling FocusDNS Blocked in Strict Mode")
                    return
                }
            }
        }

        // 3. App Blocking (Deep Focus & VPN Apps) — evaluated directly without walking tree
        if (RulesStore.isBlocked(this, pkg)) {
            Log.i(TAG, "Blocked foreground app: $pkg")
            performGlobalAction(GLOBAL_ACTION_HOME)
            val reason = when {
                RulesStore.isVpnLost(this) -> "FocusDNS VPN Lost — Internet Access Locked"
                RulesStore.isVpnApp(pkg) -> "Third-Party VPN App Blocked in Strict Mode"
                else -> "Deep Focus App Blocked"
            }
            launchBlockedScreen(pkg, reason)
        }
    }

    private fun registerVpnNetworkCallback() {
        try {
            connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val cm = connectivityManager ?: return

            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_VPN)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                .build()

            vpnNetworkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    super.onAvailable(network)
                    checkVpnAnomaly()
                }

                override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                    super.onCapabilitiesChanged(network, networkCapabilities)
                    checkVpnAnomaly()
                }

                override fun onLost(network: Network) {
                    super.onLost(network)
                    // If FocusDNS VPN service is neither running nor starting, record VPN lost
                    if (RulesStore.isStrictMode(this@FocusAccessibilityService) &&
                        !FocusDnsVpnService.isRunning &&
                        !FocusDnsVpnService.isStarting) {
                        RulesStore.setVpnLost(this@FocusAccessibilityService, true)
                    }
                }
            }
            cm.registerNetworkCallback(request, vpnNetworkCallback!!)
            Log.i(TAG, "TRANSPORT_VPN NetworkCallback registered.")
        } catch (e: Exception) {
            Log.w(TAG, "Failed registering TRANSPORT_VPN callback: ${e.message}")
        }
    }

    private fun checkVpnAnomaly() {
        if (!RulesStore.isStrictMode(this)) return

        // If FocusDNS VPN service is running OR actively starting,
        // this VPN network is our own! Do NOT trigger false-positive lockdown.
        if (FocusDnsVpnService.isRunning || FocusDnsVpnService.isStarting) {
            return
        }

        Log.w(TAG, "Third-party VPN tunnel detected while Strict Mode active!")
        RulesStore.setVpnLost(this, true)
        handler.post {
            performGlobalAction(GLOBAL_ACTION_HOME)
            launchBlockedScreen("vpn.tunnel.detected", "Third-Party VPN Tunnel Detected in Strict Mode")
        }
    }

    private fun unregisterVpnNetworkCallback() {
        try {
            vpnNetworkCallback?.let {
                connectivityManager?.unregisterNetworkCallback(it)
            }
            vpnNetworkCallback = null
        } catch (e: Exception) {
            Log.d(TAG, "Unregistering VPN callback failed: ${e.message}")
        }
    }

    private fun launchBlockedScreen(pkg: String, reason: String) {
        val intent = Intent(this, BlockedActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(BlockedActivity.EXTRA_PACKAGE_NAME, pkg)
            putExtra(BlockedActivity.EXTRA_REASON, reason)
        }
        startActivity(intent)
    }

    private fun extractWindowTexts(event: AccessibilityEvent?): List<String> {
        val texts = mutableListOf<String>()
        val root = event?.source ?: rootInActiveWindow ?: return texts
        try {
            fun traverse(node: AccessibilityNodeInfo?) {
                if (node == null) return
                node.text?.let { texts.add(it.toString()) }
                node.contentDescription?.let { texts.add(it.toString()) }
                val count = node.childCount
                for (i in 0 until count) {
                    val child = node.getChild(i)
                    traverse(child)
                }
                if (node != root) {
                    try { node.recycle() } catch (_: Exception) {}
                }
            }
            traverse(root)
        } catch (e: Exception) {
            Log.d(TAG, "Error extracting window texts: ${e.message}")
        } finally {
            try { root.recycle() } catch (_: Exception) {}
        }
        return texts
    }

    override fun onInterrupt() {
        Log.w(TAG, "FocusDNS Accessibility Service interrupted.")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        isRunning = false
        onStateChangeListener?.invoke(false)
        pendingContentRunnable?.let { handler.removeCallbacks(it) }
        pendingVpnDialogRunnable?.let { handler.removeCallbacks(it) }
        unregisterVpnNetworkCallback()
        Log.i(TAG, "FocusDNS Accessibility Service unbound.")
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        isRunning = false
        onStateChangeListener?.invoke(false)
        pendingContentRunnable?.let { handler.removeCallbacks(it) }
        pendingVpnDialogRunnable?.let { handler.removeCallbacks(it) }
        unregisterVpnNetworkCallback()
        super.onDestroy()
        Log.i(TAG, "FocusDNS Accessibility Service destroyed.")
    }
}
