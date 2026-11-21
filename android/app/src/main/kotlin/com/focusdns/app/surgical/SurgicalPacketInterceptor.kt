package com.focusdns.app.surgical

import android.util.Log
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * SurgicalPacketInterceptor operates at the socket / VPN tunnel boundary,
 * performing zero-copy inspection of TLS ClientHello SNI headers and DNS queries.
 *
 * It surgically differentiates and decouples CDN video streaming clusters
 * from messaging WebSockets and communication gateways.
 */
class SurgicalPacketInterceptor {

    companion object {
        const val TAG = "SurgicalPacketFilter"
        private const val TLS_HANDSHAKE_TYPE = 0x16
        private const val TLS_CLIENT_HELLO = 0x01
        private const val EXTENSION_SERVER_NAME = 0x00
    }

    enum class PacketDecision {
        ALLOW,
        DROP,
        NXDOMAIN,
        SYN_RST
    }

    data class FilterResult(
        val decision: PacketDecision,
        val matchedDomain: String?,
        val isChatTraffic: Boolean,
        val estimatedBytesSaved: Long
    )

    private val severedDomains = ConcurrentHashMap<String, Boolean>()
    private val allowedChatGateways = ConcurrentHashMap<String, Boolean>()
    private val wildcardSeveredSuffixes = CopyOnWriteList<String>()

    val totalPacketsInspected = AtomicLong(0)
    val totalCdnPacketsBlocked = AtomicLong(0)
    val totalChatPacketsAllowed = AtomicLong(0)
    val totalBytesIntercepted = AtomicLong(0)

    init {
        registerDefaultDomains()
    }

    /**
     * Registers default platform CDN video servers and messaging gateways.
     */
    private fun registerDefaultDomains() {
        // Instagram
        severedDomains["reels.instagram.com"] = true
        wildcardSeveredSuffixes.add(".cdninstagram.com")
        wildcardSeveredSuffixes.add(".fbcdn.net")
        allowedChatGateways["edge-chat.instagram.com"] = true
        allowedChatGateways["graph.instagram.com"] = true

        // YouTube
        severedDomains["googlevideo.com"] = true
        wildcardSeveredSuffixes.add(".googlevideo.com")
        allowedChatGateways["www.youtube.com/live_chat"] = true

        // Reddit
        severedDomains["v.redd.it"] = true
        allowedChatGateways["chat.reddit.com"] = true
        allowedChatGateways["sendbird.reddit.com"] = true

        // Twitter / X
        severedDomains["video.twimg.com"] = true
        allowedChatGateways["twitter.com/i/chat"] = true
        allowedChatGateways["x.com/messages"] = true

        // TikTok
        wildcardSeveredSuffixes.add(".byteoversea.com")
        wildcardSeveredSuffixes.add(".ibytedtos.com")
        wildcardSeveredSuffixes.add(".tiktokcdn.com")
    }

    fun addSeveredDomain(domain: String) {
        val clean = domain.trim().lowercase()
        if (clean.startsWith("*.")) {
            wildcardSeveredSuffixes.add(clean.substring(1)) // ".fbcdn.net"
        } else {
            severedDomains[clean] = true
        }
    }

    fun addAllowedChatGateway(domain: String) {
        allowedChatGateways[domain.trim().lowercase()] = true
    }

    fun removeSeveredDomain(domain: String) {
        val clean = domain.trim().lowercase()
        severedDomains.remove(clean)
        wildcardSeveredSuffixes.remove("." + clean.removePrefix("*."))
    }

    /**
     * Inspects a domain name extracted from DNS query or TLS SNI.
     */
    fun evaluateDomain(domain: String): FilterResult {
        totalPacketsInspected.incrementAndGet()
        val clean = domain.trim().lowercase()

        // 1. Check if explicitly whitelisted as communication gateway (DMs)
        if (allowedChatGateways.containsKey(clean) ||
            allowedChatGateways.keys.any { clean.endsWith(it) }) {
            totalChatPacketsAllowed.incrementAndGet()
            return FilterResult(
                decision = PacketDecision.ALLOW,
                matchedDomain = clean,
                isChatTraffic = true,
                estimatedBytesSaved = 0L
            )
        }

        // 2. Check exact severed video/feed domain
        if (severedDomains.containsKey(clean)) {
            totalCdnPacketsBlocked.incrementAndGet()
            totalBytesIntercepted.addAndGet(2097152L) // ~2 MB per video chunk
            return FilterResult(
                decision = PacketDecision.DROP,
                matchedDomain = clean,
                isChatTraffic = false,
                estimatedBytesSaved = 2097152L
            )
        }

        // 3. Check wildcard suffixes (*.fbcdn.net)
        for (suffix in wildcardSeveredSuffixes) {
            if (clean.endsWith(suffix)) {
                totalCdnPacketsBlocked.incrementAndGet()
                totalBytesIntercepted.addAndGet(2097152L)
                return FilterResult(
                    decision = PacketDecision.DROP,
                    matchedDomain = clean,
                    isChatTraffic = false,
                    estimatedBytesSaved = 2097152L
                )
            }
        }

        return FilterResult(
            decision = PacketDecision.ALLOW,
            matchedDomain = null,
            isChatTraffic = false,
            estimatedBytesSaved = 0L
        )
    }

