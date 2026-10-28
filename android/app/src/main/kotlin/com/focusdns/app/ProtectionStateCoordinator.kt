package com.focusdns.app

import android.content.Context
import android.content.SharedPreferences
import android.os.SystemClock
import android.util.Log
import java.security.MessageDigest
import java.util.concurrent.CopyOnWriteArrayList
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * ProtectionStateCoordinator
 * ==========================
 * Central cryptographic authority governing device uninstallation, Device Administrator
 * deactivation, and focus session locking for FocusDNS.
 *
 * Core Law of Uninstallation:
 * - When Protection Mode is OFF and Timer Mode is NOT running:
 *     canUninstall() == TRUE
 *     canDeactivateDeviceAdmin() == TRUE
 *     The user can freely uninstall the app like any standard Android application.
 *
 * - When Protection Mode is ON OR Timer Mode is ACTIVE (>0s remaining):
 *     canUninstall() == FALSE
 *     canDeactivateDeviceAdmin() == FALSE
 *     Uninstallation, force-stop, and admin revocation are strictly intercepted
 *     and blocked until the timer reaches zero or protection is stopped.
 */
object ProtectionStateCoordinator {

    private const val TAG = "ProtectionCoordinator"
    private const val PREFS_NAME = "focus_dns_protection_state"

    // Storage Keys
    private const val KEY_PROTECTION_ACTIVE = "key_protection_active"
    private const val KEY_TIMER_ACTIVE = "key_timer_active"
    private const val KEY_TIMER_DURATION_SEC = "key_timer_duration_sec"
    private const val KEY_TIMER_START_ELAPSED = "key_timer_start_elapsed"
    private const val KEY_TIMER_EXPIRE_ELAPSED = "key_timer_expire_elapsed"
    private const val KEY_DEVICE_ADMIN_ACTIVE = "key_device_admin_active"
    private const val KEY_STATE_SIGNATURE = "key_state_signature"
    private const val KEY_FORCE_UNINSTALL_LOCKED = "key_force_uninstall_locked"

    // Hardened internal secret seed for HMAC state validation
    private val HMAC_SECRET_SEED = byteArrayOf(
        0x46, 0x6F, 0x63, 0x75, 0x73, 0x44, 0x4E, 0x53,
        0x50, 0x72, 0x6F, 0x74, 0x65, 0x63, 0x74, 0x69,
        0x6F, 0x6E, 0x53, 0x65, 0x61, 0x6C, 0x32, 0x30,
        0x32, 0x36, 0x4B, 0x65, 0x79, 0x21, 0x24, 0x2A
    )

    enum class SessionState {
        IDLE,                   // No protection, no timer -> Uninstallation allowed
        PROTECTION_ONLY,        // DNS/VPN active without strict timer -> Must disable protection to uninstall
        TIMER_ACTIVE,           // Countdown timer active -> Uninstallation locked until timer expires
        LOCKED_PROTECTED        // Both DNS/VPN and Timer active -> Completely locked
    }

    interface StateChangeListener {
        fun onProtectionStateChanged(
            sessionState: SessionState,
            canUninstall: Boolean,
            remainingSeconds: Long
        )
    }

    private val listeners = CopyOnWriteArrayList<StateChangeListener>()

    fun registerListener(listener: StateChangeListener) {
        if (!listeners.contains(listener)) {
            listeners.add(listener)
        }
    }

    fun unregisterListener(listener: StateChangeListener) {
        listeners.remove(listener)
    }

    private fun notifyListeners(sessionState: SessionState, canUninstall: Boolean, remainingSeconds: Long) {
        for (listener in listeners) {
            try {
                listener.onProtectionStateChanged(sessionState, canUninstall, remainingSeconds)
            } catch (e: Exception) {
                Log.e(TAG, "Error notifying state change listener: ${e.message}")
            }
        }
    }

    fun currentMonotonicMs(): Long {
        return try {
            SystemClock.elapsedRealtime()
        } catch (e: Throwable) {
            System.currentTimeMillis()
        }
    }

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    // --- Cryptographic HMAC State Seal ---

    private fun computeSignature(
        protectionActive: Boolean,
        timerActive: Boolean,
        expireElapsed: Long,
        adminActive: Boolean
    ): String {
        return try {
            val payload = "$protectionActive:$timerActive:$expireElapsed:$adminActive"
            val mac = Mac.getInstance("HmacSHA256")
            val secretKey = SecretKeySpec(HMAC_SECRET_SEED, "HmacSHA256")
            mac.init(secretKey)
            val hash = mac.doFinal(payload.toByteArray(Charsets.UTF_8))
            hash.joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            ""
        }
    }

