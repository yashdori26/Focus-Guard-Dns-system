package com.focusdns.app

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.io.File
import java.security.MessageDigest

/**
 * Enterprise-grade On-Device Application Audit & Distraction Scanner.
 *
 * Scans installed packages, rigorously validates installation source (Play Store verification),
 * categorizes apps into Social, Video/Streaming, Games, Productivity, etc.,
 * and calculates forensic distraction risk scores.
 */
object AppAuditScannerManager {
    private const val TAG = "AppAuditScanner"

    // Recognized Google Play Store installer package identifiers
    private val PLAY_STORE_INSTALLERS = setOf(
        "com.android.vending",
        "com.google.android.feedback",
        "com.google.android.packageinstaller"
    )

    // Taxonomy of recognized distraction domains mapped to package keywords
    private val DISTRACTION_DOMAIN_TAXONOMY = mapOf(
        "youtube" to listOf("youtube.com", "googlevideo.com", "ytimg.com", "youtu.be"),
        "instagram" to listOf("instagram.com", "cdninstagram.com", "ig.me"),
        "facebook" to listOf("facebook.com", "fbcdn.net", "messenger.com"),
        "tiktok" to listOf("tiktok.com", "tiktokv.com", "tiktokcdn.com", "byteoversea.com", "musical.ly"),
        "reddit" to listOf("reddit.com", "redd.it", "redditmedia.com", "redditstatic.com"),
        "twitter" to listOf("twitter.com", "x.com", "twimg.com", "t.co"),
        "snapchat" to listOf("snapchat.com", "sc-cdn.net"),
        "netflix" to listOf("netflix.com", "nflxvideo.net", "nflximg.net", "nflxext.com"),
        "primevideo" to listOf("primevideo.com", "amazonvideo.com", "aiv-cdn.net"),
        "hotstar" to listOf("hotstar.com", "disneyplus.com"),
        "twitch" to listOf("twitch.tv", "ttvnw.net", "jtvnw.net"),
        "discord" to listOf("discord.com", "discord.gg", "discordapp.com"),
        "telegram" to listOf("telegram.org", "t.me"),
        "whatsapp" to listOf("whatsapp.com", "whatsapp.net"),
        "pinterest" to listOf("pinterest.com", "pinimg.com"),
        "spotify" to listOf("spotify.com", "scdn.co", "spoti.fi"),
        "roblox" to listOf("roblox.com", "rbxcdn.com"),
        "pubg" to listOf("pubgmobile.com", "tencentmusic.com", "proximabeta.com"),
        "freefire" to listOf("freefiremobile.com", "garena.com"),
        "candycrush" to listOf("king.com"),
        "clashofclans" to listOf("supercell.com"),
        "brawlstars" to listOf("supercell.com"),
        "genshin" to listOf("mihoyo.com", "hoyoverse.com"),
        "chess" to listOf("chess.com"),
        "tinder" to listOf("tinder.com", "gotinder.com"),
        "bumble" to listOf("bumble.com"),
        "hinge" to listOf("hinge.co")
    )

    data class AuditedAppItem(
        val packageName: String,
        val appName: String,
        val installerPackage: String?,
        val isPlayStoreVerified: Boolean,
        val isSystemApp: Boolean,
        val category: String, // "social", "video", "gaming", "communication", "shopping", "other"
        val distractionScore: Int, // 0 - 100
        val isDistraction: Boolean,
        val installTimeMs: Long,
        val lastUpdateTimeMs: Long,
        val targetSdkVersion: Int,
        val versionName: String,
        val associatedDomains: List<String>
    ) {
        fun toMap(): Map<String, Any?> {
            return mapOf(
                "packageName" to packageName,
                "appName" to appName,
                "installerPackage" to installerPackage,
                "isPlayStoreVerified" to isPlayStoreVerified,
                "isSystemApp" to isSystemApp,
                "category" to category,
                "distractionScore" to distractionScore,
                "isDistraction" to isDistraction,
                "installTimeMs" to installTimeMs,
                "lastUpdateTimeMs" to lastUpdateTimeMs,
                "targetSdkVersion" to targetSdkVersion,
                "versionName" to versionName,
                "associatedDomains" to associatedDomains
            )
        }
    }