    /**
     * Zero-allocation extraction of Server Name Indication (SNI) from TLS ClientHello packet.
     * Returns the SNI hostname if present, or null if not a TLS ClientHello or no SNI extension.
     */
    fun extractSniFromTlsClientHello(buffer: ByteBuffer): String? {
        val startPos = buffer.position()
        try {
            if (buffer.remaining() < 5) return null

            // TLS Record Layer Header
            val contentType = buffer.get().toInt() and 0xFF
            if (contentType != TLS_HANDSHAKE_TYPE) return null

            val majorVer = buffer.get().toInt() and 0xFF
            val minorVer = buffer.get().toInt() and 0xFF
            val recordLength = buffer.short.toInt() and 0xFFFF

            if (buffer.remaining() < recordLength) return null

            // Handshake Protocol Header
            val handshakeType = buffer.get().toInt() and 0xFF
            if (handshakeType != TLS_CLIENT_HELLO) return null

            val handshakeLength = ((buffer.get().toInt() and 0xFF) shl 16) or
                    ((buffer.get().toInt() and 0xFF) shl 8) or
                    (buffer.get().toInt() and 0xFF)

            // Skip Client Version (2 bytes) + Client Random (32 bytes)
            if (buffer.remaining() < 34) return null
            buffer.position(buffer.position() + 34)

            // Skip Session ID (1 byte length + data)
            if (!buffer.hasRemaining()) return null
            val sessionIdLen = buffer.get().toInt() and 0xFF
            if (buffer.remaining() < sessionIdLen) return null
            buffer.position(buffer.position() + sessionIdLen)

            // Skip Cipher Suites (2 bytes length + data)
            if (buffer.remaining() < 2) return null
            val cipherSuitesLen = buffer.short.toInt() and 0xFFFF
            if (buffer.remaining() < cipherSuitesLen) return null
            buffer.position(buffer.position() + cipherSuitesLen)

            // Skip Compression Methods (1 byte length + data)
            if (!buffer.hasRemaining()) return null
            val compMethodsLen = buffer.get().toInt() and 0xFF
            if (buffer.remaining() < compMethodsLen) return null
            buffer.position(buffer.position() + compMethodsLen)

            // Extensions block
            if (buffer.remaining() < 2) return null
            val extensionsLen = buffer.short.toInt() and 0xFFFF
            if (buffer.remaining() < extensionsLen) return null

            val extensionsEnd = buffer.position() + extensionsLen

            while (buffer.position() + 4 <= extensionsEnd) {
                val extType = buffer.short.toInt() and 0xFFFF
                val extLen = buffer.short.toInt() and 0xFFFF

                if (extType == EXTENSION_SERVER_NAME) {
                    if (extLen < 5) return null
                    val serverNameListLen = buffer.short.toInt() and 0xFFFF
                    val nameType = buffer.get().toInt() and 0xFF
                    val nameLen = buffer.short.toInt() and 0xFFFF

                    if (buffer.remaining() < nameLen) return null
                    val nameBytes = ByteArray(nameLen)
                    buffer.get(nameBytes)
                    return String(nameBytes, StandardCharsets.US_ASCII)
                } else {
                    if (buffer.remaining() < extLen) break
                    buffer.position(buffer.position() + extLen)
                }
            }

            return null
        } catch (e: Exception) {
            return null
        } finally {
            buffer.position(startPos)
        }
    }

    fun clearAll() {
        severedDomains.clear()
        allowedChatGateways.clear()
        wildcardSeveredSuffixes.clear()
    }
}

// Utility class for thread-safe list in Kotlin
class CopyOnWriteList<T> : Iterable<T> {
    private var list = listOf<T>()

    @Synchronized
    fun add(element: T) {
        list = list + element
    }

    @Synchronized
    fun remove(element: T) {
        list = list - element
    }

    @Synchronized
    fun clear() {
        list = emptyList()
    }

    override fun iterator(): Iterator<T> = list.iterator()
}
