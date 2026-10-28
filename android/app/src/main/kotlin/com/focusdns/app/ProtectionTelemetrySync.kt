package com.focusdns.app

import android.content.Context
import android.os.Build
import android.util.Log
import org.json.JSONObject

/**
 * ProtectionTelemetrySync
 * =======================
 * Aggregates complete Android device security, MDM posture, and uninstallation lock
 * metrics into a unified payload for the local Flutter UI and FocusDNS cloud backends.
 */
object ProtectionTelemetrySync {

    private const val TAG = "ProtectionTelemetry"

    fun getFullDeviceReport(context: Context): Map<String, Any> {
        val lockStatus = ProtectionStateCoordinator.getTelemetry(context)
        val mdmStatus = MdmPolicyEngine.getMdmCapabilities(context)
        val splitTunnel = SplitTunnelManager.getTelemetry(context)
        val antiTamper = AntiTamperSecurityShield.getTelemetry(context)
        val quarantine = AppQuarantineManager.getTelemetry(context)
        val restrictions = DevicePolicyProfileManager.getRestrictionsReport(context)

        return mapOf(
            "timestamp" to System.currentTimeMillis(),
            "os" to "Android",
            "androidRelease" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "lockStatus" to lockStatus,
            "mdmStatus" to mdmStatus,
            "splitTunnel" to splitTunnel,
            "antiTamper" to antiTamper,
            "quarantine" to quarantine,
            "userRestrictions" to restrictions
        )
    }

    fun getFullDeviceReportJson(context: Context): String {
        return try {
            val report = getFullDeviceReport(context)
            JSONObject(report).toString(2)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to serialize report: ${e.message}")
            "{}"
        }
    }
}
