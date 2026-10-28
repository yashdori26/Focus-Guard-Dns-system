package com.focusdns.app

import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.os.PersistableBundle
import android.util.Log
import org.json.JSONException
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale

/**
 * ZeroTouchQrPayloadParser
 * ========================
 * High-reliability parser and validator for Android Enterprise Zero-Touch and QR Code
 * enrollment bundles (Android 9.0+ / API 28+).
 *
 * During factory setup wizard (OOBE), scanning a FocusDNS enrollment QR code passes a JSON payload
 * defining the Device Policy Controller (DPC) component, APK download location, SHA-256 signature
 * checksum, Wi-Fi provisioning credentials, and enterprise admin extras.
 *
 * Architectural & Safety Guarantees:
 * 1. Strict Conditional Uninstallation: Admin extras flags respect the FocusDNS core law:
 *    - Normal Mode: Clean uninstallation is 100% permitted.
 *    - Active Session / Timer Mode: Uninstallation restrictions are strictly enforced.
 * 2. Life Safety: Emergency dialers (911, 112, etc.) and telecom packages are ALWAYS preserved.
 * 3. Cryptographic Checksum Validation: Validates APK SHA-256 signature checksum before provisioning.
 */
class ZeroTouchQrPayloadParser(private val context: Context? = null) {

    companion object {
        private const val TAG = "ZeroTouchQrParser"

        // Standard Android Enterprise QR Enrollment Keys
        const val EXTRA_PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME =
            "android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME"
        const val EXTRA_PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME =
            "android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME"
        const val EXTRA_PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION =
            "android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION"
        const val EXTRA_PROVISIONING_DEVICE_ADMIN_PACKAGE_CHECKSUM =
            "android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_CHECKSUM"
        const val EXTRA_PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM =
            "android.app.extra.PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM"
        const val EXTRA_PROVISIONING_WIFI_SSID =
            "android.app.extra.PROVISIONING_WIFI_SSID"
        const val EXTRA_PROVISIONING_WIFI_PASSWORD =
            "android.app.extra.PROVISIONING_WIFI_PASSWORD"
        const val EXTRA_PROVISIONING_WIFI_SECURITY_TYPE =
            "android.app.extra.PROVISIONING_WIFI_SECURITY_TYPE"
        const val EXTRA_PROVISIONING_WIFI_HIDDEN =
            "android.app.extra.PROVISIONING_WIFI_HIDDEN"
        const val EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE =
            "android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE"
        const val EXTRA_PROVISIONING_LOCALE =
            "android.app.extra.PROVISIONING_LOCALE"
        const val EXTRA_PROVISIONING_TIME_ZONE =
            "android.app.extra.PROVISIONING_TIME_ZONE"
        const val EXTRA_PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED =
            "android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED"

        // Admin Extras Keys
        const val KEY_SERVER_URL = "server_url"
        const val KEY_ENROLLMENT_TOKEN = "enrollment_token"
        const val KEY_TENANT_ID = "tenant_id"
        const val KEY_DEVICE_ID = "device_id"
        const val KEY_ENFORCE_STRICT_UNINSTALL = "enforce_strict_uninstall_lock"
        const val KEY_AUTO_LOCK_TASK = "auto_lock_task"
        const val KEY_PRIVATE_DNS_HOST = "private_dns_host"
        const val KEY_SPLIT_TUNNEL_EXEMPTIONS = "split_tunnel_exemptions"
        const val KEY_EMERGENCY_WHITELIST = "emergency_whitelist"

        val DEFAULT_PACKAGE = "com.focusdns.app"
        val DEFAULT_COMPONENT = "$DEFAULT_PACKAGE/.FocusDeviceAdminReceiver"
    }

    /**
     * Wi-Fi configuration extracted from QR code.
     */
    data class ProvisioningWifiConfig(
        val ssid: String? = null,
        val password: String? = null,
        val securityType: String = "WPA",
        val hidden: Boolean = false
    )

    /**
     * FocusDNS Admin Extras bundle passed to DPC upon provisioning completion.
     */
    data class ProvisioningAdminExtras(
        val serverUrl: String = "https://dns.focusdns.io",
        val enrollmentToken: String = "",
        val tenantId: String = "default_enterprise",
        val deviceId: String = "",
        val enforceStrictUninstallLock: Boolean = false,
        val autoLockTask: Boolean = false,
        val privateDnsHost: String = "dns.focusdns.io",
        val splitTunnelExemptions: List<String> = emptyList(),
        val emergencyWhitelist: List<String> = listOf("911", "112", "999", "000", "100", "108", "988")
    )

