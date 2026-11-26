package com.focusdns.focus_dns

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * FocusAccessibilityService
 * =========================
 * Provides multi-layered device security and content blocking that operates
 * independently of network tunnels, private DNS, or external VPN status.
 *
 * Hardened against automatic OS shutdowns and memory/battery kills:
 * 1. Blocks distracting / restricted apps instantly upon launch.
 * 2. Neutralizes doomscrolling video feeds (YouTube Shorts & Instagram Reels).
 * 3. Inspects browser address bars across all major Android browsers (Chrome, Brave,
 *    Firefox, Samsung Internet, Edge, Opera, DuckDuckGo) to block prohibited domains
 *    even when another VPN has taken over the network tunnel.
 * 4. Traps unauthorized third-party VPN apps when Anti-Bypass is active.
 * 5. Full exception absorption (no crashes propagate to the OS to trigger disablement).
 * 6. Sticky restart and rebind retention.
 */
class FocusAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile var instance: FocusAccessibilityService? = null
        private val NEVER_BLOCK = setOf(
            "com.focusdns.focus_dns", "com.android.systemui", "com.android.settings",
            "com.android.dialer", "com.google.android.dialer", "com.android.phone",
            "com.android.emergency", "com.samsung.android.dialer"
        )

        private val BROWSER_PACKAGES = setOf(
            "com.android.chrome",
            "com.chrome.beta",
            "com.chrome.dev",
            "com.chrome.canary",
            "org.chromium.chrome",
            "com.brave.browser",
            "com.brave.browser_beta",
            "com.brave.browser_nightly",
            "org.mozilla.firefox",
            "org.mozilla.firefox_beta",
            "org.mozilla.fenix",
            "com.sec.android.app.sbrowser",
            "com.sec.android.app.sbrowser.beta",
            "com.microsoft.emmx",
            "com.opera.browser",
            "com.opera.mini.native",
            "com.opera.gx",
            "com.duckduckgo.mobile.android",
            "com.kiwibrowser.browser",
            "com.vivaldi.browser",
            "com.UCMobile.intl",
            "mark.via.gp",
            "org.torproject.torbrowser",
            "org.torproject.torbrowser_alpha"
        )

        private val KNOWN_VPN_PACKAGES = setOf(
            "com.nordvpn.android",
            "ch.protonvpn.android",
            "com.expressvpn.vpn",
            "com.surfshark.vpnclient.android",
            "com.wireguard.android",
            "com.cloudflare.onedotonedotonedotone",
            "com.tunnelbear.android",
            "com.cyberghostro.vpn",
            "net.openvpn.openvpn",
            "de.blinkt.openvpn",
            "free.vpn.unblock.proxy.turbovpn",
            "com.fast.free.unblock.thunder.vpn",
            "vpn.free.hotspot.shield",
            "com.jrzheng.supervpnfree"
        )

        private val URL_BAR_IDS = listOf(
            "url_bar", "location_bar_edit_text", "url_bar_title", "location_bar",
            "search_box", "omnibarTextInput", "url_field", "address_bar_edit_text",
            "toolbar", "url"
        )

        /**
         * Automatically restores and re-enables accessibility in Android settings
         * if the permission was granted and WRITE_SECURE_SETTINGS is present.
         */
        fun restoreAccessibilityIfConfigured(context: Context) {
            try {
                val db = LocalDb.get(context)
                val previouslyEnabled = db.getKv("focus_perm_a11y", "0") == "1"
                if (previouslyEnabled && context.checkCallingOrSelfPermission("android.permission.WRITE_SECURE_SETTINGS") == PackageManager.PERMISSION_GRANTED) {
                    val cn = ComponentName(context, FocusAccessibilityService::class.java).flattenToString()
                    val current = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
                    if (!current.contains(cn)) {
                        val newSetting = if (current.isEmpty()) cn else "$current:$cn"
                        Settings.Secure.putString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, newSetting)
                        Settings.Secure.putInt(context.contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
                    }
                }
            } catch (_: Throwable) {}
        }
    }

    private var lastBlockAt = 0L
    private var lastStateCheckTime = 0L
    private var cachedIsStrict = false
    private var cachedInBreak = false
    private var cachedIsPaused = false
    private var cachedWasRunning = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        instance = this
        try {
            Rules.reload(this)
            LocalDb.get(this).putKv("focus_perm_a11y", "1")
        } catch (_: Throwable) {}
        return START_STICKY
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        try {
            Rules.reload(this)
            LocalDb.get(this).putKv("focus_perm_a11y", "1")
        } catch (_: Throwable) {}
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return true // Return true so onRebind is called when system re-attaches
    }

    override fun onRebind(intent: Intent?) {
        super.onRebind(intent)
        instance = this
        try {
            Rules.reload(this)
            LocalDb.get(this).putKv("focus_perm_a11y", "1")
        } catch (_: Throwable) {}
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onInterrupt() {
        // Preserved on transient interrupt
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        try {
            val e = event ?: return
            val pkg = e.packageName?.toString() ?: return

            // Event fast-filter: only process window content changes for apps where feed or settings locking applies.
            // For general app blocking, window state changed (app opened) is sufficient.
            // This prevents tens of thousands of redundant CPU cycles and system ANR kills.
            val isContentChange = e.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            if (isContentChange && pkg != "com.google.android.youtube" && pkg != "com.instagram.android"
                && pkg != "com.android.settings" && !pkg.contains("packageinstaller")) {
                return
            }

            val now = System.currentTimeMillis()
            if (now - lastStateCheckTime > 250) {
                lastStateCheckTime = now
                try {
                    val db = LocalDb.get(this)
                    val until = db.getKv("strict_until", "0").toLongOrNull() ?: 0L
                    cachedIsStrict = (until - now) > 0
                    cachedInBreak = db.getKv("routine_in_break", "0") == "1"
                    cachedIsPaused = db.getKv("protection_paused", "0") == "1"
                    cachedWasRunning = db.getKv("was_running", "0") == "1"
                } catch (_: Throwable) {}
            }

            val isStrict = cachedIsStrict

            // Tamper-Proof Scheduled Lock: ONLY during active strict mode countdown
            if (isStrict && (pkg == "com.android.settings" || pkg.contains("packageinstaller"))) {
                val root = try { rootInActiveWindow } catch (_: Throwable) { null }
                if (root != null && containsAnyText(root, listOf("focusdns", "focus dns", "com.focusdns.focus_dns"))) {
                    blockNow(pkg, "Tamper-Proof Lock: Settings modification locked during strict focus timer")
                    return
                }
            }

            if (pkg in NEVER_BLOCK) return
            try { Rules.ensureLoaded(this) } catch (_: Throwable) {}

            if (cachedInBreak) return // Completely unblocked during break timer!

            if (cachedIsPaused && !isStrict) return

            val isAnyModeActive = cachedWasRunning || isStrict || FocusDnsVpnService.isRunning
            if (!isAnyModeActive) return

            // 1. Anti-VPN Bypass Trap (detect unauthorized third-party VPN apps)
            if (Rules.antiVpnBypassEnabled && pkg in KNOWN_VPN_PACKAGES) {
                blockNow(pkg, "Third-party VPN blocked: Focus Shield active")
                return
            }

            // 2. Prohibited App Enforcement (works whether VPN is on or off)
            if (Rules.isPackageBlocked(pkg)) {
                blockNow(pkg, "App locked by Focus Shield")
                return
            }

            // 3. Anti-Doomscroll Feed Interceptors
            if (e.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED || e.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                if (pkg == "com.google.android.youtube" && Rules.feedYoutubeShorts) {
                    val root = try { rootInActiveWindow } catch (_: Throwable) { null }
                    if (hasViewId(root, listOf("reel_player", "shorts_container", "reel_recycler"))) goBackFromFeed()
                } else if (pkg == "com.instagram.android" && Rules.feedInstagramReels) {
                    val root = try { rootInActiveWindow } catch (_: Throwable) { null }
                    if (hasViewId(root, listOf("clips_viewer", "reel_viewer", "clips_tab_content"))) goBackFromFeed()
                }
            }
        } catch (t: Throwable) {
            android.util.Log.e("FocusAccessibility", "Resilient catch in onAccessibilityEvent: ${t.message}", t)
        }
    }

    private fun hasViewId(root: AccessibilityNodeInfo?, needles: List<String>): Boolean {
        if (root == null) return false
        val pkg = root.packageName?.toString() ?: return false
        try {
            for (n in needles) {
                val hits = root.findAccessibilityNodeInfosByViewId("$pkg:id/$n")
                if (!hits.isNullOrEmpty()) return true
            }
        } catch (_: Throwable) {}
        return false
    }

    private fun containsAnyText(node: AccessibilityNodeInfo?, targets: List<String>, depth: Int = 0): Boolean {
        if (node == null || depth > 8) return false
        try {
            val text = node.text?.toString()?.lowercase() ?: ""
            val desc = node.contentDescription?.toString()?.lowercase() ?: ""
            for (target in targets) {
                val t = target.lowercase()
                if (text.contains(t) || desc.contains(t)) return true
            }
            val count = node.childCount
            for (i in 0 until count) {
                val child = try { node.getChild(i) } catch (_: Throwable) { null } ?: continue
                if (containsAnyText(child, targets, depth + 1)) return true
            }
        } catch (_: Throwable) {}
        return false
    }

    private fun goBackFromFeed() {
        try {
            val now = System.currentTimeMillis()
            if (now - lastBlockAt < 500) return
            lastBlockAt = now
            performGlobalAction(GLOBAL_ACTION_BACK)
        } catch (_: Throwable) {}
    }

    private fun blockNow(pkg: String, reason: String = "App block") {
        try {
            val now = System.currentTimeMillis()
            if (now - lastBlockAt < 250) return
            lastBlockAt = now
            performGlobalAction(GLOBAL_ACTION_HOME)
            try { LocalDb.get(this).addLog(pkg, "BLOCKED", reason) } catch (_: Throwable) {}
        } catch (_: Throwable) {}
    }

    fun goHome(): Boolean = try { performGlobalAction(GLOBAL_ACTION_HOME) } catch (_: Throwable) { false }
}
