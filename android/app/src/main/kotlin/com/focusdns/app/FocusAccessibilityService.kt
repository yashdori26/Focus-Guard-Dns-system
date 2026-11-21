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

        @Volatile
        var instance: FocusAccessibilityService? = null
            private set

        var onStateChangeListener: ((Boolean) -> Unit)? = null

        fun closeForegroundApp(): Boolean {
            val s = instance ?: return false
            return s.performGlobalAction(GLOBAL_ACTION_HOME)
        }

        val KNOWN_BROWSER_PACKAGES = setOf(
            "com.android.chrome",
            "com.brave.browser",
            "com.sec.android.app.sbrowser",
            "org.mozilla.firefox",
            "org.mozilla.fenix",
            "org.mozilla.firefox_beta",
            "com.opera.browser",
            "com.opera.mini.native",
            "com.opera.gx",
            "com.microsoft.emmx",
            "com.duckduckgo.mobile.android",
            "com.kiwibrowser.browser",
            "com.vivaldi.browser",
            "com.UCMobile.intl",
            "com.uc.browser.en",
            "com.yandex.browser",
            "mark.via.gp",
            "org.torproject.torbrowser",
            "org.torproject.torbrowser_alpha"
        )

        val ADULT_SEARCH_PATTERNS = listOf(
            "porn", "desi porn", "desihub", "desipapa", "desikahani", "desixx", "desisex", "indian porn", "hindisex",
            "tamilsex", "bhabhi", "choot", "xxx", "xvideos", "xnxx", "xhamster", "pornhub",
            "sex video", "sex vid", "hardcore sex", "free porn", "erome", "spankbang", "redtube",
            "stripchat", "chaturbate", "onlyfans", "fapello", "brazzers", "hentai", "nude video",
            "javhd", "adult video", "rule34", "naked video", "desi sex", "indian sex", "antarrvasna",
            "antarvasna", "desiaunty", "auntysex", "mallusex", "chutland", "masaladesi", "chudaimaza",
            "kamababa", "savita bhabhi", "velamma", "fsiblog", "tamilkama"
        )

        val GAMBLING_SEARCH_PATTERNS = listOf(
            "satta", "matka", "kalyan matka", "dpboss", "satta king", "disawar",
            "gali satta", "online casino", "live casino", "bet365", "1xbet", "parimatch",
            "dafabet", "stake casino", "aviator game", "teen patti real cash", "rummy for cash",
            "winzo", "play rummy online", "online gambling", "sports betting", "cricket betting",
            "tiranga game", "bdg game", "daman games", "91club", "okwin", "tc lottery", "color trading", "fastwin"
        )

        val PIRACY_SEARCH_PATTERNS = listOf(
            "tamilrockers", "ibomma", "movierulz", "filmyzilla", "bolly4u", "vegamovies",
            "katmoviehd", "hdhub4u", "pagalworld", "mp4moviez", "download movie torrent",
            "free movie download", "full movie download hd", "torrent download", "1337x",
            "pirate bay", "fitgirl repack", "cracked software", "yts movies", "tamilblasters", "tamilmv"
        )

        val DATING_SEARCH_PATTERNS = listOf(
            "call girls", "call girl", "escort service", "escorts in", "skokka", "locanto dating",
            "local hookup", "casual encounters", "casual sex", "adult dating", "sugar daddy",
            "meet local singles"
        )
    }

    private val handler = Handler(Looper.getMainLooper())
    private var pendingContentRunnable: Runnable? = null
    private var pendingVpnDialogRunnable: Runnable? = null
    private var connectivityManager: ConnectivityManager? = null
    private var vpnNetworkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        isRunning = true
        instance = this
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
            val isBrowser = KNOWN_BROWSER_PACKAGES.contains(pkg)
            val isStrict = RulesStore.isStrictMode(this)
            val isGuardedTarget = pkg == "com.android.vpndialogs" ||
                RulesStore.KNOWN_SETTINGS_PACKAGES.contains(pkg) ||
                RulesStore.KNOWN_INSTALLER_PACKAGES.contains(pkg)

            if (!isBrowser && (!isStrict || !isGuardedTarget)) return

            pendingContentRunnable?.let { handler.removeCallbacks(it) }
            val delay = if (isBrowser) 150L else 250L
            val runnable = Runnable {
                handleWindowCheck(event, pkg, className)
            }
            pendingContentRunnable = runnable
            handler.postDelayed(runnable, delay)
        }
    }

    private fun findBlockedCategoryContent(texts: List<String>, activeCategories: Set<String>): Pair<String, String>? {
        for (raw in texts) {
            val lower = raw.lowercase().trim()
            if (lower.length < 3) continue
            if (lower == "search" || lower == "search or type web address" || lower == "search or type url" || lower == "new tab") continue

            // 1. Adult & Pornography
            if (activeCategories.contains("porn")) {
                for (pattern in ADULT_SEARCH_PATTERNS) {
                    if (lower.contains(pattern)) {
                        return Pair("Adult & Pornography", pattern)
                    }
                }
            }

            // 2. Gambling & Betting
            if (activeCategories.contains("gambling")) {
                for (pattern in GAMBLING_SEARCH_PATTERNS) {
                    if (lower.contains(pattern)) {
                        return Pair("Gambling & Betting", pattern)
                    }
                }
            }

            // 3. Piracy & Torrents
            if (activeCategories.contains("piracy")) {
                for (pattern in PIRACY_SEARCH_PATTERNS) {
                    if (lower.contains(pattern)) {
                        return Pair("Piracy & Torrents", pattern)
                    }
                }
            }

            // 4. Dating & Escorts
            if (activeCategories.contains("dating")) {
                for (pattern in DATING_SEARCH_PATTERNS) {
                    if (lower.contains(pattern)) {
                        return Pair("Dating & Escorts", pattern)
                    }
                }
            }

            // 5. Omnibox domain / URL direct evaluation against zero-day category heuristics
            if (lower.contains(".") && !lower.contains(" ")) {
                val candidateDomain = lower.substringBefore("/").substringBefore("?").substringBefore(":")
                for (category in activeCategories) {
                    if (RulesStore.isDomainInCategory(category, candidateDomain)) {
                        val catName = category.replaceFirstChar { it.uppercase() }
                        return Pair(catName, candidateDomain)
                    }
                }
            }
        }
        return null
    }

    private fun handleWindowCheck(event: AccessibilityEvent?, pkg: String, className: String?) {
        // 1. Never intercept FocusDNS's own activities
        if (pkg == packageName) return

        // 1b. Immediately block Tor Browser and foreign VPN apps whenever Protection is active
        val isProtection = ProtectionStateCoordinator.isProtectionActive(this) || FocusDnsVpnService.isRunning
        val isStrict = RulesStore.isStrictMode(this)
        if ((isStrict || isProtection) && (RulesStore.isVpnApp(pkg) || pkg == "org.torproject.torbrowser" || pkg == "org.torproject.torbrowser_alpha")) {
            Log.w(TAG, "Circumvention Shield: Blocked Tor/VPN app in foreground: $pkg")
            performGlobalAction(GLOBAL_ACTION_HOME)
            launchBlockedScreen(pkg, "Tor Browser & VPN Circumvention Blocked")
            return
        }

        // 1c. Universal Real-Time Browser Omnibox & Search Content Shield (Active Categories)
        if (KNOWN_BROWSER_PACKAGES.contains(pkg)) {
            val activeCategories = RulesStore.getBlockedCategories(this)
            if (activeCategories.isNotEmpty()) {
                val texts = extractWindowTexts(event)
                val match = findBlockedCategoryContent(texts, activeCategories)
                if (match != null) {
                    val (categoryName, term) = match
                    Log.w(TAG, "Blocked category content '$term' ($categoryName) detected in browser ($pkg)")
                    performGlobalAction(GLOBAL_ACTION_HOME)
                    launchBlockedScreen(pkg, "$categoryName Blocked")
                    return
                }
            }
        }

        // 2. Strict Mode Protection for VPN Dialogs, Installer, & Settings
        if (isStrict || !ProtectionStateCoordinator.canUninstall(this)) {
            val isGuardedTarget = pkg == "com.android.vpndialogs" ||
                RulesStore.KNOWN_SETTINGS_PACKAGES.contains(pkg) ||
                RulesStore.KNOWN_INSTALLER_PACKAGES.contains(pkg) ||
                UninstallProtectionManager.KNOWN_PACKAGE_INSTALLERS.contains(pkg) ||
                UninstallProtectionManager.KNOWN_SETTINGS_PACKAGES.contains(pkg)

            if (isGuardedTarget) {
                val texts = extractWindowTexts(event)

                // 2a. Enforce conditional uninstallation & device admin protection
                if (UninstallProtectionManager.handleWindowInspection(this, pkg, className, texts)) {
                    return
                }

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
                RulesStore.isVpnApp(pkg) -> "Tor Browser & VPN Circumvention Blocked"
                RulesStore.isPackageInCategory(RulesStore.getBlockedCategories(this), pkg) -> "Category Blocked App"
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
            launchBlockedScreen("vpn.tunnel.detected", "DNS filtering paused, app blocking still on")
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
        instance = null
        onStateChangeListener?.invoke(false)
        pendingContentRunnable?.let { handler.removeCallbacks(it) }
        pendingVpnDialogRunnable?.let { handler.removeCallbacks(it) }
        unregisterVpnNetworkCallback()
        Log.i(TAG, "FocusDNS Accessibility Service unbound.")
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        isRunning = false
        instance = null
        onStateChangeListener?.invoke(false)
        pendingContentRunnable?.let { handler.removeCallbacks(it) }
        pendingVpnDialogRunnable?.let { handler.removeCallbacks(it) }
        unregisterVpnNetworkCallback()
        super.onDestroy()
        Log.i(TAG, "FocusDNS Accessibility Service destroyed.")
    }
}
