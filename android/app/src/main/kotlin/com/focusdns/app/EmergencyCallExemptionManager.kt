package com.focusdns.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.telephony.PhoneNumberUtils
import android.util.Log

/**
 * EmergencyCallExemptionManager
 * =============================
 * Inviolable emergency call exemption registry for FocusDNS.
 *
 * LAW OF LIFE SAFETY:
 * Under NO circumstances shall FocusDNS block, delay, intercept, or hinder
 * calls to emergency services (e.g. 911, 112, 999, 000, 100, 108, 988),
 * nor shall it lock out native emergency dialer packages.
 *
 * This manager has the highest priority in the entire application architecture,
 * superseding Strict Mode, App Quarantine, Kiosk Locks, and Accessibility filters.
 */
object EmergencyCallExemptionManager {

    private const val TAG = "EmergencyCallExemption"

    /**
     * Standard international emergency numbers.
     */
    val EMERGENCY_NUMBERS = setOf(
        "911", // United States, Canada, Mexico
        "112", // European Union, India, standard GSM emergency number
        "999", // United Kingdom, Ireland, Hong Kong, Singapore, Malaysia
        "000", // Australia
        "111", // New Zealand
        "100", // India (Police)
        "101", // India (Fire)
        "102", // India (Ambulance)
        "108", // India (Disaster Management / Emergency Ambulance)
        "988", // Suicide & Crisis Lifeline (US / Canada)
        "110", // Japan, China (Police)
        "119", // Japan, South Korea, China (Fire / Ambulance)
        "120", // China (Ambulance)
        "122", // China (Traffic Police)
        "190", // Brazil (Police)
        "192", // Brazil (Ambulance)
        "193"  // Brazil (Fire)
    )

    /**
     * Known telecom, system phone, and in-call UI packages that must NEVER be quarantined or blocked.
     */
    val EMERGENCY_SYSTEM_PACKAGES = setOf(
        "com.android.phone",
        "com.android.server.telecom",
        "com.google.android.dialer",
        "com.samsung.android.incallui",
        "com.samsung.android.dialer",
        "com.android.incallui",
        "com.android.emergency",
        "com.google.android.apps.safetyhub",
        "com.sec.android.app.popupcalculator", // Some devices map SOS shortcut
        "com.miui.home", // Keep launcher stable for emergency shortcuts
        "com.sec.android.app.launcher"
    )

    /**
     * Determines whether a dialed string or intent data URI is an emergency call.
     */
    fun isEmergencyNumber(number: String?): Boolean {
        if (number.isNullOrBlank()) return false
        val cleanNumber = number.replace(Regex("[^0-9]"), "")

        // 1. Direct match with global emergency database
        if (EMERGENCY_NUMBERS.contains(cleanNumber)) {
            return true
        }

        // 2. Android PhoneNumberUtils system check
        return try {
            PhoneNumberUtils.isEmergencyNumber(cleanNumber)
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Evaluates whether an Intent is initiating or receiving an emergency call.
     */
    fun isEmergencyIntent(intent: Intent?): Boolean {
        if (intent == null) return false
        val action = intent.action ?: ""

        if (action == "android.intent.action.CALL_EMERGENCY" ||
            action == "android.intent.action.CALL_PRIVILEGED" ||
            action == "android.intent.action.EMERGENCY_ASSISTANCE") {
            return true
        }

        val data = intent.data
        if (data != null && data.scheme == "tel") {
            val schemeSpecific = data.schemeSpecificPart
            if (isEmergencyNumber(schemeSpecific)) {
                return true
            }
        }

        val extras = intent.extras
        if (extras != null) {
            for (key in extras.keySet()) {
                val value = extras.get(key)?.toString()
                if (isEmergencyNumber(value)) {
                    return true
                }
            }
        }

        return false
    }

    /**
     * Evaluates whether a package name belongs to a protected emergency dialer or telecom service.
     */
    fun isEmergencyPackage(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        if (EMERGENCY_SYSTEM_PACKAGES.contains(packageName)) return true
        val lower = packageName.lowercase()
        return lower.contains("emergency") ||
            lower.contains("telecom") ||
            lower.contains("incallui") ||
            lower.contains("safetyhub")
    }

    /**
     * Launches the native emergency dialer activity with 112 pre-filled, bypassing all locks.
     */
    fun launchEmergencyDialer(context: Context, emergencyNumber: String = "112") {
        try {
            val intent = Intent(Intent.ACTION_DIAL).apply {
                data = Uri.parse("tel:$emergencyNumber")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            context.startActivity(intent)
            Log.i(TAG, "Emergency dialer launched successfully for number: $emergencyNumber")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch emergency dialer: ${e.message}")
        }
    }
}
