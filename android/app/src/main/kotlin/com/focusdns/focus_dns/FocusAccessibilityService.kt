package com.focusdns.focus_dns

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * FocusAccessibilityService
 * =========================
 * Provides multi-layered device security and content blocking that operates
 * independently of network tunnels, private DNS, or external VPN status.
 *
 * Capabilities:
 * 1. Blocks distracting / restricted apps instantly upon launch.
 * 2. Neutralizes doomscrolling video feeds (YouTube Shorts & Instagram Reels).
 * 3. Inspects browser address bars across all major Android browsers (Chrome, Brave,
 *    Firefox, Samsung Internet, Edge, Opera, DuckDuckGo) to block prohibited domains
 *    even when another VPN has taken over the network tunnel.
 * 4. Traps unauthorized third-party VPN apps when Anti-Bypass is active.
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
    }

    private var lastBlockAt = 0L

    override fun onServiceConnected() {
        instance = this
        Rules.reload(this)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val e = event ?: return
        val pkg = e.packageName?.toString() ?: return
        val db = LocalDb.get(this)
        val until = db.getKv("strict_until", "0").toLongOrNull() ?: 0L
        val isStrict = (until - System.currentTimeMillis()) > 0

        // Tamper-Proof Scheduled Lock: ONLY during active strict mode countdown
        if (isStrict && (pkg == "com.android.settings" || pkg == "com.google.android.packageinstaller" || pkg == "com.android.packageinstaller")) {
            val root = rootInActiveWindow
            if (root != null && containsAnyText(root, listOf("focusdns", "focus dns", "com.focusdns.focus_dns"))) {
                blockNow(pkg, "Tamper-Proof Lock: Settings modification locked during strict focus timer")
                return
            }
        }

        if (pkg in NEVER_BLOCK) return
        Rules.ensureLoaded(this)

        val isPaused = db.getKv("protection_paused", "0") == "1"
        if (isPaused && !isStrict) return

        val wasRunning = db.getKv("was_running", "0") == "1"
        val isAnyModeActive = wasRunning || isStrict || FocusDnsVpnService.isRunning
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
                if (hasViewId(rootInActiveWindow, listOf("reel_player", "shorts_container", "reel_recycler"))) goBackFromFeed()
            } else if (pkg == "com.instagram.android" && Rules.feedInstagramReels) {
                if (hasViewId(rootInActiveWindow, listOf("clips_viewer", "reel_viewer", "clips_tab_content"))) goBackFromFeed()
            }
        }
    }

    private fun hasViewId(root: AccessibilityNodeInfo?, needles: List<String>): Boolean {
        if (root == null) return false
        for (n in needles) {
            val hits = root.findAccessibilityNodeInfosByViewId("${root.packageName}:id/$n")
            if (!hits.isNullOrEmpty()) return true
        }
        return false
    }

    private fun containsAnyText(node: AccessibilityNodeInfo?, targets: List<String>): Boolean {
        if (node == null) return false
        val text = node.text?.toString()?.lowercase() ?: ""
        val desc = node.contentDescription?.toString()?.lowercase() ?: ""
        for (target in targets) {
            val t = target.lowercase()
            if (text.contains(t) || desc.contains(t)) return true
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (containsAnyText(child, targets)) return true
        }
        return false
    }

    private fun goBackFromFeed() {
        val now = System.currentTimeMillis()
        if (now - lastBlockAt < 500) return
        lastBlockAt = now
        performGlobalAction(GLOBAL_ACTION_BACK)
    }

    private fun blockNow(pkg: String, reason: String = "App block") {
        val now = System.currentTimeMillis()
        if (now - lastBlockAt < 250) return
        lastBlockAt = now
        performGlobalAction(GLOBAL_ACTION_HOME)
        try { LocalDb.get(this).addLog(pkg, "BLOCKED", reason) } catch (_: Exception) {}
    }

    fun goHome(): Boolean = performGlobalAction(GLOBAL_ACTION_HOME)
}
