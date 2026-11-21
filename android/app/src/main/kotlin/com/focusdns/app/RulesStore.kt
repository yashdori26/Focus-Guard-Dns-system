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
    const val KEY_BLOCKED_CATEGORIES = "blocked_categories"
    const val KEY_BLOCKED_DOMAINS = "blocked_domains"
    const val KEY_ALLOWED_DOMAINS = "allowed_domains"
    const val KEY_STRICT_MODE = "is_strict_mode"
    const val KEY_VPN_LOST = "is_vpn_lost"
    const val KEY_PROFILE_ID = "profile_id"
    const val KEY_SERVER_URL = "server_url"
    const val KEY_API_TOKEN = "api_token"
    const val KEY_WAS_RUNNING = "was_running"
    const val KEY_STRICT_UNTIL_ELAPSED = "strict_until_elapsed"

    // Inviolable life safety domains that can NEVER be blocked
    val LIFE_SAFETY_EXEMPT_DOMAINS = setOf(
        "911.gov",
        "112.gov",
        "emergency.gov",
        "play.googleapis.com",
        "update.microsoft.com",
        "push.apple.com"
    )

    // Complete YouTube domain umbrella (UI, Video Streaming CDN, Internal API, Thumbnails)
    val YOUTUBE_DOMAINS = setOf(
        "youtube.com", "youtu.be", "googlevideo.com", "ytimg.com",
        "youtubei.googleapis.com", "yt3.ggpht.com", "yt4.ggpht.com",
        "youtube-nocookie.com", "youtubekids.com", "yt.be", "gvt1.com",
        "wide-youtube.l.google.com"
    )

    // Complete Instagram domain umbrella (API, CDN, Stories, Reels, Meta CDN, Auth)
    val INSTAGRAM_DOMAINS = setOf(
        "instagram.com", "cdninstagram.com", "ig.me", "fbcdn.net",
        "facebook.com", "facebook.net", "fbsbx.com", "meta.com",
        "threads.net", "threads.com", "igsonar.com", "tfbnw.net", "accountkit.com"
    )

    // Complete Facebook domain umbrella (Feed, Messenger, Video CDN, Graph API)
    val FACEBOOK_DOMAINS = setOf(
        "facebook.com", "fb.com", "fbcdn.net", "fbsbx.com",
        "messenger.com", "m.me", "meta.com", "facebook.net",
        "tfbnw.net", "fb.watch", "workplace.com"
    )

    // Complete TikTok domain umbrella (Shorts CDN, ByteDance APIs, Metrics)
    val TIKTOK_DOMAINS = setOf(
        "tiktok.com", "tiktokv.com", "tiktokcdn.com", "tiktokcdn-eu.com",
        "tiktokcdn-us.com", "byteoversea.com", "byteoversea.net",
        "ibytedtos.com", "ibyteimg.com", "musical.ly", "bytedance.com",
        "bytedapm.com", "bytefcdn.com", "ttwstatic.com", "snssdk.com", "sgpstatp.com"
    )

    // Complete Snapchat domain umbrella (Snaps, Stories CDN, Bitmoji)
    val SNAPCHAT_DOMAINS = setOf(
        "snapchat.com", "sc-cdn.net", "snap-dev.net", "snapkit.com",
        "sc-analytics.com", "snapads.com", "bitmoji.com", "feelprivacy.com",
        "story.snapchat.com"
    )

    // Complete Twitter / X domain umbrella (Timeline, Media CDN, t.co)
    val TWITTER_DOMAINS = setOf(
        "twitter.com", "x.com", "twimg.com", "t.co", "periscope.tv",
        "pscp.tv", "tweetdeck.com", "cms-twdigitalassets.com"
    )

    // Complete Reddit domain umbrella (Feed, Media CDN, Preview)
    val REDDIT_DOMAINS = setOf(
        "reddit.com", "redd.it", "redditmedia.com", "redditstatic.com",
        "redditmail.com", "preview.redd.it", "v.redd.it", "i.redd.it"
    )

    // Complete WhatsApp domain umbrella
    val WHATSAPP_DOMAINS = setOf(
        "whatsapp.com", "whatsapp.net", "wa.me", "whatsapp.org"
    )

    // Complete Telegram domain umbrella
    val TELEGRAM_DOMAINS = setOf(
        "telegram.org", "telegram.me", "t.me", "tdesktop.com", "telesco.pe"
    )

    // Complete Spotify domain umbrella (Music streaming CDN, Web API)
    val SPOTIFY_DOMAINS = setOf(
        "spotify.com", "scdn.co", "spoti.fi", "spotifycdn.com",
        "spotifycdn.net", "audio-ak-spotify-com.akamaized.net"
    )

    // Complete Netflix domain umbrella (Video streaming CDN, Images)
    val NETFLIX_DOMAINS = setOf(
        "netflix.com", "nflxvideo.net", "nflximg.net", "nflxext.com", "nflxso.net"
    )

    // Complete Amazon Prime Video domain umbrella
    val PRIMEVIDEO_DOMAINS = setOf(
        "primevideo.com", "amazonvideo.com", "aiv-cdn.net", "aiv-delivery.net", "pv-cdn.net"
    )

    // Complete Disney+ / Hotstar domain umbrella
    val HOTSTAR_DOMAINS = setOf(
        "disneyplus.com", "disney-plus.net", "dssott.com", "bamgrid.com", "hotstar.com", "hotstar.net"
    )

    // Complete Twitch domain umbrella
    val TWITCH_DOMAINS = setOf(
        "twitch.tv", "ttvnw.net", "jtvnw.net"
    )

    // Complete Discord domain umbrella
    val DISCORD_DOMAINS = setOf(
        "discord.com", "discord.gg", "discordapp.com", "discordapp.net", "discord.media", "discordstatus.com"
    )

    // Complete Roblox domain umbrella
    val ROBLOX_DOMAINS = setOf(
        "roblox.com", "rbxcdn.com", "robloxlabs.com"
    )

    // Complete Pinterest domain umbrella
    val PINTEREST_DOMAINS = setOf(
        "pinterest.com", "pinimg.com"
    )

    // Complete LinkedIn domain umbrella
    val LINKEDIN_DOMAINS = setOf(
        "linkedin.com", "licdn.com"
    )

    // Complete Steam domain umbrella
    val STEAM_DOMAINS = setOf(
        "steampowered.com", "steamcommunity.com", "steamstatic.com"
    )

    // Complete Xbox domain umbrella
    val XBOX_DOMAINS = setOf(
        "xbox.com", "xboxlive.com"
    )

    val APP_CATALOG_DOMAINS = mapOf(
        "youtube" to YOUTUBE_DOMAINS,
        "com.google.android.youtube" to YOUTUBE_DOMAINS,
        "com.google.android.apps.youtube.music" to YOUTUBE_DOMAINS,
        "com.google.android.apps.youtube.kids" to YOUTUBE_DOMAINS,
        "com.google.android.apps.youtube.creator" to YOUTUBE_DOMAINS,
        "instagram" to INSTAGRAM_DOMAINS,
        "com.instagram.android" to INSTAGRAM_DOMAINS,
        "com.instagram.barcelona" to INSTAGRAM_DOMAINS,
        "com.instagram.lite" to INSTAGRAM_DOMAINS,
        "facebook" to FACEBOOK_DOMAINS,
        "com.facebook.katana" to FACEBOOK_DOMAINS,
        "com.facebook.orca" to FACEBOOK_DOMAINS,
        "com.facebook.lite" to FACEBOOK_DOMAINS,
        "com.facebook.mlite" to FACEBOOK_DOMAINS,
        "tiktok" to TIKTOK_DOMAINS,
        "com.zhiliaoapp.musically" to TIKTOK_DOMAINS,
        "com.ss.android.ugc.trill" to TIKTOK_DOMAINS,
        "com.zhiliaoapp.musically.go" to TIKTOK_DOMAINS,
        "snapchat" to SNAPCHAT_DOMAINS,
        "com.snapchat.android" to SNAPCHAT_DOMAINS,
        "twitter" to TWITTER_DOMAINS,
        "x" to TWITTER_DOMAINS,
        "com.twitter.android" to TWITTER_DOMAINS,
        "com.twitter.android.lite" to TWITTER_DOMAINS,
        "reddit" to REDDIT_DOMAINS,
        "com.reddit.frontpage" to REDDIT_DOMAINS,
        "whatsapp" to WHATSAPP_DOMAINS,
        "com.whatsapp" to WHATSAPP_DOMAINS,
        "com.whatsapp.w4b" to WHATSAPP_DOMAINS,
        "telegram" to TELEGRAM_DOMAINS,
        "org.telegram.messenger" to TELEGRAM_DOMAINS,
        "org.telegram.plus" to TELEGRAM_DOMAINS,
        "org.thunderdog.challegram" to TELEGRAM_DOMAINS,
        "spotify" to SPOTIFY_DOMAINS,
        "com.spotify.music" to SPOTIFY_DOMAINS,
        "com.spotify.lite" to SPOTIFY_DOMAINS,
        "netflix" to NETFLIX_DOMAINS,
        "com.netflix.mediaclient" to NETFLIX_DOMAINS,
        "com.netflix.ninja" to NETFLIX_DOMAINS,
        "primevideo" to PRIMEVIDEO_DOMAINS,
        "amazonvideo" to PRIMEVIDEO_DOMAINS,
        "com.amazon.avod.thirdpartyclient" to PRIMEVIDEO_DOMAINS,
        "hotstar" to HOTSTAR_DOMAINS,
        "disneyplus" to HOTSTAR_DOMAINS,
        "in.startv.hotstar" to HOTSTAR_DOMAINS,
        "com.disney.disneyplus" to HOTSTAR_DOMAINS,
        "twitch" to TWITCH_DOMAINS,
        "tv.twitch.android.app" to TWITCH_DOMAINS,
        "discord" to DISCORD_DOMAINS,
        "com.discord" to DISCORD_DOMAINS,
        "roblox" to ROBLOX_DOMAINS,
        "com.roblox.client" to ROBLOX_DOMAINS,
        "pinterest" to PINTEREST_DOMAINS,
        "com.pinterest" to PINTEREST_DOMAINS,
        "linkedin" to LINKEDIN_DOMAINS,
        "com.linkedin.android" to LINKEDIN_DOMAINS,
        "steam" to STEAM_DOMAINS,
        "com.valvesoftware.android.steam.community" to STEAM_DOMAINS,
        "xbox" to XBOX_DOMAINS,
        "com.microsoft.xboxone.smartglass" to XBOX_DOMAINS
    )

    val CATEGORY_CATALOG_DOMAINS = mapOf(
        "porn" to setOf("pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "stripchat.com", "chaturbate.com", "onlyfans.com", "redtube.com", "youporn.com", "spankbang.com", "erome.com", "livejasmin.com", "camsoda.com", "brazzers.com", "beeg.com", "eporner.com", "hqporner.com", "txxx.com", "tube8.com", "adultfriendfinder.com", "bonga.com", "bongacams.com", "fapello.com", "cam4.com", "rule34.xxx", "gelbooru.com", "e-hentai.org", "nhentai.net", "tnaflix.com", "redgifs.com"),
        "video" to setOf("youtube.com", "googlevideo.com", "ytimg.com", "youtubei.googleapis.com", "netflix.com", "nflxvideo.net", "disneyplus.com", "hulu.com", "primevideo.com", "twitch.tv", "ttvnw.net", "vimeo.com", "kick.com"),
        "social" to setOf("facebook.com", "fbcdn.net", "instagram.com", "cdninstagram.com", "tiktok.com", "tiktokv.com", "twitter.com", "x.com", "twimg.com", "reddit.com", "snapchat.com", "pinterest.com", "linkedin.com", "threads.net"),
        "gaming" to setOf("roblox.com", "epicgames.com", "steampowered.com", "ea.com", "riotgames.com", "playstation.com", "xboxlive.com", "blizzard.com", "battle.net", "supercell.com"),
        "gambling" to setOf("bet365.com", "pokerstars.com", "draftkings.com", "fanduel.com", "betfair.com", "888poker.com", "stake.com", "bovada.lv", "casino.com", "1xbet.com"),
        "dating" to setOf("tinder.com", "bumble.com", "hinge.co", "match.com", "okcupid.com", "badoo.com", "grindr.com", "pure.app"),
        "piracy" to setOf("thepiratebay.org", "1337x.to", "rarbg.to", "yts.mx", "fitgirl-repacks.site", "torrentz2.eu", "fmovies.to", "nyaa.si", "rutracker.org")
    )

    // In-memory temporary pass map (packageName -> expiryMonotonicMs)
    private val temporaryPassMap = ConcurrentHashMap<String, Long>()

    // Built-in package list for third-party VPN apps, Tor browsers, and proxies used to evade DNS filtering
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
        "com.cloudflare.onedotonedotonedtone.beta",
        "hotspotshield.android.vpn",
        "com.mullvad.vpn",
        "org.torproject.torbrowser",
        "org.torproject.torbrowser_alpha",
        "info.guardianproject.orfox",
        "org.torproject.android",
        "org.briarproject.briar.android",
        "com.github.shadowsocks",
        "com.v2ray.ang",
        "io.nekohasekai.sagernet",
        "com.adguard.android",
        "org.strongswan.android"
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

    // --- Blocked & Allowed Domains Configuration ---

    fun setBlockedDomains(context: Context, domains: Collection<String>) {
        getSecurePrefs(context).edit()
            .putStringSet(KEY_BLOCKED_DOMAINS, domains.toSet())
            .apply()
    }

    fun getBlockedDomains(context: Context): Set<String> {
        val direct = getSecurePrefs(context).getStringSet(KEY_BLOCKED_DOMAINS, emptySet()) ?: emptySet()
        val all = mutableSetOf<String>()
        all.addAll(direct)

        // Automatically bridge any blocked packages into corresponding DNS domain umbrellas
        val blockedPkgs = getBlockedPackages(context)
        for (pkg in blockedPkgs) {
            val pkgLower = pkg.lowercase()
            // 1. Direct package / short name match
            APP_CATALOG_DOMAINS[pkgLower]?.let { all.addAll(it) }
            // 2. Substring match across catalog
            for ((key, domains) in APP_CATALOG_DOMAINS) {
                if (pkgLower.contains(key) || key.contains(pkgLower)) {
                    all.addAll(domains)
                }
            }
        }
        return all
    }

    fun setAllowedDomains(context: Context, domains: Collection<String>) {
        getSecurePrefs(context).edit()
            .putStringSet(KEY_ALLOWED_DOMAINS, domains.toSet())
            .apply()
    }

    fun getAllowedDomains(context: Context): Set<String> {
        return getSecurePrefs(context).getStringSet(KEY_ALLOWED_DOMAINS, emptySet()) ?: emptySet()
    }

    fun setBlockedCategories(context: Context, categories: Collection<String>) {
        getSecurePrefs(context).edit()
            .putStringSet(KEY_BLOCKED_CATEGORIES, categories.toSet())
            .apply()
    }

    fun getBlockedCategories(context: Context): Set<String> {
        val prefs = getSecurePrefs(context)
        return prefs.getStringSet(KEY_BLOCKED_CATEGORIES, emptySet()) ?: emptySet()
    }

    fun isAdultBlockingActive(context: Context): Boolean {
        val categories = getBlockedCategories(context)
        if (categories.contains("porn")) return true
        val blocked = getBlockedDomains(context)
        return blocked.any { it.contains("porn") || it.contains("xvideos") || it.contains("xnxx") }
    }

    /**
     * High-speed, zero-day heuristic adult content domain classifier.
     */
    fun isAdultDomain(domain: String): Boolean {
        val clean = domain.trim().trimEnd('.').lowercase()
        if (clean.isEmpty()) return false
        if (LIFE_SAFETY_EXEMPT_DOMAINS.any { clean == it || clean.endsWith(".$it") }) return false
        if (clean.endsWith(".gov") || clean.endsWith(".mil") || clean.endsWith(".edu") || clean.endsWith(".ac.uk")) {
            return false
        }

        val pornCatalog = CATEGORY_CATALOG_DOMAINS["porn"] ?: emptySet()
        for (known in pornCatalog) {
            if (clean == known || clean.endsWith(".$known")) return true
        }

        val adultTlds = listOf(".xxx", ".adult", ".porn", ".cam", ".sex", ".tube")
        for (tld in adultTlds) {
            if (clean.endsWith(tld)) return true
        }

        val parts = clean.split('.')
        val mainParts = if (parts.size > 1) parts.dropLast(1) else parts
        val nameBody = mainParts.joinToString("-")

        val adultSubstrings = listOf(
            "porn", "xxx", "desihub", "desixx", "xvideo", "xnxx", "xhamster", "pornhub",
            "erome", "spankbang", "redtube", "stripchat", "chaturbate", "onlyfans",
            "fapello", "brazzers", "beeg", "eporner", "hqporner", "txxx", "tube8",
            "adultfriendfinder", "bongacams", "bonga", "tnaflix", "redgifs", "cam4",
            "camsoda", "livejasmin", "rule34", "gelbooru", "hentai", "nhentai",
            "javhd", "javcensored", "javporn", "desisex", "hindisex", "tamilsex",
            "telugusex", "bengalisex", "marathisex", "punjabisex", "bhabhi", "choot",
            "gaand", "chudai", "boobs", "milf", "incest", "fetish", "dildo",
            "masturbat", "orgasm", "cumshot", "creampie", "shemale", "fapvid",
            "hardcoresex", "freeporn", "sexvid", "sexporn", "adultweb", "adultsite",
            "nudevid", "nakedvid", "antarrvasna", "antarvasna", "savita", "luststories", "youjizz",
            "heavy-r", "daftsex", "motherless", "x-art", "nuvid", "porn555",
            "kamababa", "malluporn", "randi", "suhagraat", "desipapa", "desikahani",
            "desiaunty", "auntysex", "mallusex", "chutland", "masaladesi", "chudaimaza"
        )

        for (sub in adultSubstrings) {
            if (nameBody.contains(sub)) return true
        }

        val tokens = nameBody.split('-', '_', '.')
        val explicitTokens = setOf("sex", "sexx", "sexy", "sexi", "nude", "nudes", "naked")
        for (token in tokens) {
            if (explicitTokens.contains(token)) return true
        }

        val regionalIndicators = listOf("desi", "indian", "hindi", "tamil", "telugu", "mallu", "bengali")
        val adultAssociates = listOf("hub", "papa", "kahani", "aunty", "bhabhi", "chudai", "chut", "hot", "video", "tube", "clip", "leak", "mms", "scandal", "sex", "porn", "xxx", "kama", "nude", "naked")
        for (reg in regionalIndicators) {
            if (nameBody.contains(reg)) {
                for (assoc in adultAssociates) {
                    if (nameBody.contains(assoc)) return true
                }
            }
        }

        if (nameBody.contains("sex") && !nameBody.contains("sussex") && !nameBody.contains("essex") && !nameBody.contains("unisex") && !nameBody.contains("section")) return true

        return false
    }

    /**
     * Universal zero-day gambling, betting, casino, and lottery classifier.
     */
    fun isGamblingDomain(domain: String): Boolean {
        val clean = domain.trim().trimEnd('.').lowercase()
        if (clean.isEmpty()) return false
        if (LIFE_SAFETY_EXEMPT_DOMAINS.any { clean == it || clean.endsWith(".$it") }) return false
        if (clean.endsWith(".gov") || clean.endsWith(".mil") || clean.endsWith(".edu") || clean.endsWith(".ac.uk")) {
            return false
        }

        val gamblingCatalog = CATEGORY_CATALOG_DOMAINS["gambling"] ?: emptySet()
        for (known in gamblingCatalog) {
            if (clean == known || clean.endsWith(".$known")) return true
        }

        val gamblingTlds = listOf(".bet", ".casino", ".poker", ".lotto", ".bingo")
        for (tld in gamblingTlds) {
            if (clean.endsWith(tld)) return true
        }

        val parts = clean.split('.')
        val mainParts = if (parts.size > 1) parts.dropLast(1) else parts
        val nameBody = mainParts.joinToString("-")

        val gamblingSubstrings = listOf(
            "satta", "matka", "kalyan", "dpboss", "disawar", "gali-satta", "galidisawar",
            "casino", "poker", "roulette", "blackjack", "slots", "jackpot",
            "teenpatti", "rummy", "aviator", "winzo", "mpl",
            "parimatch", "1xbet", "dafabet", "melbet", "betway", "bet365",
            "stake", "fairplay", "lottery", "bookmaker", "bovada", "paddypower",
            "fanduel", "draftkings", "unibet", "betsson", "betonline", "bwin",
            "sportsbet", "betfair", "betwinner", "mostbet", "4rabet", "linebet",
            "tiranga", "bdggame", "bdg", "damangame", "daman", "91club", "okwin",
            "51game", "tc-lottery", "tclottery", "fastwin", "colorprediction"
        )

        for (sub in gamblingSubstrings) {
            if (nameBody.contains(sub)) return true
        }

        val tokens = nameBody.split('-', '_', '.')
        val explicitBetTokens = setOf("bet", "bets", "betting", "wager", "wagers", "gambling", "gamble")
        for (token in tokens) {
            if (explicitBetTokens.contains(token)) return true
            if (token.startsWith("bet") && token.length > 3 && (token.endsWith("in") || token.endsWith("club") || token.endsWith("hub") || token.endsWith("win") || token.endsWith("vip"))) {
                return true
            }
        }

        val gamblingIndicators = listOf("tiranga", "bdg", "daman", "91", "okwin", "fastwin")
        val gamblingAssociates = listOf("game", "games", "club", "lottery", "win", "play", "bet")
        for (ind in gamblingIndicators) {
            if (nameBody.contains(ind)) {
                for (assoc in gamblingAssociates) {
                    if (nameBody.contains(assoc)) return true
                }
            }
        }

        return false
    }

    /**
     * Universal zero-day piracy, torrent, warez, and illegal streaming classifier.
     */
    fun isPiracyDomain(domain: String): Boolean {
        val clean = domain.trim().trimEnd('.').lowercase()
        if (clean.isEmpty()) return false
        if (LIFE_SAFETY_EXEMPT_DOMAINS.any { clean == it || clean.endsWith(".$it") }) return false
        if (clean.endsWith(".gov") || clean.endsWith(".mil") || clean.endsWith(".edu") || clean.endsWith(".ac.uk")) {
            return false
        }

        val piracyCatalog = CATEGORY_CATALOG_DOMAINS["piracy"] ?: emptySet()
        for (known in piracyCatalog) {
            if (clean == known || clean.endsWith(".$known")) return true
        }

        val piracyTlds = listOf(".torrent", ".rip")
        for (tld in piracyTlds) {
            if (clean.endsWith(tld)) return true
        }

        val parts = clean.split('.')
        val mainParts = if (parts.size > 1) parts.dropLast(1) else parts
        val nameBody = mainParts.joinToString("-")

        val piracySubstrings = listOf(
            "tamilrockers", "ibomma", "movierulz", "filmyzilla", "bolly4u", "katmoviehd",
            "vegamovies", "hdhub4u", "pagalworld", "mp4moviez", "warez",
            "repack", "yts", "1337x", "piratebay", "magnetdl", "keygen", "crack",
            "fitgirl", "rutracker", "rarbg", "fmovies", "soap2day", "putlocker",
            "streamio", "crazyhd", "limetorrents", "eztv", "kickasstorrents",
            "torrentfreak", "thepiratebay", "uwatchfree", "skymovieshd", "cinemavilla"
        )

        for (sub in piracySubstrings) {
            if (nameBody.contains(sub)) return true
        }

        val tokens = nameBody.split('-', '_', '.')
        val explicitPiracyTokens = setOf("torrent", "torrents", "pirate", "warez", "cracked", "keygen")
        for (token in tokens) {
            if (explicitPiracyTokens.contains(token)) return true
        }

        if (nameBody.contains("torrent") && !nameBody.contains("torrential")) return true

        return false
    }

    /**
     * Universal zero-day dating, hookup, escort, and classifieds classifier.
     */
    fun isDatingDomain(domain: String): Boolean {
        val clean = domain.trim().trimEnd('.').lowercase()
        if (clean.isEmpty()) return false
        if (LIFE_SAFETY_EXEMPT_DOMAINS.any { clean == it || clean.endsWith(".$it") }) return false
        if (clean.endsWith(".gov") || clean.endsWith(".mil") || clean.endsWith(".edu") || clean.endsWith(".ac.uk")) {
            return false
        }

        val datingCatalog = CATEGORY_CATALOG_DOMAINS["dating"] ?: emptySet()
        for (known in datingCatalog) {
            if (clean == known || clean.endsWith(".$known")) return true
        }

        val datingTlds = listOf(".dating", ".singles")
        for (tld in datingTlds) {
            if (clean.endsWith(tld)) return true
        }

        val parts = clean.split('.')
        val mainParts = if (parts.size > 1) parts.dropLast(1) else parts
        val nameBody = mainParts.joinToString("-")

        val datingSubstrings = listOf(
            "tinder", "bumble", "hinge", "grindr", "badoo", "okcupid", "skokka",
            "locanto", "escort", "callgirl", "hookup", "casualsex", "casualencounters",
            "adultfriendfinder", "sugarbaby", "sugardaddy", "fetlife", "ashleymadison",
            "seekingarrangement", "datehookup", "fling.com"
        )

        for (sub in datingSubstrings) {
            if (nameBody.contains(sub)) return true
        }

        val tokens = nameBody.split('-', '_', '.')
        val explicitDatingTokens = setOf("dating", "hookup", "hookups", "escorts", "singles", "matchmaker")
        for (token in tokens) {
            if (explicitDatingTokens.contains(token)) return true
        }

        return false
    }

    /**
     * Universal social network umbrella classifier.
     */
    fun isSocialDomain(domain: String): Boolean {
        val clean = domain.trim().trimEnd('.').lowercase()
        if (clean.isEmpty()) return false
        if (LIFE_SAFETY_EXEMPT_DOMAINS.any { clean == it || clean.endsWith(".$it") }) return false
        if (clean.endsWith(".gov") || clean.endsWith(".mil") || clean.endsWith(".edu") || clean.endsWith(".ac.uk")) {
            return false
        }

        val socialCatalog = CATEGORY_CATALOG_DOMAINS["social"] ?: emptySet()
        for (known in socialCatalog) {
            if (clean == known || clean.endsWith(".$known")) return true
        }

        val socialStems = listOf(
            "facebook", "fbcdn", "instagram", "cdninstagram", "tiktok", "tiktokv",
            "twitter", "twimg", "snapchat", "pinterest", "threads.net", "tumblr",
            "mastodon", "bsky.app", "bereal"
        )
        for (stem in socialStems) {
            if (clean == stem || clean.endsWith(".$stem") || clean.contains(stem)) return true
        }
        if (clean == "x.com" || clean.endsWith(".x.com")) return true
        if (clean == "reddit.com" || clean.endsWith(".reddit.com") || clean == "redd.it") return true

        return false
    }

    /**
     * Universal gaming network umbrella classifier.
     */
    fun isGamingDomain(domain: String): Boolean {
        val clean = domain.trim().trimEnd('.').lowercase()
        if (clean.isEmpty()) return false
        if (LIFE_SAFETY_EXEMPT_DOMAINS.any { clean == it || clean.endsWith(".$it") }) return false
        if (clean.endsWith(".gov") || clean.endsWith(".mil") || clean.endsWith(".edu") || clean.endsWith(".ac.uk")) {
            return false
        }

        val gamingCatalog = CATEGORY_CATALOG_DOMAINS["gaming"] ?: emptySet()
        for (known in gamingCatalog) {
            if (clean == known || clean.endsWith(".$known")) return true
        }

        val gamingStems = listOf(
            "roblox", "steampowered", "steamcommunity", "steamstatic", "epicgames",
            "riotgames", "playstation", "xboxlive", "blizzard", "battle.net",
            "supercell", "pubg", "freefire", "ubisoft", "origin.com"
        )
        for (stem in gamingStems) {
            if (clean.contains(stem)) return true
        }

        return false
    }

    fun isDomainInCategory(category: String, domain: String): Boolean {
        return when (category.lowercase()) {
            "porn" -> isAdultDomain(domain)
            "gambling" -> isGamblingDomain(domain)
            "piracy" -> isPiracyDomain(domain)
            "dating" -> isDatingDomain(domain)
            "social" -> isSocialDomain(domain)
            "gaming" -> isGamingDomain(domain)
            else -> false
        }
    }

    fun isDomainBlocked(context: Context, domain: String): Pair<Boolean, String> {
        var clean = domain.trim().trimEnd('.').lowercase()
        if (clean.contains(":")) {
            clean = clean.substringBefore(":")
        }
        if (clean.isEmpty()) return Pair(false, "")

        // 1. Inviolable Life Safety Exemption Check
        for (exempt in LIFE_SAFETY_EXEMPT_DOMAINS) {
            if (clean == exempt || clean.endsWith(".$exempt")) {
                return Pair(false, "Life-Safety Exemption")
            }
        }

        // 2. Allowlist Check
        val allowed = getAllowedDomains(context)
        for (rule in allowed) {
            val r = rule.trim().trimEnd('.').lowercase()
            if (clean == r || clean.endsWith(".$r")) {
                return Pair(false, "Allowlisted")
            }
        }

        // 3. Blocklist Check
        val blocked = getBlockedDomains(context)
        for (rule in blocked) {
            val r = rule.trim().trimEnd('.').lowercase()
            if (clean == r || clean.endsWith(".$r")) {
                return Pair(true, rule)
            }
        }

        // 3b. Dynamic Package Stem & App Umbrella Shield Check
        val blockedPkgs = getBlockedPackages(context)
        for (pkg in blockedPkgs) {
            val p = pkg.lowercase()
            // Meta / Instagram feed & media CDN umbrella
            if (p.contains("instagram") || p == "com.instagram.android") {
                if (clean.contains("instagram") || clean.contains("fbcdn") || clean.contains("threads.net") || clean.contains("threads.com")) {
                    return Pair(true, "App Package Rule: Instagram ($clean)")
                }
            }
            // Facebook & Messenger umbrella
            if (p.contains("facebook") || p.contains("katana") || p.contains("orca")) {
                if (clean.contains("facebook") || clean.contains("fbcdn") || clean.contains("messenger")) {
                    return Pair(true, "App Package Rule: Facebook ($clean)")
                }
            }
            // Snapchat umbrella
            if (p.contains("snapchat")) {
                if (clean.contains("snapchat") || clean.contains("sc-cdn")) {
                    return Pair(true, "App Package Rule: Snapchat ($clean)")
                }
            }
            // TikTok umbrella
            if (p.contains("tiktok") || p.contains("musically") || p.contains("trill")) {
                if (clean.contains("tiktok") || clean.contains("byteoversea") || clean.contains("ibytedtos")) {
                    return Pair(true, "App Package Rule: TikTok ($clean)")
                }
            }
            // Twitter / X umbrella
            if (p.contains("twitter") || p == "x") {
                if (clean.contains("twitter") || clean.contains("twimg")) {
                    return Pair(true, "App Package Rule: Twitter ($clean)")
                }
            }
            // Spotify umbrella
            if (p.contains("spotify")) {
                if (clean.contains("spotify") || clean.contains("scdn")) {
                    return Pair(true, "App Package Rule: Spotify ($clean)")
                }
            }
            // Reddit umbrella
            if (p.contains("reddit")) {
                if (clean.contains("reddit") || clean == "redd.it" || clean.endsWith(".redd.it")) {
                    return Pair(true, "App Package Rule: Reddit ($clean)")
                }
            }

            // Universal heuristic for any other installed app package:
            // Extract segments from package (e.g. "flipkart" from "com.flipkart.android")
            val segments = p.split('.').filter {
                it.length >= 4 && it !in setOf("android", "google", "client", "mobile", "media", "frontpage", "music", "lite", "free", "plus")
            }
            for (segment in segments) {
                if (clean == segment || clean.endsWith(".$segment.com") || clean.endsWith(".$segment.net") || clean.endsWith(".$segment.io") || clean.contains(segment)) {
                    return Pair(true, "App Package Rule: $pkg ($segment)")
                }
            }
        }

        // 4. Universal Zero-Day Category Classifiers
        val activeCategories = getBlockedCategories(context)
        for (category in activeCategories) {
            if (isDomainInCategory(category, clean)) {
                val catName = category.replaceFirstChar { it.uppercase() }
                return Pair(true, "Category Block: $catName (Zero-Day Heuristic)")
            }
        }

        return Pair(false, "")
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

    fun hasStrictTimerExpired(context: Context): Boolean {
        val prefs = getSecurePrefs(context)
        val enabled = prefs.getBoolean(KEY_STRICT_MODE, false)
        val strictUntilElapsed = prefs.getLong(KEY_STRICT_UNTIL_ELAPSED, 0L)
        if (enabled && strictUntilElapsed > 0L) {
            return currentMonotonicMs() >= strictUntilElapsed
        }
        return false
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
        val isProtection = ProtectionStateCoordinator.isProtectionActive(context) || FocusDnsVpnService.isRunning
        return evaluateIsBlocked(
            packageName = packageName,
            blockedPackages = getBlockedPackages(context),
            isStrict = isStrictMode(context),
            isVpnLost = isVpnLost(context),
            isOurApp = (packageName == context.packageName),
            isSystemWhitelisted = isSystemWhitelisted(context, packageName),
            isProtectionActive = isProtection
        )
    }

    fun evaluateIsBlocked(
        packageName: String,
        blockedPackages: Set<String>,
        isStrict: Boolean,
        isVpnLost: Boolean,
        isOurApp: Boolean = false,
        isSystemWhitelisted: Boolean = false,
        isProtectionActive: Boolean = false
    ): Boolean {
        if (isOurApp) return false
        if (isTemporaryPassActive(packageName)) return false
        if (isVpnLost && isStrict) {
            if (!isSystemWhitelisted) return true
        }
        if (blockedPackages.contains(packageName)) return true
        // Tor and 3rd-party VPN apps are blocked whenever Strict Mode OR FocusDNS Protection is active
        if ((isStrict || isProtectionActive) && isVpnApp(packageName)) return true
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
