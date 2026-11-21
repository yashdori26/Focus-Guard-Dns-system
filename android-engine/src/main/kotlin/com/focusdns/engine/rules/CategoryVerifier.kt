package com.focusdns.engine.rules

import java.net.IDN
import java.util.Locale

/**
 * On-device Lexical Category Verifier for Double Verification.
 * Evaluates domains and applications against category vocabulary, n-grams, and TLD priors
 * to verify if a target matches an active blocked category (Adult, Gambling, Gaming, Social, etc.).
 */
object CategoryVerifier {

    const val CAT_ADULT = "ADULT_CONTENT"
    const val CAT_GAMBLING = "CRYPTO_GAMBLING"
    const val CAT_GAMING = "GAMING"
    const val CAT_SOCIAL = "SOCIAL_MEDIA"
    const val CAT_STREAMING = "STREAMING_ENTERTAINMENT"
    const val CAT_PIRACY = "PIRACY"

    // High distraction categories blocked during Focus sessions
    val DEFAULT_BLOCKED_CATEGORIES = setOf(
        CAT_ADULT, CAT_GAMBLING, CAT_GAMING, CAT_SOCIAL, CAT_STREAMING, CAT_PIRACY
    )

    // TLD Priors strongly indicating specific categories
    private val TLD_PRIORS = mapOf(
        "xxx" to CAT_ADULT,
        "porn" to CAT_ADULT,
        "adult" to CAT_ADULT,
        "sexy" to CAT_ADULT,
        "cam" to CAT_ADULT,
        "casino" to CAT_GAMBLING,
        "bet" to CAT_GAMBLING,
        "poker" to CAT_GAMBLING,
        "crypto" to CAT_GAMBLING,
        "game" to CAT_GAMING,
        "games" to CAT_GAMING,
        "gg" to CAT_GAMING,
        "quest" to CAT_GAMING
    )

    // Weighted lexical keyword vocabulary (keyword -> category)
    private val CATEGORY_KEYWORDS = mapOf(
        // Adult
        "porn" to CAT_ADULT,
        "pornhub" to CAT_ADULT,
        "xvideos" to CAT_ADULT,
        "xnxx" to CAT_ADULT,
        "stripchat" to CAT_ADULT,
        "erotic" to CAT_ADULT,
        "onlyfans" to CAT_ADULT,
        "cams" to CAT_ADULT,
        "nudity" to CAT_ADULT,

        // Gambling & Betting
        "casino" to CAT_GAMBLING,
        "bet" to CAT_GAMBLING,
        "betting" to CAT_GAMBLING,
        "bet365" to CAT_GAMBLING,
        "poker" to CAT_GAMBLING,
        "stake" to CAT_GAMBLING,
        "1xbet" to CAT_GAMBLING,
        "slots" to CAT_GAMBLING,
        "roulette" to CAT_GAMBLING,
        "wager" to CAT_GAMBLING,
        "lottery" to CAT_GAMBLING,

        // Gaming
        "steam" to CAT_GAMING,
        "roblox" to CAT_GAMING,
        "riotgames" to CAT_GAMING,
        "epicgames" to CAT_GAMING,
        "blizzard" to CAT_GAMING,
        "playstation" to CAT_GAMING,
        "xbox" to CAT_GAMING,
        "nintendo" to CAT_GAMING,
        "minecraft" to CAT_GAMING,
        "valorant" to CAT_GAMING,
        "genshin" to CAT_GAMING,
        "twitch" to CAT_GAMING,
        "discord" to CAT_GAMING,

        // Social Media & Algorithmic Feeds
        "instagram" to CAT_SOCIAL,
        "tiktok" to CAT_SOCIAL,
        "byteoversea" to CAT_SOCIAL,
        "facebook" to CAT_SOCIAL,
        "fbcdn" to CAT_SOCIAL,
        "reddit" to CAT_SOCIAL,
        "twitter" to CAT_SOCIAL,
        "threads" to CAT_SOCIAL,
        "reels" to CAT_SOCIAL,
        "shorts" to CAT_SOCIAL,

        // Streaming
        "netflix" to CAT_STREAMING,
        "hulu" to CAT_STREAMING,
        "disneyplus" to CAT_STREAMING,

        // Piracy
        "torrent" to CAT_PIRACY,
        "1337x" to CAT_PIRACY,
        "thepiratebay" to CAT_PIRACY,
        "pirate" to CAT_PIRACY,
        "warez" to CAT_PIRACY
    )

