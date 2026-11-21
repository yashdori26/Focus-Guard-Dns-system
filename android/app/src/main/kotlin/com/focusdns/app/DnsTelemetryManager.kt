package com.focusdns.app

import java.util.concurrent.ConcurrentLinkedDeque
import java.util.concurrent.atomic.AtomicLong

/**
 * DnsTelemetryManager
 * ===================
 * Thread-safe on-device telemetry and query logging coordinator for FocusDNS.
 * Tracks live query volume, blocked threat ratios, latencies, and circular query logs.
 */
object DnsTelemetryManager {

    data class LiveQueryEntry(
        val id: String,
        val domain: String,
        val status: String, // "BLOCKED" or "ALLOWED"
        val reason: String,
        val latencyMs: Int,
        val timestampMs: Long
    ) {
        fun toMap(): Map<String, Any> {
            return mapOf(
                "id" to id,
                "domain" to domain,
                "status" to status,
                "reason" to reason,
                "latencyMs" to latencyMs,
                "timestampMs" to timestampMs
            )
        }
    }

    private const val MAX_RECENT_LOGS = 60

    private val totalQueriesCounter = AtomicLong(0)
    private val blockedQueriesCounter = AtomicLong(0)
    private val totalLatencyAccumulator = AtomicLong(0)
    private val idCounter = AtomicLong(1000)

    private val recentQueriesDeque = ConcurrentLinkedDeque<LiveQueryEntry>()

    var onQueryRecorded: ((LiveQueryEntry) -> Unit)? = null

    fun recordQuery(domain: String, status: String, reason: String, latencyMs: Int): LiveQueryEntry {
        totalQueriesCounter.incrementAndGet()
        if (status == "BLOCKED") {
            blockedQueriesCounter.incrementAndGet()
        }
        totalLatencyAccumulator.addAndGet(maxOf(0L, latencyMs.toLong()))

        val entry = LiveQueryEntry(
            id = "q_${idCounter.incrementAndGet()}",
            domain = domain,
            status = status,
            reason = reason,
            latencyMs = latencyMs,
            timestampMs = System.currentTimeMillis()
        )

        recentQueriesDeque.addFirst(entry)
        while (recentQueriesDeque.size > MAX_RECENT_LOGS) {
            recentQueriesDeque.pollLast()
        }

        onQueryRecorded?.invoke(entry)
        return entry
    }

    fun getTotalQueries(): Long = totalQueriesCounter.get()
    fun getBlockedQueries(): Long = blockedQueriesCounter.get()

    fun getAverageLatencyMs(): Int {
        val total = totalQueriesCounter.get()
        if (total == 0L) return 0
        return (totalLatencyAccumulator.get() / total).toInt()
    }

    fun getTelemetryMap(): Map<String, Any> {
        val total = totalQueriesCounter.get()
        val blocked = blockedQueriesCounter.get()
        val ratio = if (total > 0L) (blocked.toDouble() / total.toDouble()) * 100.0 else 0.0
        val avgLatency = getAverageLatencyMs()

        val recentList = recentQueriesDeque.take(MAX_RECENT_LOGS).map { it.toMap() }

        return mapOf(
            "totalQueries" to total,
            "blockedQueries" to blocked,
            "blockedPercentage" to String.format("%.1f%%", ratio),
            "threatRatio" to ratio,
            "averageLatencyMs" to avgLatency,
            "recentQueries" to recentList
        )
    }

    fun reset() {
        totalQueriesCounter.set(0)
        blockedQueriesCounter.set(0)
        totalLatencyAccumulator.set(0)
        recentQueriesDeque.clear()
    }
}