    private fun verifyStateIntegrity(context: Context): Boolean {
        val prefs = getPrefs(context)
        val protectionActive = prefs.getBoolean(KEY_PROTECTION_ACTIVE, false)
        val timerActive = prefs.getBoolean(KEY_TIMER_ACTIVE, false)
        val expireElapsed = prefs.getLong(KEY_TIMER_EXPIRE_ELAPSED, 0L)
        val adminActive = prefs.getBoolean(KEY_DEVICE_ADMIN_ACTIVE, false)
        val storedSig = prefs.getString(KEY_STATE_SIGNATURE, null) ?: return true

        val computed = computeSignature(protectionActive, timerActive, expireElapsed, adminActive)
        return computed == storedSig
    }

    // --- State Ingestion & Modification ---

    /**
     * Updates the active protection status (DNS interception / VPN tunnel state).
     */
    fun setProtectionActive(context: Context, active: Boolean) {
        val prefs = getPrefs(context)
        val timerActive = prefs.getBoolean(KEY_TIMER_ACTIVE, false)
        val expireElapsed = prefs.getLong(KEY_TIMER_EXPIRE_ELAPSED, 0L)
        val adminActive = prefs.getBoolean(KEY_DEVICE_ADMIN_ACTIVE, false)

        val sig = computeSignature(active, timerActive, expireElapsed, adminActive)
        prefs.edit()
            .putBoolean(KEY_PROTECTION_ACTIVE, active)
            .putString(KEY_STATE_SIGNATURE, sig)
            .apply()

        checkAndNotifyState(context)
        Log.i(TAG, "Protection active set to: $active (canUninstall: ${canUninstall(context)})")
    }

