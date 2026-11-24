package com.focusdns.focus_dns

import android.content.Context
import java.util.concurrent.ConcurrentHashMap

data class Decision(val blocked: Boolean, val reason: String)

/** In-memory rule cache (backed by LocalDb) plus bundled blocklists and keyword heuristics. */
object Rules {
    const val K_DOMAIN = "blocked_domain"
    const val K_ALLOW = "allowed_domain"
    const val K_CATEGORY = "category"
    const val K_PACKAGE = "package"

    @Volatile private var blockedDomains: Set<String> = emptySet()
    @Volatile private var allowedDomains: Set<String> = emptySet()
    @Volatile private var categories: Set<String> = emptySet()
    @Volatile var packages: Set<String> = emptySet()
        private set
    @Volatile private var loaded = false
    @Volatile var feedInstagramReels = false
    @Volatile var feedYoutubeShorts = false
    @Volatile var safeSearchEnabled = true
    @Volatile var threatIntelEnabled = true
    @Volatile var adblockEnabled = true
    @Volatile var antiVpnBypassEnabled = true

    private val lists = ConcurrentHashMap<String, Set<String>>()

    private val exemptSuffixes = listOf(
        ".gov", ".mil", ".edu", ".gov.in", ".nic.in", ".ac.in", ".edu.in", ".ac.uk", ".gov.uk"
    )
    private val exemptDomains = setOf("112.gov", "emergency.gov", "play.googleapis.com", "android.com", "gstatic.com")

    // Domains covered when an app package is blocked (so the app can't work around via browser/CDN).
    private val umbrellas: Map<String, List<String>> = mapOf(
        "youtube" to listOf("youtube.com", "youtu.be", "googlevideo.com", "ytimg.com", "youtube-nocookie.com", "youtubei.googleapis.com"),
        "instagram" to listOf("instagram.com", "cdninstagram.com"),
        "facebook" to listOf("facebook.com", "fbcdn.net", "messenger.com"),
        "katana" to listOf("facebook.com", "fbcdn.net"),
        "snapchat" to listOf("snapchat.com", "sc-cdn.net"),
        "musically" to listOf("tiktok.com", "tiktokv.com", "tiktokcdn.com", "byteoversea.com"),
        "trill" to listOf("tiktok.com", "tiktokv.com", "tiktokcdn.com"),
        "twitter" to listOf("twitter.com", "x.com", "twimg.com"),
        "reddit" to listOf("reddit.com", "redd.it", "redditmedia.com", "redditstatic.com"),
        "spotify" to listOf("spotify.com", "scdn.co"),
        "netflix" to listOf("netflix.com", "nflxvideo.net"),
        "pinterest" to listOf("pinterest.com", "pinimg.com")
    )

    private val adTokens = setOf("doubleclick", "adservice", "googleadservices", "pagead2", "adnxs", "appsflyersdk", "telemetry", "analytics", "branch.io", "segment.io", "hotjar", "adcolony", "applovin", "unityads", "ironsrc")
    private val malwareTokens = setOf("malware", "phishing", "cryptolocker", "miner", "coinhive", "xmrig")

    @Synchronized
    fun reload(ctx: Context) {
        val db = LocalDb.get(ctx)
        blockedDomains = db.getRules(K_DOMAIN)
        allowedDomains = db.getRules(K_ALLOW)
        categories = db.getRules(K_CATEGORY)
        packages = db.getRules(K_PACKAGE)
        feedInstagramReels = db.getKv("feed_instagram_reels", "0") == "1"
        feedYoutubeShorts = db.getKv("feed_youtube_shorts", "0") == "1"
        safeSearchEnabled = db.getKv("sec_safesearch", "1") == "1"
        threatIntelEnabled = db.getKv("sec_threat_intel", "1") == "1"
        adblockEnabled = db.getKv("sec_adblock", "1") == "1"
        antiVpnBypassEnabled = db.getKv("sec_anti_vpn_bypass", "1") == "1"
        loaded = true
    }

    fun ensureLoaded(ctx: Context) { if (!loaded) reload(ctx) }

    private fun list(ctx: Context, name: String): Set<String> =
        lists.getOrPut(name) {
            try {
                ctx.assets.open("blocklists/$name.txt").bufferedReader().useLines { seq ->
                    seq.map { it.trim() }.filter { it.isNotEmpty() }.toHashSet()
                }
            } catch (e: Exception) {
                emptySet()
            }
        }

    /** True if [domain] or any parent domain is in [set]. */
    private fun suffixMatch(set: Set<String>, domain: String): Boolean {
        if (set.isEmpty()) return false
        var d = domain
        while (true) {
            if (set.contains(d)) return true
            val i = d.indexOf('.')
            if (i < 0) return false
            d = d.substring(i + 1)
            if (!d.contains('.')) return false // never match bare TLDs
        }
    }

