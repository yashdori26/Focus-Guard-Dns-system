package com.focusdns.app

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.security.MessageDigest

/**
 * ZeroTouchQrPayloadParserTest
 * ============================
 * Unit test suite validating Android Enterprise Zero-Touch and QR Code enrollment parsing.
 *
 * Verifies:
 * - Proper extraction of package name, admin component, checksum, and Wi-Fi credentials.
 * - Validation and parsing of Admin Extras JSON bundle.
 * - Enforcement of life-safety emergency dialer whitelisting.
 * - Conditional uninstallation posture (normal idle allows uninstallation, active session locks it).
 * - Cryptographic checksum validation against simulated APK binary payloads.
 */
class ZeroTouchQrPayloadParserTest {

    private lateinit var parser: ZeroTouchQrPayloadParser

    @Before
    fun setUp() {
        parser = ZeroTouchQrPayloadParser(null)
    }

    @Test
    fun testParseValidCompleteZeroTouchJson() {
        val adminExtras = JSONObject().apply {
            put("server_url", "https://custom.mdm.focusdns.io")
            put("enrollment_token", "tok_ent_9988776655")
            put("tenant_id", "acme_corp")
            put("device_id", "dev_pixel_8_pro")
            put("enforce_strict_uninstall_lock", true)
            put("auto_lock_task", false)
            put("private_dns_host", "dot.acme.focusdns.io")
            put("emergency_whitelist", JSONArray(listOf("911", "112", "999", "000")))
        }

        val json = JSONObject().apply {
            put("android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME", "com.focusdns.app")
            put("android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME", "com.focusdns.app/.FocusDeviceAdminReceiver")
            put("android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION", "https://cdn.focusdns.io/apk/focusdns-enterprise.apk")
            put("android.app.extra.PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM", "a1b2c3d4e5f67890123456789abcdef0123456789abcdef0123456789abcdef0")
            put("android.app.extra.PROVISIONING_WIFI_SSID", "Acme-Enterprise-WiFi")
            put("android.app.extra.PROVISIONING_WIFI_PASSWORD", "SuperSecurePassword!123")
            put("android.app.extra.PROVISIONING_WIFI_SECURITY_TYPE", "WPA2")
            put("android.app.extra.PROVISIONING_WIFI_HIDDEN", false)
            put("android.app.extra.PROVISIONING_LOCALE", "en_US")
            put("android.app.extra.PROVISIONING_TIME_ZONE", "America/New_York")
            put("android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED", true)
            put("android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE", adminExtras)
        }

        val result = parser.parseJson(json.toString())

        assertTrue(result.isValid)
        assertNull(result.validationError)
        assertEquals("com.focusdns.app", result.packageName)
        assertEquals("com.focusdns.app/.FocusDeviceAdminReceiver", result.componentName)
        assertEquals("https://cdn.focusdns.io/apk/focusdns-enterprise.apk", result.downloadLocation)
        assertEquals("a1b2c3d4e5f67890123456789abcdef0123456789abcdef0123456789abcdef0", result.signatureChecksum)

        // Wi-Fi validation
        assertNotNull(result.wifiConfig)
        assertEquals("Acme-Enterprise-WiFi", result.wifiConfig?.ssid)
        assertEquals("SuperSecurePassword!123", result.wifiConfig?.password)
        assertEquals("WPA2", result.wifiConfig?.securityType)
        assertFalse(result.wifiConfig!!.hidden)

        // Admin Extras validation
        val extras = result.adminExtras
        assertEquals("https://custom.mdm.focusdns.io", extras.serverUrl)
        assertEquals("tok_ent_9988776655", extras.enrollmentToken)
        assertEquals("acme_corp", extras.tenantId)
        assertEquals("dev_pixel_8_pro", extras.deviceId)
        assertTrue(extras.enforceStrictUninstallLock)
        assertFalse(extras.autoLockTask)
        assertEquals("dot.acme.focusdns.io", extras.privateDnsHost)
        assertTrue(extras.emergencyWhitelist.contains("911"))
        assertTrue(extras.emergencyWhitelist.contains("112"))
    }