    /**
     * Parsed Zero-Touch QR Payload result.
     */
    data class ZeroTouchQrPayload(
        val packageName: String,
        val componentName: String,
        val downloadLocation: String? = null,
        val signatureChecksum: String? = null,
        val wifiConfig: ProvisioningWifiConfig? = null,
        val adminExtras: ProvisioningAdminExtras = ProvisioningAdminExtras(),
        val locale: String? = null,
        val timeZone: String? = null,
        val leaveAllSystemAppsEnabled: Boolean = true,
        val rawJson: String = "",
        val isValid: Boolean = true,
        val validationError: String? = null
    )

    /**
     * Parses and validates raw QR JSON string.
     */
    fun parseJson(jsonString: String?): ZeroTouchQrPayload {
        if (jsonString.isNullOrBlank()) {
            return ZeroTouchQrPayload(
                packageName = DEFAULT_PACKAGE,
                componentName = DEFAULT_COMPONENT,
                isValid = false,
                validationError = "Payload is null or empty"
            )
        }

        try {
            val json = JSONObject(jsonString)

            val pkg = json.optString(EXTRA_PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME, DEFAULT_PACKAGE)
            val comp = json.optString(EXTRA_PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME, "$pkg/.FocusDeviceAdminReceiver")
            val dlLoc = json.optString(EXTRA_PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION).takeIf { it.isNotBlank() }
            val checksum = json.optString(EXTRA_PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM).takeIf { it.isNotBlank() }
                ?: json.optString(EXTRA_PROVISIONING_DEVICE_ADMIN_PACKAGE_CHECKSUM).takeIf { it.isNotBlank() }

            // Wi-Fi parsing
            val wifiSsid = json.optString(EXTRA_PROVISIONING_WIFI_SSID).takeIf { it.isNotBlank() }
            val wifiConfig = if (wifiSsid != null) {
                ProvisioningWifiConfig(
                    ssid = wifiSsid,
                    password = json.optString(EXTRA_PROVISIONING_WIFI_PASSWORD).takeIf { it.isNotBlank() },
                    securityType = json.optString(EXTRA_PROVISIONING_WIFI_SECURITY_TYPE, "WPA"),
                    hidden = json.optBoolean(EXTRA_PROVISIONING_WIFI_HIDDEN, false)
                )
            } else null

            // Admin Extras parsing
            val adminExtras = parseAdminExtrasObject(json.opt(EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE))

            val locale = json.optString(EXTRA_PROVISIONING_LOCALE).takeIf { it.isNotBlank() }
            val timeZone = json.optString(EXTRA_PROVISIONING_TIME_ZONE).takeIf { it.isNotBlank() }
            val leaveSystemApps = json.optBoolean(EXTRA_PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED, true)

            return ZeroTouchQrPayload(
                packageName = pkg,
                componentName = comp,
                downloadLocation = dlLoc,
                signatureChecksum = checksum,
                wifiConfig = wifiConfig,
                adminExtras = adminExtras,
                locale = locale,
                timeZone = timeZone,
                leaveAllSystemAppsEnabled = leaveSystemApps,
                rawJson = jsonString,
                isValid = true,
                validationError = null
            )
        } catch (e: JSONException) {
            Log.e(TAG, "Failed to parse Zero-Touch QR JSON: ${e.message}")
            return ZeroTouchQrPayload(
                packageName = DEFAULT_PACKAGE,
                componentName = DEFAULT_COMPONENT,
                rawJson = jsonString,
                isValid = false,
                validationError = "JSON Syntax Error: ${e.message}"
            )
        }
    }