    /**
     * Scans all applications installed on device, rigorously filtering and verifying Play Store origin.
     */
    fun scanDeviceApps(context: Context): Map<String, Any> {
        val pm = context.packageManager
        val resultApps = mutableListOf<AuditedAppItem>()

        // Query launcher-enabled applications so we only audit user-facing apps
        val launcherIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val launcherResolveInfos = pm.queryIntentActivities(launcherIntent, 0)
        val launcherPackageNames = launcherResolveInfos.map { it.activityInfo.packageName }.toSet()

        val installedPackages = pm.getInstalledPackages(PackageManager.GET_META_DATA)

        var totalScanned = 0
        var playStoreVerifiedCount = 0
        var distractionCount = 0

        for (pkgInfo in installedPackages) {
            val pkg = pkgInfo.packageName
            val appInfo = pkgInfo.applicationInfo ?: continue

            // Exclude our own application from audit
            if (pkg == context.packageName) continue

            totalScanned++

            // Check system flags
            val isSystem = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            val isUpdatedSystem = (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0

            // Obtain installer package source
            val installerPackage = getInstallerPackage(context, pkg)
            val isPlayStore = installerPackage != null && PLAY_STORE_INSTALLERS.contains(installerPackage)

            // Strictly classify user-installed Play Store apps:
            // 1) Must not be pure system app (or if updated system, must have launcher activity and Play Store origin)
            // 2) Must have a launcher activity or be marked as game/social
            val isUserApp = !isSystem || (isUpdatedSystem && isPlayStore)

            // Cross verification for Play Store status
            val isPlayStoreVerified = isPlayStore && isUserApp

            if (isPlayStoreVerified) {
                playStoreVerifiedCount++
            }

            // Exclude internal system background packages that do not have a user interface
            val hasLauncher = launcherPackageNames.contains(pkg)
            if (!hasLauncher && !isPlayStoreVerified) {
                continue
            }

            // Extract App label
            val appName = try {
                pm.getApplicationLabel(appInfo).toString()
            } catch (e: Exception) {
                pkg
            }

            // Categorize the app
            val category = resolveAppCategory(appInfo, pkg, appName)
            val distractionScore = computeDistractionScore(category, pkg, appName)
            val isDistraction = distractionScore >= 45

            if (isDistraction && isPlayStoreVerified) {
                distractionCount++
            }

            // Associated DNS blocking domains
            val associatedDomains = resolveAssociatedDomains(pkg, appName)

            val item = AuditedAppItem(
                packageName = pkg,
                appName = appName,
                installerPackage = installerPackage,
                isPlayStoreVerified = isPlayStoreVerified,
                isSystemApp = isSystem,
                category = category,
                distractionScore = distractionScore,
                isDistraction = isDistraction,
                installTimeMs = pkgInfo.firstInstallTime,
                lastUpdateTimeMs = pkgInfo.lastUpdateTime,
                targetSdkVersion = appInfo.targetSdkVersion,
                versionName = pkgInfo.versionName ?: "1.0",
                associatedDomains = associatedDomains
            )

            resultApps.add(item)
        }

        // Sort: Play Store verified distractions first, highest distraction score descending
        val sortedApps = resultApps.sortedWith(
            compareByDescending<AuditedAppItem> { it.isPlayStoreVerified }
                .thenByDescending { it.isDistraction }
                .thenByDescending { it.distractionScore }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.appName }
        )

        val auditGrade = calculateAuditGrade(distractionCount, playStoreVerifiedCount)

        Log.i(TAG, "Completed app audit. Scanned: $totalScanned, PlayStore: $playStoreVerifiedCount, Distractions: $distractionCount")

        return mapOf(
            "totalScanned" to totalScanned,
            "playStoreVerifiedCount" to playStoreVerifiedCount,
            "distractionCount" to distractionCount,
            "auditGrade" to auditGrade,
            "timestamp" to System.currentTimeMillis(),
            "apps" to sortedApps.map { it.toMap() }
        )
    }

    /**
     * Resolves the installer source package using appropriate API for Android SDK version.
     */
    private fun getInstallerPackage(context: Context, packageName: String): String? {
        return try {
            val pm = context.packageManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val info = pm.getInstallSourceInfo(packageName)
                info.installingPackageName ?: info.initiatingPackageName
            } else {
                @Suppress("DEPRECATION")
                pm.getInstallerPackageName(packageName)
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Resolves app category based on Android ApplicationInfo category flags, package keywords, and heuristics.
     */
    private fun resolveAppCategory(appInfo: ApplicationInfo, packageName: String, appName: String): String {
        val lowerPkg = packageName.lowercase()
        val lowerName = appName.lowercase()

        // 1. Android Native Category Flags (API 26+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            when (appInfo.category) {
                ApplicationInfo.CATEGORY_GAME -> return "gaming"
                ApplicationInfo.CATEGORY_SOCIAL -> return "social"
                ApplicationInfo.CATEGORY_VIDEO -> return "video"
                ApplicationInfo.CATEGORY_AUDIO -> return "media"
                ApplicationInfo.CATEGORY_NEWS -> return "news"
                ApplicationInfo.CATEGORY_PRODUCTIVITY -> return "productivity"
            }
        }

        // 2. Legacy game flag
        if ((appInfo.flags and ApplicationInfo.FLAG_IS_GAME) != 0) {
            return "gaming"
        }

        // 3. Keyword Heuristic Classifier
        if (isSocialApp(lowerPkg, lowerName)) return "social"
        if (isVideoStreamingApp(lowerPkg, lowerName)) return "video"
        if (isGamingApp(lowerPkg, lowerName)) return "gaming"
        if (isCommunicationApp(lowerPkg, lowerName)) return "communication"
        if (isShoppingApp(lowerPkg, lowerName)) return "shopping"

        return "other"
    }

