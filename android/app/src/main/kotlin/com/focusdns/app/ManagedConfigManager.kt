package com.focusdns.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.RestrictionsManager
import android.os.Bundle
import android.util.Log

/**
 * ManagedConfigManager
 * ====================
 * Android Enterprise Managed Configurations (AppConfig) Reader & Sync Coordinator.
 *
 * Listens for configuration broadcasts pushed dynamically from enterprise EMM consoles
 * (Microsoft Intune, Google Workspace Endpoint, VMware Workspace ONE, MobileIron).
 *
 * Supported Managed Keys:
 * - "server_url": Central FocusDNS API & DoH/DoT upstream URL.
 * - "tenant_id": Enterprise fleet identifier.
 * - "enrollment_token": DPC device enrollment token.
 * - "enforce_strict_uninstall_lock": Overrides local protection settings.
 * - "whitelisted_split_tunnel_pkgs": Array of apps bypassing DNS tunnel.
 * - "lock_task_kiosk_enabled": Forces kiosk containment.
 */
class ManagedConfigManager(private val context: Context) {

    companion object {
        private const val TAG = "ManagedConfigManager"

        const val KEY_SERVER_URL = "server_url"
        const val KEY_TENANT_ID = "tenant_id"
        const val KEY_ENROLLMENT_TOKEN = "enrollment_token"
        const val KEY_ENFORCE_STRICT_UNINSTALL = "enforce_strict_uninstall_lock"
        const val KEY_WHITELISTED_PKGS = "whitelisted_split_tunnel_pkgs"
        const val KEY_KIOSK_ENABLED = "lock_task_kiosk_enabled"
        const val KEY_APPROVED_DOT_HOST = "approved_dot_host"
    }

    data class ManagedConfig(
        val serverUrl: String = "https://dns.focusguard.internal",
        val tenantId: String = "default_enterprise",
        val enrollmentToken: String = "",
        val enforceStrictUninstallLock: Boolean = false,
        val whitelistedPackages: List<String> = emptyList(),
        val kioskEnabled: Boolean = false,
        val approvedDotHost: String = ""
    ) {
        fun toMap(): Map<String, Any> {
            return mapOf(
                "serverUrl" to serverUrl,
                "tenantId" to tenantId,
                "enrollmentToken" to enrollmentToken,
                "enforceStrictUninstallLock" to enforceStrictUninstallLock,
                "whitelistedPackages" to whitelistedPackages,
                "kioskEnabled" to kioskEnabled,
                "approvedDotHost" to approvedDotHost
            )
        }
    }

    interface ConfigChangeListener {
        fun onConfigurationChanged(config: ManagedConfig)
    }

    private val listeners = mutableListOf<ConfigChangeListener>()
    private var cachedConfig: ManagedConfig = ManagedConfig()
    private var isReceiverRegistered = false

    private val restrictionsReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (Intent.ACTION_APPLICATION_RESTRICTIONS_CHANGED == intent?.action) {
                Log.i(TAG, "Application restrictions changed broadcast received.")
                reloadConfiguration()
            }
        }
    }

    init {
        reloadConfiguration()
    }

    /**
     * Registers broadcast receiver for dynamic Managed Config changes.
     */
    fun startMonitoring() {
        if (!isReceiverRegistered) {
            val filter = IntentFilter(Intent.ACTION_APPLICATION_RESTRICTIONS_CHANGED)
            context.registerReceiver(restrictionsReceiver, filter)
            isReceiverRegistered = true
        }
    }

    /**
     * Unregisters broadcast receiver.
     */
    fun stopMonitoring() {
        if (isReceiverRegistered) {
            try {
                context.unregisterReceiver(restrictionsReceiver)
            } catch (e: Exception) {
                Log.w(TAG, "Error unregistering restrictions receiver: ${e.message}")
            }
            isReceiverRegistered = false
        }
    }

    /**
     * Reads restrictions bundle from system RestrictionsManager.
     */
    fun reloadConfiguration(): ManagedConfig {
        val rm = context.getSystemService(Context.RESTRICTIONS_SERVICE) as? RestrictionsManager
        val bundle: Bundle? = rm?.applicationRestrictions

        cachedConfig = if (bundle != null && !bundle.isEmpty) {
            val sUrl = bundle.getString(KEY_SERVER_URL, "https://dns.focusguard.internal") ?: "https://dns.focusguard.internal"
            val tId = bundle.getString(KEY_TENANT_ID, "default_enterprise") ?: "default_enterprise"
            val token = bundle.getString(KEY_ENROLLMENT_TOKEN, "") ?: ""
            val strict = bundle.getBoolean(KEY_ENFORCE_STRICT_UNINSTALL, false)
            val pkgs = bundle.getStringArray(KEY_WHITELISTED_PKGS)?.toList() ?: emptyList()
            val kiosk = bundle.getBoolean(KEY_KIOSK_ENABLED, false)
            val dot = bundle.getString(KEY_APPROVED_DOT_HOST, "") ?: ""

            ManagedConfig(
                serverUrl = sUrl,
                tenantId = tId,
                enrollmentToken = token,
                enforceStrictUninstallLock = strict,
                whitelistedPackages = pkgs,
                kioskEnabled = kiosk,
                approvedDotHost = dot
            )
        } else {
            ManagedConfig()
        }

        notifyListeners(cachedConfig)
        return cachedConfig
    }

    fun getConfiguration(): ManagedConfig = cachedConfig

    fun registerListener(listener: ConfigChangeListener) {
        if (!listeners.contains(listener)) {
            listeners.add(listener)
            listener.onConfigurationChanged(cachedConfig)
        }
    }

    fun unregisterListener(listener: ConfigChangeListener) {
        listeners.remove(listener)
    }

    private fun notifyListeners(config: ManagedConfig) {
        for (l in listeners) {
            try {
                l.onConfigurationChanged(config)
            } catch (e: Exception) {
                Log.e(TAG, "Listener error: ${e.message}")
            }
        }
    }
}
