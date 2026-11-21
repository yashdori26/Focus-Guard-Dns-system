package com.focusdns.engine.rules

import android.net.VpnService
import android.util.Log
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.IDN
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * High-performance on-device domain matching with Double Verification
 * and RFC 8484 zero-log DNS-over-HTTPS upstream resolver (Cloudflare & Quad9).
 */
class RulesEngine(
    private var dohEndpoint: String = "https://cloudflare-dns.com/dns-query",
    private var fallbackDohEndpoint: String = "https://dns.quad9.net/dns-query"
) {
    companion object {
        const val TAG = "RulesEngine"
        const val PRIMARY_DOH = "https://cloudflare-dns.com/dns-query"
        const val FALLBACK_DOH = "https://dns.quad9.net/dns-query"
    }

    private val exactDenyList = ConcurrentHashMap.newKeySet<String>()
    private val wildcardDenySuffixes = ConcurrentHashMap.newKeySet<String>()
    private val dohExecutor = Executors.newFixedThreadPool(4)

    // Optional VpnService reference for socket protection to avoid VPN loops
    var vpnService: VpnService? = null

    init {
        registerBuiltInRules()
    }

    private fun registerBuiltInRules() {
        exactDenyList.addAll(
            listOf(
                "youtube.com", "youtu.be", "googlevideo.com", "ytimg.com",
                "instagram.com", "cdninstagram.com", "threads.net",
                "tiktok.com", "byteoversea.com", "ibytedtos.com",
                "reddit.com", "redd.it", "redditmedia.com",
                "facebook.com", "fbcdn.net",
                "pornhub.com", "xvideos.com", "xnxx.com", "stripchat.com",
                "stake.com", "bet365.com", "1xbet.com",
                "1337x.to", "thepiratebay.org", "torrentfreak.com"
            )
        )

        wildcardDenySuffixes.addAll(
            listOf(
                "youtube.com",
                "googlevideo.com",
                "instagram.com",
                "cdninstagram.com",
                "tiktok.com",
                "byteoversea.com",
                "tiktokv.com",
                "reddit.com",
                "facebook.com",
                "pornhub.com"
            )
        )
    }

    data class DoubleVerificationVerdict(
        val isBlocked: Boolean,
        val reason: String,
        val tier: Int, // 1 = Explicit Blocklist, 2 = Lexical Category Match, 0 = Clean
        val matchedCategory: String? = null
    )

    /**
     * Performs Double Verification on a domain:
     * Check 1 (Tier 1): Checks exact blocked list and wildcard suffix match.
     * Check 2 (Tier 2): Checks address, tokens, and TLD against blocked category vocabulary.
     * If either matches -> Block. If neither matches -> Allow.
     */
    fun doubleVerifyDomain(
        rawDomain: String,
        activeCategories: Set<String> = CategoryVerifier.DEFAULT_BLOCKED_CATEGORIES
    ): DoubleVerificationVerdict {
        if (rawDomain.isEmpty()) {
            return DoubleVerificationVerdict(false, "Empty domain", 0)
        }
        val domain = canonicalizeDomain(rawDomain)

        // Tier 1: Explicit Denylist & Wildcard Match
        if (exactDenyList.contains(domain)) {
            return DoubleVerificationVerdict(
                isBlocked = true,
                reason = "Double Verification Tier 1: Exact domain match in blocklist ($domain)",
                tier = 1
            )
        }
        for (suffix in wildcardDenySuffixes) {
            if (domain == suffix || domain.endsWith(".$suffix")) {
                return DoubleVerificationVerdict(
                    isBlocked = true,
                    reason = "Double Verification Tier 1: Wildcard match in blocklist (*.$suffix)",
                    tier = 1
                )
            }
        }

        // Tier 2: Category & Lexical verification of address, name, and TLD
        val catResult = CategoryVerifier.verifyDomainCategory(domain, activeCategories)
        if (catResult.isMatched) {
            return DoubleVerificationVerdict(
                isBlocked = true,
                reason = "Double Verification Tier 2: Address/name matches blocked category (${catResult.matchedCategory} via '${catResult.matchedToken}')",
                tier = 2,
                matchedCategory = catResult.matchedCategory
            )
        }

        return DoubleVerificationVerdict(
            isBlocked = false,
            reason = "Double Verification Passed: Domain clean and unblocked",
            tier = 0
        )
    }

    fun isDomainBlocked(rawDomain: String): Boolean {
        return doubleVerifyDomain(rawDomain).isBlocked
    }

    fun updateDohEndpoint(newUrl: String) {
        dohEndpoint = newUrl
    }

    fun applyRulePack(pack: SignedRulePackParser.ParsedRulePack) {
        if (pack.killSwitchActive) {
            Log.w(TAG, "Emergency kill switch active. Reverting to base safety rules.")
            return
        }
        exactDenyList.addAll(pack.exactBlockedDomains)
        wildcardDenySuffixes.addAll(pack.wildcardSuffixes)
        Log.i(TAG, "Applied dynamic rule pack v${pack.version} (${exactDenyList.size} rules active).")
    }

    private fun canonicalizeDomain(domain: String): String {
        return try {
            IDN.toASCII(domain.trim().lowercase())
        } catch (e: Exception) {
            domain.trim().lowercase()
        }
    }

    /**
     * Resolves an allowed DNS query upstream via RFC 8484 DNS-over-HTTPS.
     * Uses primary zero-log provider (Cloudflare) with automatic fallback to Quad9.
     */
    fun resolveUpstreamDoH(
        domain: String,
        packetBuffer: ByteArray,
        dnsOffset: Int,
        dnsLength: Int,
        callback: (ByteArray?) -> Unit
    ) {
        dohExecutor.execute {
            val response = executeDoHQuery(dohEndpoint, packetBuffer, dnsOffset, dnsLength)
                ?: executeDoHQuery(fallbackDohEndpoint, packetBuffer, dnsOffset, dnsLength)
            callback(response)
        }
    }

    private fun executeDoHQuery(
        endpoint: String,
        packetBuffer: ByteArray,
        dnsOffset: Int,
        dnsLength: Int
    ): ByteArray? {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL(endpoint)
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                doInput = true
                connectTimeout = 3000
                readTimeout = 3000
                setRequestProperty("Content-Type", "application/dns-message")
                setRequestProperty("Accept", "application/dns-message")
            }

            conn.outputStream.use { os ->
                os.write(packetBuffer, dnsOffset, dnsLength)
                os.flush()
            }

            if (conn.responseCode == 200) {
                conn.inputStream.use { it.readBytes() }
            } else {
                Log.w(TAG, "Upstream DoH ($endpoint) returned HTTP ${conn.responseCode}")
                null
            }
        } catch (e: Exception) {
            Log.w(TAG, "DoH error ($endpoint): ${e.message}")
            null
        } finally {
            conn?.disconnect()
        }
    }
}