    fun isProtectionActive(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_PROTECTION_ACTIVE, false)
    }

    /**
     * Activates or clears the strict countdown timer.
     * Duration is specified in seconds. When durationSeconds <= 0, timer is cleared.
     */
    fun setStrictTimer(context: Context, durationSeconds: Long) {
        val prefs = getPrefs(context)
        val now = currentMonotonicMs()
        val editor = prefs.edit()

        val isTimerActive: Boolean
        val expireElapsed: Long

        if (durationSeconds > 0) {
            isTimerActive = true
            expireElapsed = now + (durationSeconds * 1000L)
            editor.putBoolean(KEY_TIMER_ACTIVE, true)
                .putLong(KEY_TIMER_DURATION_SEC, durationSeconds)
                .putLong(KEY_TIMER_START_ELAPSED, now)
                .putLong(KEY_TIMER_EXPIRE_ELAPSED, expireElapsed)
        } else {
            isTimerActive = false
            expireElapsed = 0L
            editor.putBoolean(KEY_TIMER_ACTIVE, false)
                .putLong(KEY_TIMER_DURATION_SEC, 0L)
                .putLong(KEY_TIMER_START_ELAPSED, 0L)
                .putLong(KEY_TIMER_EXPIRE_ELAPSED, 0L)
        }

        val protectionActive = prefs.getBoolean(KEY_PROTECTION_ACTIVE, false)
        val adminActive = prefs.getBoolean(KEY_DEVICE_ADMIN_ACTIVE, false)
        val sig = computeSignature(protectionActive, isTimerActive, expireElapsed, adminActive)
        editor.putString(KEY_STATE_SIGNATURE, sig)
        editor.apply()

        checkAndNotifyState(context)
        Log.i(TAG, "Strict timer set: $durationSeconds seconds (canUninstall: ${canUninstall(context)})")
    }

    /**
     * Computes remaining strict timer in seconds using monotonic clock.
     * Automatically transitions expired timers to IDLE.
     */
    fun getRemainingTimerSeconds(context: Context): Long {
        val prefs = getPrefs(context)
        if (!prefs.getBoolean(KEY_TIMER_ACTIVE, false)) return 0L

        val expireElapsed = prefs.getLong(KEY_TIMER_EXPIRE_ELAPSED, 0L)
        if (expireElapsed <= 0L) return 0L

        val now = currentMonotonicMs()
        val remainingMs = expireElapsed - now

        if (remainingMs <= 0L) {
            // Timer expired! Automatically clear timer state
            val protectionActive = prefs.getBoolean(KEY_PROTECTION_ACTIVE, false)
            val adminActive = prefs.getBoolean(KEY_DEVICE_ADMIN_ACTIVE, false)
            val sig = computeSignature(protectionActive, false, 0L, adminActive)

            prefs.edit()
                .putBoolean(KEY_TIMER_ACTIVE, false)
                .putLong(KEY_TIMER_EXPIRE_ELAPSED, 0L)
                .putLong(KEY_TIMER_DURATION_SEC, 0L)
                .putString(KEY_STATE_SIGNATURE, sig)
                .apply()

            checkAndNotifyState(context)
            Log.i(TAG, "Strict focus timer expired naturally. Uninstallation lock released.")
            return 0L
        }

        return maxOf(1L, (remainingMs + 999L) / 1000L)
    }

    fun isTimerActive(context: Context): Boolean {
        return getRemainingTimerSeconds(context) > 0L
    }

    fun setDeviceAdminActive(context: Context, active: Boolean) {
        val prefs = getPrefs(context)
        val protectionActive = prefs.getBoolean(KEY_PROTECTION_ACTIVE, false)
        val timerActive = isTimerActive(context)
        val expireElapsed = prefs.getLong(KEY_TIMER_EXPIRE_ELAPSED, 0L)

        val sig = computeSignature(protectionActive, timerActive, expireElapsed, active)
        prefs.edit()
            .putBoolean(KEY_DEVICE_ADMIN_ACTIVE, active)
            .putString(KEY_STATE_SIGNATURE, sig)
            .apply()

        checkAndNotifyState(context)
        Log.i(TAG, "Device Administrator active flag set to: $active")
    }

    fun isDeviceAdminActive(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_DEVICE_ADMIN_ACTIVE, false)
    }

    // --- The Core Uninstallation Authority ---

    /**
     * Determines whether uninstallation of FocusDNS is currently permitted.
     *
     * @return TRUE if both Protection Mode is OFF and no countdown timer is active.
     *         FALSE if Protection Mode is ON or a countdown timer is running.
     */
    fun canUninstall(context: Context): Boolean {
        // If state integrity check fails, fail-safe to locked
        if (!verifyStateIntegrity(context)) {
            Log.w(TAG, "State integrity check failed! Locking uninstallation.")
            return false
        }

        val protectionOn = isProtectionActive(context)
        val timerRunning = isTimerActive(context)

        // User requirement: uninstallation is ALLOWED only if protection is off AND timer completed
        return !protectionOn && !timerRunning
    }

    /**
     * Determines whether deactivation of the Device Administrator is permitted.
     * Follows the exact same rule as uninstallation.
     */
    fun canDeactivateDeviceAdmin(context: Context): Boolean {
        return canUninstall(context)
    }

    /**
     * Returns the current unified SessionState enum.
     */
    fun getSessionState(context: Context): SessionState {
        val protectionOn = isProtectionActive(context)
        val timerRunning = isTimerActive(context)

        return when {
            protectionOn && timerRunning -> SessionState.LOCKED_PROTECTED
            timerRunning -> SessionState.TIMER_ACTIVE
            protectionOn -> SessionState.PROTECTION_ONLY
            else -> SessionState.IDLE
        }
    }

    /**
     * Formats remaining seconds as standard digital clock string (HH:MM:SS or MM:SS).
     */
    fun formatRemainingTime(seconds: Long): String {
        if (seconds <= 0L) return "00:00"
        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        val secs = seconds % 60

        return if (hours > 0) {
            "%02d:%02d:%02d".format(hours, minutes, secs)
        } else {
            "%02d:%02d".format(minutes, secs)
        }
    }

    private fun checkAndNotifyState(context: Context) {
        val state = getSessionState(context)
        val canUninstall = canUninstall(context)
        val remaining = getRemainingTimerSeconds(context)
        notifyListeners(state, canUninstall, remaining)
    }

    /**
     * Exports detailed telemetry dictionary for Flutter UI and diagnostics.
     */
    fun getTelemetry(context: Context): Map<String, Any> {
        val remaining = getRemainingTimerSeconds(context)
        val canUninstallApp = canUninstall(context)
        val state = getSessionState(context)

        return mapOf(
            "sessionState" to state.name,
            "isProtectionActive" to isProtectionActive(context),
            "isTimerActive" to (remaining > 0L),
            "remainingSeconds" to remaining,
            "formattedRemainingTime" to formatRemainingTime(remaining),
            "canUninstall" to canUninstallApp,
            "canDeactivateAdmin" to canDeactivateDeviceAdmin(context),
            "isDeviceAdminActive" to isDeviceAdminActive(context),
            "isIntegrityValid" to verifyStateIntegrity(context)
        )
    }
}