    private fun isSocialApp(pkg: String, name: String): Boolean {
        return pkg.contains("instagram") || pkg.contains("facebook") || pkg.contains("katana") ||
                pkg.contains("reddit") || pkg.contains("tiktok") || pkg.contains("musically") ||
                pkg.contains("twitter") || pkg.contains("snapchat") || pkg.contains("pinterest") ||
                pkg.contains("linkedin") || pkg.contains("tinder") || pkg.contains("bumble") ||
                pkg.contains("threads") || pkg.contains("barcelona") || name.contains("instagram") ||
                name.contains("tiktok") || name.contains("reddit") || name.contains("facebook") ||
                name.contains("twitter") || name.contains("snapchat")
    }

    private fun isVideoStreamingApp(pkg: String, name: String): Boolean {
        return pkg.contains("youtube") || pkg.contains("netflix") || pkg.contains("primevideo") ||
                pkg.contains("hotstar") || pkg.contains("twitch") || pkg.contains("hulu") ||
                pkg.contains("vimeo") || pkg.contains("disney") || pkg.contains("mxplayer") ||
                pkg.contains("jiocinema") || name.contains("youtube") || name.contains("netflix") ||
                name.contains("twitch") || name.contains("hotstar") || name.contains("prime video")
    }

    private fun isGamingApp(pkg: String, name: String): Boolean {
        return pkg.contains("game") || pkg.contains("roblox") || pkg.contains("pubg") ||
                pkg.contains("supercell") || pkg.contains("king.candy") || pkg.contains("garena") ||
                pkg.contains("tencent") || pkg.contains("riotgames") || pkg.contains("epicgames") ||
                pkg.contains("blizzard") || pkg.contains("ea.gp") || pkg.contains("chess") ||
                name.contains("game") || name.contains("clash") || name.contains("pubg") ||
                name.contains("roblox") || name.contains("candy crush")
    }

    private fun isCommunicationApp(pkg: String, name: String): Boolean {
        return pkg.contains("whatsapp") || pkg.contains("telegram") || pkg.contains("discord") ||
                pkg.contains("signal") || pkg.contains("skype") || pkg.contains("zoom") ||
                pkg.contains("teams") || pkg.contains("viber") || pkg.contains("wechat")
    }

    private fun isShoppingApp(pkg: String, name: String): Boolean {
        return pkg.contains("amazon") || pkg.contains("flipkart") || pkg.contains("myntra") ||
                pkg.contains("meesho") || pkg.contains("aliexpress") || pkg.contains("ebay") ||
                pkg.contains("shein") || pkg.contains("temu")
    }

    /**
     * Computes a distraction score from 0 to 100 based on addictive algorithm engagement.
     */
    private fun computeDistractionScore(category: String, pkg: String, name: String): Int {
        val lowerPkg = pkg.lowercase()
        val lowerName = name.lowercase()

        // Infinite Short-Form Video feeds (Highest addiction profile)
        if (lowerPkg.contains("tiktok") || lowerPkg.contains("musically") ||
            (lowerPkg.contains("instagram") && !lowerPkg.contains("lite")) ||
            lowerPkg.contains("youtube") || lowerPkg.contains("snapchat")) {
            return 98
        }

        // High engagement social feeds & forums
        if (lowerPkg.contains("reddit") || lowerPkg.contains("twitter") ||
            lowerPkg.contains("facebook") || lowerPkg.contains("threads")) {
            return 90
        }

        // Multiplayer / Gacha games
        if (category == "gaming") {
            if (lowerPkg.contains("roblox") || lowerPkg.contains("pubg") || lowerPkg.contains("freefire")) {
                return 95
            }
            return 82
        }

        // Long-form video streaming
        if (category == "video") {
            return 80
        }

        // Dating & Hookup apps
        if (lowerPkg.contains("tinder") || lowerPkg.contains("bumble") || lowerPkg.contains("hinge")) {
            return 85
        }

        // Shopping & Impulse buying
        if (category == "shopping") {
            return 60
        }

        // Chat & Messaging (Communication)
        if (category == "communication") {
            if (lowerPkg.contains("discord")) return 75
            if (lowerPkg.contains("telegram")) return 65
            return 40 // WhatsApp / Signal / Work messaging
        }

        if (category == "social") {
            return 75
        }

        return 10
    }

    /**
     * Resolves matching DNS domain rules for the specified package.
     */
    private fun resolveAssociatedDomains(packageName: String, appName: String): List<String> {
        val lowerPkg = packageName.lowercase()
        val lowerName = appName.lowercase()

        for ((key, domains) in DISTRACTION_DOMAIN_TAXONOMY) {
            if (lowerPkg.contains(key) || lowerName.contains(key)) {
                return domains
            }
        }
        return emptyList()
    }

    private fun calculateAuditGrade(distractionCount: Int, playStoreCount: Int): String {
        if (playStoreCount == 0) return "A+"
        val ratio = distractionCount.toDouble() / playStoreCount.toDouble()
        return when {
            ratio <= 0.10 -> "A+"
            ratio <= 0.25 -> "A"
            ratio <= 0.40 -> "B"
            ratio <= 0.60 -> "C"
            ratio <= 0.80 -> "D"
            else -> "F"
        }
    }
}
