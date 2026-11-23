package com.focusdns.focus_dns

import java.util.concurrent.atomic.AtomicLong

object DnsStats {
    private val total = AtomicLong()
    private val blocked = AtomicLong()
    private val latencySum = AtomicLong()
    private val recent = ArrayDeque<Map<String, Any>>()
    private var seq = 0L

    @Synchronized
    fun record(domain: String, status: String, reason: String, latencyMs: Int) {
        total.incrementAndGet()
        if (status == "BLOCKED") blocked.incrementAndGet()
        latencySum.addAndGet(latencyMs.toLong())
        seq++
        recent.addFirst(mapOf(
            "id" to seq.toString(), "domain" to domain, "status" to status, "reason" to reason,
            "latencyMs" to latencyMs, "timestampMs" to System.currentTimeMillis()
        ))
        while (recent.size > 50) recent.removeLast()
    }

    @Synchronized
    fun snapshot(): Map<String, Any> {
        val t = total.get()
        val b = blocked.get()
        val ratio = if (t == 0L) 0.0 else b.toDouble() / t.toDouble()
        return mapOf(
            "totalQueries" to t.toInt(),
            "blockedQueries" to b.toInt(),
            "blockedPercentage" to String.format("%.1f%%", ratio * 100.0),
            "threatRatio" to ratio,
            "averageLatencyMs" to (if (t == 0L) 0 else (latencySum.get() / t).toInt()),
            "recentQueries" to recent.toList()
        )
    }
}