    // Messaging stays reachable when a broad category (e.g. social) is blocked.
    private val messaging = setOf("whatsapp.com", "whatsapp.net", "wa.me", "telegram.org", "t.me", "signal.org")

    private fun exempt(d: String): Boolean {
        if (exemptDomains.any { d == it || d.endsWith(".$it") }) return true
        return exemptSuffixes.any { d.endsWith(it) }
    }

    private val pornTokens = setOf("porn", "porno", "xxx", "hentai", "nsfw", "camgirl", "camgirls", "sexcam", "escorts", "xvideos", "xnxx", "xhamster", "pornhub", "redtube", "youporn", "onlyfans")
    private val pornSubstrings = listOf("porn", "xvideo", "xnxx", "xhamster", "hentai", "redtube", "youporn", "chaturbate", "stripchat")
    private val gamblingSubstrings = listOf("satta", "matka", "dpboss", "disawar", "casino", "teenpatti", "aviator", "winzo", "jackpot", "roulette", "blackjack")
    private val gamblingTokens = setOf("bet", "bets", "betting", "poker", "rummy", "wager", "gamble", "gambling", "slots")
    private val safeRegistrable = setOf("mistake", "alphabet", "example", "simple", "sample", "template", "employee", "whatsapp", "stakeholder", "essex", "sussex")

    private fun heuristic(category: String, d: String): Boolean {
        val labels = d.split('.')
        val reg = if (labels.size >= 2) labels[labels.size - 2] else d
        if (safeRegistrable.contains(reg)) return false
        val tokens = d.split('.', '-', '_').filter { it.isNotEmpty() }
        return when (category) {
            "porn" -> pornTokens.any { tokens.contains(it) } || pornSubstrings.any { d.contains(it) }
            "gambling" -> gamblingSubstrings.any { d.contains(it) } ||
                gamblingTokens.any { tokens.contains(it) } ||
                tokens.any { t -> t.startsWith("bet") && t.length > 3 && listOf("in", "club", "hub", "win", "vip").any { t.endsWith(it) } }
            else -> false
        }
    }

    private fun inCategory(ctx: Context, category: String, d: String): Boolean {
        val name = when (category) {
            "porn", "adult" -> "porn"
            "gambling" -> "gambling"
            "social" -> "social"
            else -> null
        }
        if (name != null && suffixMatch(list(ctx, name), d)) return true
        return heuristic(if (name == "porn") "porn" else category, d)
    }

    fun decide(ctx: Context, raw: String): Decision {
        ensureLoaded(ctx)
        val d = raw.trim().trimEnd('.').lowercase()
        if (d.isEmpty() || !d.contains('.')) return Decision(false, "")
        if (exempt(d)) return Decision(false, "exempt")
        if (suffixMatch(allowedDomains, d)) return Decision(false, "allowlist")
        if (suffixMatch(blockedDomains, d)) return Decision(true, "Blocked domain")
        for (pkg in packages) {
            val p = pkg.lowercase()
            for ((key, doms) in umbrellas) {
                if (p.contains(key) && doms.any { d == it || d.endsWith(".$it") }) return Decision(true, "App block: $pkg")
            }
        }
        if (messaging.any { d == it || d.endsWith(".$it") }) return Decision(false, "messaging")
        if (adblockEnabled && adTokens.any { d.contains(it) }) return Decision(true, "Ad & Tracker Block")
        if (threatIntelEnabled && malwareTokens.any { d.contains(it) }) return Decision(true, "Threat Intelligence")
        for (cat in categories) {
            if (inCategory(ctx, cat, d)) return Decision(true, "Category: $cat")
        }
        return Decision(false, "")
    }

    fun isPackageBlocked(pkg: String): Boolean {
        if (packages.contains(pkg)) return true
        val p = pkg.lowercase()
        for (pkgRule in packages) {
            if (p == pkgRule.lowercase()) return true
        }
        if (categories.contains("social") || categories.contains("social_media")) {
            val socialPkgs = setOf(
                "com.instagram.android", "com.zhiliaoapp.musically", "com.ss.android.ugc.trill",
                "com.facebook.katana", "com.twitter.android", "com.snapchat.android",
                "com.reddit.frontpage", "com.pinterest"
            )
            if (socialPkgs.contains(p)) return true
        }
        if (categories.contains("video") || categories.contains("youtube") || feedYoutubeShorts) {
            if (p == "com.google.android.youtube") return true
        }
        if (categories.contains("porn") || categories.contains("adult")) {
            if (p == "org.torproject.torbrowser" || p == "org.torproject.torbrowser_alpha") return true
        }
        if (categories.contains("gambling")) {
            val gamblingPkgs = setOf("com.winzo.gold", "com.mpl.androidapp", "com.rummycircle.android", "com.dream11.app")
            if (gamblingPkgs.contains(p)) return true
        }
        return false
    }
}
