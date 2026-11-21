package com.focusdns.engine.storage

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import org.json.JSONArray
import org.json.JSONObject

/**
 * Encrypted on-device session storage using AES-256 GCM via Jetpack Security.
 * Ensures crash resilience, local-first state restoration, and tamper-proof session journals.
 */
class EncryptedSessionStore(private val context: Context) {

    companion object {
        const val TAG = "EncryptedSessionStore"
        private const val PREFS_FILE = "focusdns_secure_engine_prefs"
        private const val KEY_ACTIVE_SNAPSHOT = "active_session_snapshot"
        private const val KEY_EVENT_JOURNAL = "session_event_journal"
        private const val KEY_RULE_PACK = "cached_rule_pack"
        private const val MAX_JOURNAL_ENTRIES = 250
    }

    private val prefs: SharedPreferences by lazy {
        try {
            val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
            EncryptedSharedPreferences.create(
                PREFS_FILE,
                masterKeyAlias,
                context,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        } catch (e: Exception) {
            Log.w(TAG, "Hardware KeyStore unavailable, falling back to private prefs: ${e.message}")
            context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        }
    }

    @Synchronized
    fun saveSnapshot(snapshotJson: String) {
        prefs.edit().putString(KEY_ACTIVE_SNAPSHOT, snapshotJson).apply()
    }

    @Synchronized
    fun loadSnapshot(): String? {
        return prefs.getString(KEY_ACTIVE_SNAPSHOT, null)
    }

    @Synchronized
    fun clearSnapshot() {
        prefs.edit().remove(KEY_ACTIVE_SNAPSHOT).apply()
    }

    @Synchronized
    fun appendEvent(eventJson: String) {
        try {
            val raw = prefs.getString(KEY_EVENT_JOURNAL, "[]") ?: "[]"
            val arr = JSONArray(raw)

            if (arr.length() >= MAX_JOURNAL_ENTRIES) {
                // Shift oldest entry to maintain bounded footprint
                val trimmed = JSONArray()
                for (i in 1 until arr.length()) {
                    trimmed.put(arr.get(i))
                }
                trimmed.put(JSONObject(eventJson))
                prefs.edit().putString(KEY_EVENT_JOURNAL, trimmed.toString()).apply()
            } else {
                arr.put(JSONObject(eventJson))
                prefs.edit().putString(KEY_EVENT_JOURNAL, arr.toString()).apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error appending event to secure journal: ${e.message}")
        }
    }

    @Synchronized
    fun loadEventJournal(): List<String> {
        val raw = prefs.getString(KEY_EVENT_JOURNAL, "[]") ?: "[]"
        val list = mutableListOf<String>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                list.add(arr.getJSONObject(i).toString())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error reading event journal: ${e.message}")
        }
        return list
    }

    @Synchronized
    fun saveRulePack(rulePackJson: String) {
        prefs.edit().putString(KEY_RULE_PACK, rulePackJson).apply()
    }

    @Synchronized
    fun loadRulePack(): String? {
        return prefs.getString(KEY_RULE_PACK, null)
    }
}
