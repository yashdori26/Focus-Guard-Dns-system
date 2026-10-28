package com.focusdns.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for MultiOemSettingsSandbox verifying OEM vendor detection,
 * multi-language dangerous action matching, and the inviolable conditional
 * uninstallation law across all vendor settings environments.
 */
class MultiOemSettingsSandboxTest {

    @Test
    fun testDetectVendor_allMajorOems() {
        assertEquals(MultiOemSettingsSandbox.OemVendor.SAMSUNG_ONEUI, MultiOemSettingsSandbox.detectVendor("com.samsung.android.settings"))
        assertEquals(MultiOemSettingsSandbox.OemVendor.SAMSUNG_ONEUI, MultiOemSettingsSandbox.detectVendor("com.samsung.android.sm_cn"))
        assertEquals(MultiOemSettingsSandbox.OemVendor.XIAOMI_MIUI_HYPEROS, MultiOemSettingsSandbox.detectVendor("com.miui.securitycenter"))
        assertEquals(MultiOemSettingsSandbox.OemVendor.OPPO_COLOROS, MultiOemSettingsSandbox.detectVendor("com.coloros.safecenter"))
        assertEquals(MultiOemSettingsSandbox.OemVendor.VIVO_ORIGINOS, MultiOemSettingsSandbox.detectVendor("com.iqoo.secure"))
        assertEquals(MultiOemSettingsSandbox.OemVendor.ONEPLUS_OXYGENOS, MultiOemSettingsSandbox.detectVendor("com.oneplus.security"))
        assertEquals(MultiOemSettingsSandbox.OemVendor.HUAWEI_EMUI, MultiOemSettingsSandbox.detectVendor("com.huawei.systemmanager"))
        assertEquals(MultiOemSettingsSandbox.OemVendor.GOOGLE_PIXEL, MultiOemSettingsSandbox.detectVendor("com.android.settings"))
        assertEquals(MultiOemSettingsSandbox.OemVendor.AOSP_GENERIC, MultiOemSettingsSandbox.detectVendor("com.custom.rom.settings"))
    }

    @Test
    fun testIdleSession_permitsUninstallationAcrossAllOems() {
        // When canUninstall is true (no active focus session, timer 0):
        // Package installer, OEM settings app details, and deactivation are 100% allowed!
        val vendors = listOf(
            "com.samsung.android.settings",
            "com.miui.securitycenter",
            "com.coloros.safecenter",
            "com.huawei.systemmanager",
            "com.android.settings",
            "com.google.android.packageinstaller"
        )

        for (pkg in vendors) {
            val (intercepted, reason) = MultiOemSettingsSandbox.evaluateWindow(
                packageName = pkg,
                className = "InstalledAppDetails",
                nodeTexts = listOf("FocusDNS", "Uninstall", "Force Stop", "Clear Storage"),
                canUninstall = true,
                isOurApp = false
            )
            assertFalse("When session is idle, $pkg must NEVER be intercepted", intercepted)
            assertEquals(MultiOemSettingsSandbox.InterceptReason.NONE, reason)
        }
    }

    @Test
    fun testActiveSession_interceptsSamsungForceStopAndClearStorage() {
        val (intercepted, reason) = MultiOemSettingsSandbox.evaluateWindow(
            packageName = "com.samsung.android.settings",
            className = "com.samsung.android.settings.applications.AppDetailActivity",
            nodeTexts = listOf("FocusDNS", "Force stop", "Storage", "Clear data"),
            canUninstall = false,
            isOurApp = false
        )
        assertTrue(intercepted)
        assertTrue(reason == MultiOemSettingsSandbox.InterceptReason.FORCE_STOP_ATTEMPT ||
                   reason == MultiOemSettingsSandbox.InterceptReason.CLEAR_STORAGE_ATTEMPT)
    }