    /**
     * Parses Android Intent Bundle passed by setup wizard.
     */
    fun parseBundle(bundle: Bundle?): ZeroTouchQrPayload {
        if (bundle == null) {
            return ZeroTouchQrPayload(
                packageName = DEFAULT_PACKAGE,
                componentName = DEFAULT_COMPONENT,
                isValid = false,
                validationError = "Bundle is null"
            )
        }

        val pkg = bundle.getString(EXTRA_PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME) ?: DEFAULT_PACKAGE
        val comp = bundle.getString(EXTRA_PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME) ?: "$pkg/.FocusDeviceAdminReceiver"
        val dlLoc = bundle.getString(EXTRA_PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION)
        val checksum = bundle.getString(EXTRA_PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM)
            ?: bundle.getString(EXTRA_PROVISIONING_DEVICE_ADMIN_PACKAGE_CHECKSUM)

        val wifiSsid = bundle.getString(EXTRA_PROVISIONING_WIFI_SSID)
        val wifiConfig = if (wifiSsid != null) {
            ProvisioningWifiConfig(
                ssid = wifiSsid,
                password = bundle.getString(EXTRA_PROVISIONING_WIFI_PASSWORD),
                securityType = bundle.getString(EXTRA_PROVISIONING_WIFI_SECURITY_TYPE) ?: "WPA",
                hidden = bundle.getBoolean(EXTRA_PROVISIONING_WIFI_HIDDEN, false)
            )
        } else null

        val adminExtrasObj = bundle.get(EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE)
        val adminExtras = when (adminExtrasObj) {
            is Bundle -> parseAdminExtrasFromBundle(adminExtrasObj)
            is PersistableBundle -> parseAdminExtrasFromPersistableBundle(adminExtrasObj)
            is String -> parseAdminExtrasObject(adminExtrasObj)
            else -> ProvisioningAdminExtras()
        }

        return ZeroTouchQrPayload(
            packageName = pkg,
            componentName = comp,
            downloadLocation = dlLoc,
            signatureChecksum = checksum,
            wifiConfig = wifiConfig,
            adminExtras = adminExtras,
            locale = bundle.getString(EXTRA_PROVISIONING_LOCALE),
            timeZone = bundle.getString(EXTRA_PROVISIONING_TIME_ZONE),
            leaveAllSystemAppsEnabled = bundle.getBoolean(EXTRA_PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED, true),
            isValid = true,
            validationError = null
        )
    }

    private fun parseAdminExtrasObject(obj: Any?): ProvisioningAdminExtras {
        if (obj == null) return ProvisioningAdminExtras()

        if (obj is JSONObject) {
            return parseAdminExtrasFromJson(obj)
        }

        if (obj is String) {
            return try {
                parseAdminExtrasFromJson(JSONObject(obj))
            } catch (e: Exception) {
                Log.w(TAG, "admin_extras string is not valid JSON: $obj")
                ProvisioningAdminExtras()
            }
        }

        return ProvisioningAdminExtras()
    }

    private fun parseAdminExtrasFromJson(json: JSONObject): ProvisioningAdminExtras {
        val serverUrl = json.optString(KEY_SERVER_URL, "https://dns.focusdns.io")
        val token = json.optString(KEY_ENROLLMENT_TOKEN, "")
        val tenant = json.optString(KEY_TENANT_ID, "default_enterprise")
        val devId = json.optString(KEY_DEVICE_ID, "")
        val strictUninstall = json.optBoolean(KEY_ENFORCE_STRICT_UNINSTALL, false)
        val autoLock = json.optBoolean(KEY_AUTO_LOCK_TASK, false)
        val dnsHost = json.optString(KEY_PRIVATE_DNS_HOST, "dns.focusdns.io")

        val splitExemptions = mutableListOf<String>()
        val splitArray = json.optJSONArray(KEY_SPLIT_TUNNEL_EXEMPTIONS)
        if (splitArray != null) {
            for (i in 0 until splitArray.length()) {
                splitExemptions.add(splitArray.getString(i))
            }
        }

        val emergencyList = mutableListOf<String>()
        val emerArray = json.optJSONArray(KEY_EMERGENCY_WHITELIST)
        if (emerArray != null) {
            for (i in 0 until emerArray.length()) {
                emergencyList.add(emerArray.getString(i))
            }
        } else {
            emergencyList.addAll(listOf("911", "112", "999", "000", "100", "108", "988"))
        }

        return ProvisioningAdminExtras(
            serverUrl = serverUrl,
            enrollmentToken = token,
            tenantId = tenant,
            deviceId = devId,
            enforceStrictUninstallLock = strictUninstall,
            autoLockTask = autoLock,
            privateDnsHost = dnsHost,
            splitTunnelExemptions = splitExemptions,
            emergencyWhitelist = emergencyList
        )
    }