    data class VerificationResult(
        val isMatched: Boolean,
        val matchedCategory: String?,
        val matchedToken: String?,
        val confidence: Double
    )

    /**
     * Verifies if a domain matches any blocked category via lexical tokenization and TLD matching.
     */
    fun verifyDomainCategory(
        domain: String,
        activeCategories: Set<String> = DEFAULT_BLOCKED_CATEGORIES
    ): VerificationResult {
        if (domain.isBlank()) {
            return VerificationResult(false, null, null, 0.0)
        }

        val cleanDomain = canonicalize(domain)
        val parts = cleanDomain.split(".").filter { it.isNotEmpty() }
        if (parts.isEmpty()) {
            return VerificationResult(false, null, null, 0.0)
        }

        // 1. TLD check
        val tld = parts.last()
        val tldCat = TLD_PRIORS[tld]
        if (tldCat != null && activeCategories.contains(tldCat)) {
            return VerificationResult(true, tldCat, tld, 0.95)
        }

        // 2. Tokenized domain inspection (labels + hyphen splits)
        for (part in parts) {
            val subTokens = part.split("-", "_")
            for (token in subTokens) {
                if (token.length < 3) continue
                val cat = CATEGORY_KEYWORDS[token]
                if (cat != null && activeCategories.contains(cat)) {
                    return VerificationResult(true, cat, token, 0.90)
                }
            }
        }

        // 3. Substring check for high-confidence tokens in main label
        val mainLabel = if (parts.size >= 2) parts[parts.size - 2] else parts[0]
        for ((keyword, cat) in CATEGORY_KEYWORDS) {
            if (keyword.length >= 4 && mainLabel.contains(keyword)) {
                if (activeCategories.contains(cat)) {
                    return VerificationResult(true, cat, keyword, 0.85)
                }
            }
        }

        return VerificationResult(false, null, null, 0.0)
    }

    /**
     * Verifies if an application package name or visible title matches blocked categories.
     */
    fun verifyAppCategory(
        packageName: String,
        appTitle: String? = null,
        activeCategories: Set<String> = DEFAULT_BLOCKED_CATEGORIES
    ): VerificationResult {
        val cleanPkg = packageName.lowercase(Locale.ROOT)

        // 1. Package tokens
        val pkgTokens = cleanPkg.split(".", "_", "-")
        for (token in pkgTokens) {
            if (token.length < 3) continue
            val cat = CATEGORY_KEYWORDS[token]
            if (cat != null && activeCategories.contains(cat)) {
                return VerificationResult(true, cat, token, 0.92)
            }
        }

        // 2. App title inspection if present
        if (!appTitle.isNullOrBlank()) {
            val titleTokens = appTitle.lowercase(Locale.ROOT).split(" ", "-", "_", ":")
            for (token in titleTokens) {
                if (token.length < 3) continue
                val cat = CATEGORY_KEYWORDS[token]
                if (cat != null && activeCategories.contains(cat)) {
                    return VerificationResult(true, cat, token, 0.88)
                }
            }
        }

        return VerificationResult(false, null, null, 0.0)
    }

    private fun canonicalize(domain: String): String {
        return try {
            IDN.toASCII(domain.trim().lowercase(Locale.ROOT))
        } catch (e: Exception) {
            domain.trim().lowercase(Locale.ROOT)
        }
    }
}
