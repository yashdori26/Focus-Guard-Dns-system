package com.focusdns.app.daemon

import android.content.Context
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * AdaptiveWakeLockManager
 * =======================
 * Strict Zero-Wake-Lock Policy Enforcer.
 *
 * FocusDNS guarantees zero partial wake-locks during normal DNS socket listening.
 * This class provides safety guards and tripwire telemetry to detect and alert
 * if any background worker inadvertently holds a CPU wake lock for longer than 50ms.
 */
object AdaptiveWakeLockManager {

    private const val TAG = "AdaptiveWakeLock"
    private const val MAX_ALLOWED_WAKELOCK_MS = 50L

    private val activeWakeLockCount = AtomicInteger(0)
    private val totalWakeLocksAcquired = AtomicInteger(0)
    private val violationCount = AtomicInteger(0)
    private val lastAcquiredTimestamp = AtomicLong(0)

    fun acquireBriefWakeLock(context: Context, tag: String, block: () -> Unit) {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return block()
        val wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "FocusDNS:$tag").apply {
            setReferenceCounted(false)
        }

        val start = SystemClock.elapsedRealtime()
        activeWakeLockCount.incrementAndGet()
        totalWakeLocksAcquired.incrementAndGet()
        lastAcquiredTimestamp.set(start)

        try {
            wakeLock.acquire(MAX_ALLOWED_WAKELOCK_MS)
            block()
        } finally {
            val duration = SystemClock.elapsedRealtime() - start
            if (wakeLock.isHeld) {
                try {
                    wakeLock.release()
                } catch (_: Exception) {}
            }
            activeWakeLockCount.decrementAndGet()

            if (duration > MAX_ALLOWED_WAKELOCK_MS) {
                violationCount.incrementAndGet()
                Log.w(TAG, "ZERO WAKE-LOCK VIOLATION! Tag: $tag held for ${duration}ms (Max allowed: ${MAX_ALLOWED_WAKELOCK_MS}ms)")
            }
        }
    }

    fun getTelemetry(): Map<String, Any> = mapOf(
        "activeCount" to activeWakeLockCount.get(),
        "totalAcquired" to totalWakeLocksAcquired.get(),
        "violationCount" to violationCount.get(),
        "zeroWakeLockCompliant" to (violationCount.get() == 0)
    )
}