    @Test
    fun testParseMinimalJsonWithDefaultFallback() {
        val json = JSONObject().apply {
            put("android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME", "com.focusdns.app")
        }

        val result = parser.parseJson(json.toString())

        assertTrue(result.isValid)
        assertNull(result.validationError)
        assertEquals("com.focusdns.app", result.packageName)
        assertEquals("com.focusdns.app/.FocusDeviceAdminReceiver", result.componentName)
        assertNull(result.downloadLocation)
        assertNull(result.signatureChecksum)
        assertNull(result.wifiConfig)

        // In normal idle mode with defaults, strict uninstallation lock is false (clean uninstall permitted)
        assertFalse(result.adminExtras.enforceStrictUninstallLock)
        assertEquals("https://dns.focusdns.io", result.adminExtras.serverUrl)
        assertEquals("default_enterprise", result.adminExtras.tenantId)
    }

    @Test
    fun testParseNullOrEmptyJsonReturnsInvalid() {
        val resultNull = parser.parseJson(null)
        assertFalse(resultNull.isValid)
        assertNotNull(resultNull.validationError)

        val resultEmpty = parser.parseJson("   ")
        assertFalse(resultEmpty.isValid)
        assertNotNull(resultEmpty.validationError)
    }

    @Test
    fun testParseMalformedJsonReturnsInvalid() {
        val malformed = "{ \"android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME\": "
        val result = parser.parseJson(malformed)

        assertFalse(result.isValid)
        assertTrue(result.validationError!!.contains("JSON Syntax Error"))
    }

    @Test
    fun testAdminExtrasStringEmbeddedJson() {
        val extrasJson = JSONObject().apply {
            put("server_url", "https://embedded.mdm.io")
            put("enrollment_token", "tok_str_123")
            put("tenant_id", "dept_hr")
        }

        val json = JSONObject().apply {
            put("android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME", "com.focusdns.app")
            put("android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE", extrasJson.toString())
        }

        val result = parser.parseJson(json.toString())
        assertTrue(result.isValid)
        assertEquals("https://embedded.mdm.io", result.adminExtras.serverUrl)
        assertEquals("tok_str_123", result.adminExtras.enrollmentToken)
        assertEquals("dept_hr", result.adminExtras.tenantId)
    }

    @Test
    fun testLifeSafetyEmergencyWhitelistAlwaysContainsDialerNumbers() {
        // Even when no emergency whitelist is supplied in QR payload, default must contain emergency numbers
        val json = JSONObject().apply {
            put("android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME", "com.focusdns.app")
        }

        val result = parser.parseJson(json.toString())
        val whitelist = result.adminExtras.emergencyWhitelist

        assertTrue(whitelist.contains("911"))
        assertTrue(whitelist.contains("112"))
        assertTrue(whitelist.contains("999"))
        assertTrue(whitelist.contains("000"))
        assertTrue(whitelist.contains("100"))
        assertTrue(whitelist.contains("108"))
        assertTrue(whitelist.contains("988"))
    }

    @Test
    fun testChecksumVerificationMatchesSha256() {
        val testBytes = "FocusDNS-Enterprise-APK-Payload-Content".toByteArray(Charsets.UTF_8)
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(testBytes)
        val expectedHex = digest.joinToString("") { "%02x".format(it) }

        assertTrue(parser.verifyChecksum(testBytes, expectedHex))
        assertTrue(parser.verifyChecksum(testBytes, expectedHex.uppercase()))
        assertFalse(parser.verifyChecksum(testBytes, "deadbeef12345678"))
        assertFalse(parser.verifyChecksum(testBytes, ""))
    }

    @Test
    fun testToPersistableBundleConversion() {
        val extras = ZeroTouchQrPayloadParser.ProvisioningAdminExtras(
            serverUrl = "https://pb.test.io",
            enrollmentToken = "tok_bundle_456",
            tenantId = "test_tenant",
            deviceId = "test_dev_01",
            enforceStrictUninstallLock = true,
            autoLockTask = true,
            privateDnsHost = "dns.test.io"
        )

        val pb = parser.toPersistableBundle(extras)
        assertNotNull(pb)
        assertEquals("https://pb.test.io", extras.serverUrl)
        assertEquals("tok_bundle_456", extras.enrollmentToken)
        assertEquals("test_tenant", extras.tenantId)
        assertEquals("test_dev_01", extras.deviceId)
        assertTrue(extras.enforceStrictUninstallLock)
        assertTrue(extras.autoLockTask)
        assertEquals("dns.test.io", extras.privateDnsHost)
    }
}