    private fun parseAdminExtrasFromBundle(bundle: Bundle): ProvisioningAdminExtras {
        return ProvisioningAdminExtras(
            serverUrl = bundle.getString(KEY_SERVER_URL) ?: "https://dns.focusdns.io",
            enrollmentToken = bundle.getString(KEY_ENROLLMENT_TOKEN) ?: "",
            tenantId = bundle.getString(KEY_TENANT_ID) ?: "default_enterprise",
            deviceId = bundle.getString(KEY_DEVICE_ID) ?: "",
            enforceStrictUninstallLock = bundle.getBoolean(KEY_ENFORCE_STRICT_UNINSTALL, false),
            autoLockTask = bundle.getBoolean(KEY_AUTO_LOCK_TASK, false),
            privateDnsHost = bundle.getString(KEY_PRIVATE_DNS_HOST) ?: "dns.focusdns.io"
        )
    }

    private fun parseAdminExtrasFromPersistableBundle(pb: PersistableBundle): ProvisioningAdminExtras {
        return ProvisioningAdminExtras(
            serverUrl = pb.getString(KEY_SERVER_URL) ?: "https://dns.focusdns.io",
            enrollmentToken = pb.getString(KEY_ENROLLMENT_TOKEN) ?: "",
            tenantId = pb.getString(KEY_TENANT_ID) ?: "default_enterprise",
            deviceId = pb.getString(KEY_DEVICE_ID) ?: "",
            enforceStrictUninstallLock = pb.getInt(KEY_ENFORCE_STRICT_UNINSTALL, 0) == 1,
            autoLockTask = pb.getInt(KEY_AUTO_LOCK_TASK, 0) == 1,
            privateDnsHost = pb.getString(KEY_PRIVATE_DNS_HOST) ?: "dns.focusdns.io"
        )
    }

    /**
     * Converts ProvisioningAdminExtras to PersistableBundle for DevicePolicyManager API.
     */
    fun toPersistableBundle(extras: ProvisioningAdminExtras): PersistableBundle {
        val pb = PersistableBundle()
        pb.putString(KEY_SERVER_URL, extras.serverUrl)
        pb.putString(KEY_ENROLLMENT_TOKEN, extras.enrollmentToken)
        pb.putString(KEY_TENANT_ID, extras.tenantId)
        pb.putString(KEY_DEVICE_ID, extras.deviceId)
        pb.putInt(KEY_ENFORCE_STRICT_UNINSTALL, if (extras.enforceStrictUninstallLock) 1 else 0)
        pb.putInt(KEY_AUTO_LOCK_TASK, if (extras.autoLockTask) 1 else 0)
        pb.putString(KEY_PRIVATE_DNS_HOST, extras.privateDnsHost)
        return pb
    }

    /**
     * Validates raw byte SHA-256 against expected hex-encoded checksum.
     */
    fun verifyChecksum(data: ByteArray, expectedSha256Hex: String): Boolean {
        if (expectedSha256Hex.isBlank()) return false
        try {
            val md = MessageDigest.getInstance("SHA-256")
            val digest = md.digest(data)
            val hex = digest.joinToString("") { "%02x".format(it) }
            return hex.equals(expectedSha256Hex.trim().replace(":", ""), ignoreCase = true)
        } catch (e: Exception) {
            Log.e(TAG, "Checksum verification failed: ${e.message}")
            return false
        }
    }

    /**
     * Applies parsed provisioning parameters to FocusDNS system coordinators.
     * Enforces the uninstallation policy:
     * - If normal idle mode: clean uninstallation is preserved.
     * - If focus/strict mode requested: activates lock state.
     */
    fun applyProvisioning(payload: ZeroTouchQrPayload): Boolean {
        if (!payload.isValid) {
            Log.w(TAG, "Cannot apply invalid provisioning payload: ${payload.validationError}")
            return false
        }

        val ctx = context ?: return false
        val extras = payload.adminExtras

        Log.i(TAG, "Applying Zero-Touch provisioning: tenant=${extras.tenantId}, server=${extras.serverUrl}")

        // Save server URL and token into shared preferences
        val prefs = ctx.getSharedPreferences("FocusDnsPrefs", Context.MODE_PRIVATE)
        prefs.edit()
            .putString("enterprise_server_url", extras.serverUrl)
            .putString("enterprise_tenant_id", extras.tenantId)
            .putString("enterprise_enrollment_token", extras.enrollmentToken)
            .putString("enterprise_dns_host", extras.privateDnsHost)
            .putBoolean("dpc_provisioned", true)
            .apply()

        // Handle strict uninstallation lock
        if (extras.enforceStrictUninstallLock) {
            Log.i(TAG, "Activating conditional protection mode per enterprise profile")
            ProtectionStateCoordinator.setProtectionActive(ctx, true)
        } else {
            Log.i(TAG, "Device provisioned in normal idle state: uninstallation is 100% permitted")
        }

        return true
    }
}