    @Test
    fun testActiveSession_interceptsXiaomiSecurityCenterAdminRevocation() {
        val (intercepted, reason) = MultiOemSettingsSandbox.evaluateWindow(
            packageName = "com.miui.securitycenter",
            className = "DeviceAdminAdd",
            nodeTexts = listOf("FocusDNS", "Deactivate device administrator", "Cancel"),
            canUninstall = false,
            isOurApp = false
        )
        assertTrue(intercepted)
        assertEquals(MultiOemSettingsSandbox.InterceptReason.DEVICE_ADMIN_REVOCATION, reason)
    }

    @Test
    fun testActiveSession_interceptsPrivateDnsBypass() {
        val (intercepted, reason) = MultiOemSettingsSandbox.evaluateWindow(
            packageName = "com.android.settings",
            className = "PrivateDnsSettings",
            nodeTexts = listOf("Network & internet", "Private DNS", "dns.google", "Save"),
            canUninstall = false,
            isOurApp = false
        )
        assertTrue(intercepted)
        assertEquals(MultiOemSettingsSandbox.InterceptReason.PRIVATE_DNS_BYPASS, reason)
    }

    @Test
    fun testActiveSession_interceptsSystemClockTampering() {
        val (intercepted, reason) = MultiOemSettingsSandbox.evaluateWindow(
            packageName = "com.android.settings",
            className = "DateTimeSettings",
            nodeTexts = listOf("Date & time", "Set time", "Automatic date & time"),
            canUninstall = false,
            isOurApp = false
        )
        assertTrue(intercepted)
        assertEquals(MultiOemSettingsSandbox.InterceptReason.SYSTEM_CLOCK_TAMPERING, reason)
    }

    @Test
    fun testActiveSession_interceptsNetworkSettingsReset() {
        val (intercepted, reason) = MultiOemSettingsSandbox.evaluateWindow(
            packageName = "com.android.settings",
            className = "ResetNetworkSettingsActivity",
            nodeTexts = listOf("Reset network settings", "This will reset all network settings, including Wi-Fi, Mobile data, and Bluetooth"),
            canUninstall = false,
            isOurApp = false
        )
        assertTrue(intercepted)
        assertEquals(MultiOemSettingsSandbox.InterceptReason.NETWORK_SETTINGS_RESET, reason)
    }

    @Test
    fun testActiveSession_interceptsDeveloperOptionsUsbDebugging() {
        val (intercepted, reason) = MultiOemSettingsSandbox.evaluateWindow(
            packageName = "com.android.settings",
            className = "DevelopmentSettingsDashboardFragment",
            nodeTexts = listOf("Developer options", "USB debugging", "Revoke USB debugging authorizations"),
            canUninstall = false,
            isOurApp = false
        )
        assertTrue(intercepted)
        assertEquals(MultiOemSettingsSandbox.InterceptReason.DEVELOPER_OPTIONS_EXPLOIT, reason)
    }

    @Test
    fun testEmergencyPackages_areNeverIntercepted() {
        val (intercepted, reason) = MultiOemSettingsSandbox.evaluateWindow(
            packageName = "com.google.android.dialer",
            className = "DialtactsActivity",
            nodeTexts = listOf("Emergency Call", "112", "Call"),
            canUninstall = false,
            isOurApp = false
        )
        assertFalse("Emergency dialer must NEVER be intercepted", intercepted)
        assertEquals(MultiOemSettingsSandbox.InterceptReason.NONE, reason)
    }

    @Test
    fun testUnrelatedApps_areNeverIntercepted() {
        val (intercepted, reason) = MultiOemSettingsSandbox.evaluateWindow(
            packageName = "com.google.android.packageinstaller",
            className = "UninstallerActivity",
            nodeTexts = listOf("Do you want to uninstall Twitter?", "Cancel", "OK"),
            canUninstall = false,
            isOurApp = false
        )
        assertFalse("Uninstalling other apps must not be intercepted", intercepted)
        assertEquals(MultiOemSettingsSandbox.InterceptReason.NONE, reason)
    }
}
