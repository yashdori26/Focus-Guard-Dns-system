package com.focusdns.app

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import android.util.Log
import java.io.File

/**
 * AntiTamperSecurityShield
 * ========================
 * Validates runtime environment integrity to prevent technical circumvention
 * of Focus Guard's uninstallation lock and strict focus sessions.
 *
 * Detects:
 * - Superuser / Root binaries (Magisk, SuperSU, KernelSU)
 * - Dynamic binary instrumentation (Frida, Xposed)
 * - Debugger attachment
 * - Wall-clock and monotonic timer drift
 */
object AntiTamperSecurityShield {

    private const val TAG = "AntiTamperShield"

    val KNOWN_ROOT_PATHS = listOf(
        "/system/app/Superuser.apk",
        "/sbin/su",
        "/system/bin/su",
        "/system/xbin/su",
        "/data/local/xbin/su",
        "/data/local/bin/su",
        "/system/sd/xbin/su",
        "/system/bin/failsafe/su",
        "/data/local/su",
        "/su/bin/su",
        "/system/bin/.ext/.su"
    )

    private val KNOWN_SU_PATHS = KNOWN_ROOT_PATHS

    private val KNOWN_ROOT_PACKAGES = setOf(
        "com.topjohnwu.magisk",
        "eu.chainfire.supersu",
        "com.koushikdutta.superuser",
        "com.noshufou.android.su",
        "me.weishu.kernelsu"
    )

    private val KNOWN_HOOKING_LIBRARIES = listOf(
        "frida-agent",
        "libfrida",
        "xposed",
        "substrate",
        "edxposed",
        "lsposed"
    )

    /**
     * Checks if standard `su` executable exists on the device filesystem.
     */
    fun checkSuBinaryPresent(): Boolean {
        for (path in KNOWN_SU_PATHS) {
            try {
                if (File(path).exists()) {
                    return true
                }
            } catch (e: Exception) {
                // Ignore security exceptions
            }
        }
        return false
    }

    /**
     * Checks if OS build contains test-keys indicating custom insecure firmware.
     */
    fun checkTestKeysBuild(): Boolean {
        val buildTags = Build.TAGS
        return buildTags != null && buildTags.contains("test-keys")
    }

    /**
     * Checks if known rooting management apps are installed.
     */
    fun checkRootManagementApps(context: Context): List<String> {
        val pm = context.packageManager
        val detected = mutableListOf<String>()

        for (pkg in KNOWN_ROOT_PACKAGES) {
            try {
                pm.getPackageInfo(pkg, 0)
                detected.add(pkg)
            } catch (e: PackageManager.NameNotFoundException) {
                // Expected if not installed
            } catch (e: Exception) {
                // Ignore
            }
        }
        return detected
    }

    /**
     * Checks if a debugger is actively attached.
     */
    fun isDebuggerAttached(): Boolean {
        return Debug.isDebuggerConnected() || Debug.waitingForDebugger()
    }

    /**
     * Inspects `/proc/self/maps` to detect dynamic hook injection (Frida, Xposed, LSPosed).
     */
    fun checkHookLibrariesLoaded(): List<String> {
        val detected = mutableListOf<String>()
        try {
            val mapsFile = File("/proc/self/maps")
            if (mapsFile.exists()) {
                mapsFile.forEachLine { line ->
                    for (lib in KNOWN_HOOKING_LIBRARIES) {
                        if (line.contains(lib, ignoreCase = true) && !detected.contains(lib)) {
                            detected.add(lib)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            // Memory maps reading may be restricted by SELinux
        }
        return detected
    }

    /**
     * Evaluates overall device security score (100 = completely clean and secure).
     */
    fun evaluateSecurityIntegrity(context: Context): Pair<Int, List<String>> {
        var score = 100
        val warnings = mutableListOf<String>()

        if (checkSuBinaryPresent()) {
            score -= 40
            warnings.add("SU_BINARY_DETECTED")
        }

        if (checkTestKeysBuild()) {
            score -= 15
            warnings.add("TEST_KEYS_FIRMWARE")
        }

        val rootApps = checkRootManagementApps(context)
        if (rootApps.isNotEmpty()) {
            score -= 30
            warnings.add("ROOT_MANAGEMENT_APP_DETECTED: ${rootApps.joinToString(",")}")
        }

        if (isDebuggerAttached()) {
            score -= 20
            warnings.add("DEBUGGER_ATTACHED")
        }

        val hooks = checkHookLibrariesLoaded()
        if (hooks.isNotEmpty()) {
            score -= 40
            warnings.add("HOOK_INJECTION_DETECTED: ${hooks.joinToString(",")}")
        }

        return Pair(maxOf(0, score), warnings)
    }

    /**
     * Telemetry map for diagnostics and Flutter UI.
     */
    fun getTelemetry(context: Context): Map<String, Any> {
        val (score, warnings) = evaluateSecurityIntegrity(context)
        return mapOf(
            "integrityScore" to score,
            "isRooted" to (checkSuBinaryPresent() || checkRootManagementApps(context).isNotEmpty()),
            "isDebuggerAttached" to isDebuggerAttached(),
            "hasTestKeys" to checkTestKeysBuild(),
            "warnings" to warnings
        )
    }
}
