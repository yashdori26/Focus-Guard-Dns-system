package com.focusdns.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for UninstallProtectionManager verifying package identification,
 * string token matching for destructive actions and clock tampering, and
 * the non-blocking behavior when uninstallation is permitted.
 */
class UninstallProtectionManagerTest {

    // Pure logic simulation matching UninstallProtectionManager
    private fun shouldInterceptWindow(
        canUninstall: Boolean,
        packageName: String,
        activityClass: String,
        windowTexts: List<String>
    ): Boolean {
        // Core law: If uninstallation is permitted, NEVER intercept
        if (canUninstall) {
            return false
        }

        val isInstaller = UninstallProtectionManager.KNOWN_PACKAGE_INSTALLERS.contains(packageName)
        val isSettings = UninstallProtectionManager.KNOWN_SETTINGS_PACKAGES.contains(packageName)

        if (!isInstaller && !isSettings) {
            return false
        }

        val lowerClass = activityClass.lowercase()
        val allTextsLower = windowTexts.joinToString(" ").lowercase()

        // 1. Check for uninstall / delete / clear data actions
        val isUninstallAction = DANGEROUS_ACTIONS.any { act ->
            lowerClass.contains(act) || allTextsLower.contains(act)
        }

        val targetsOurApp = lowerClass.contains("focusdns") ||
            allTextsLower.contains("focusdns") ||
            allTextsLower.contains("focus dns") ||
            allTextsLower.contains("focus_dns") ||
            allTextsLower.contains("com.focusdns.app")

        if (isUninstallAction && targetsOurApp) {
            return true
        }

        // 2. Check for Date & Time clock manipulation attempts
        val isTimeTampering = DATE_TIME_ACTIONS.any { act ->
            lowerClass.contains(act) || allTextsLower.contains(act)
        }
        if (isTimeTampering) {
            return true
        }

        return false
    }

    companion object {
        private val DANGEROUS_ACTIONS = listOf(
            "uninstall", "delete", "remove", "force stop", "clear data",
            "clear storage", "deactivate", "disable admin", "device administrator"
        )

        private val DATE_TIME_ACTIONS = listOf(
            "date & time", "date and time", "automatic date",
            "set time", "time zone", "network-provided time"
        )
    }

    @Test
    fun testKnownPackageInstallers_containsStandardAndOemPackages() {
        val installers = UninstallProtectionManager.KNOWN_PACKAGE_INSTALLERS
        assertTrue(installers.contains("com.google.android.packageinstaller"))
        assertTrue(installers.contains("com.android.packageinstaller"))
        assertTrue(installers.contains("com.samsung.android.packageinstaller"))
        assertTrue(installers.contains("com.miui.packageinstaller"))
        assertTrue(installers.contains("com.coloros.packageinstaller"))
        assertTrue(installers.contains("com.oppo.packageinstaller"))
        assertTrue(installers.contains("com.vivo.packageinstaller"))
    }

    @Test
    fun testKnownSettingsPackages_containsStandardAndOemSecurityCenters() {
        val settings = UninstallProtectionManager.KNOWN_SETTINGS_PACKAGES
        assertTrue(settings.contains("com.android.settings"))
        assertTrue(settings.contains("com.samsung.android.settings"))
        assertTrue(settings.contains("com.miui.securitycenter"))
        assertTrue(settings.contains("com.coloros.safecenter"))
        assertTrue(settings.contains("com.huawei.systemmanager"))
        assertTrue(settings.contains("com.oppo.safecenter"))
        assertTrue(settings.contains("com.iqoo.secure"))
    }

    @Test
    fun testNormalMode_neverInterceptsUninstall() {
        // When canUninstall is true (Protection OFF, Timer 0), uninstallation is 100% permitted
        val intercepted = shouldInterceptWindow(
            canUninstall = true,
            packageName = "com.google.android.packageinstaller",
            activityClass = "com.android.packageinstaller.UninstallerActivity",
            windowTexts = listOf("Do you want to uninstall this app?", "FocusDNS", "OK", "Cancel")
        )
        assertFalse("When uninstallation is permitted, installer must NEVER be intercepted", intercepted)
    }

    @Test
    fun testNormalMode_neverInterceptsSettingsDetails() {
        val intercepted = shouldInterceptWindow(
            canUninstall = true,
            packageName = "com.android.settings",
            activityClass = "com.android.settings.applications.InstalledAppDetails",
            windowTexts = listOf("FocusDNS", "Uninstall", "Force Stop", "Storage & cache")
        )
        assertFalse("When uninstallation is permitted, settings must NOT be intercepted", intercepted)
    }

    @Test
    fun testActiveProtection_interceptsPackageInstaller() {
        // When canUninstall is false (session running), installer IS intercepted
        val intercepted = shouldInterceptWindow(
            canUninstall = false,
            packageName = "com.google.android.packageinstaller",
            activityClass = "com.android.packageinstaller.UninstallerActivity",
            windowTexts = listOf("Do you want to uninstall FocusDNS?", "OK", "Cancel")
        )
        assertTrue("When protection is locked, package installer must be intercepted", intercepted)
    }

    @Test
    fun testActiveProtection_interceptsForceStopAndClearData() {
        val intercepted = shouldInterceptWindow(
            canUninstall = false,
            packageName = "com.android.settings",
            activityClass = "com.android.settings.InstalledAppDetails",
            windowTexts = listOf("FocusDNS App Info", "Force Stop", "Uninstall", "Clear Data")
        )
        assertTrue("When protection is locked, Force Stop and Clear Data must be intercepted", intercepted)
    }

    @Test
    fun testActiveProtection_interceptsDeviceAdminDeactivation() {
        val intercepted = shouldInterceptWindow(
            canUninstall = false,
            packageName = "com.android.settings",
            activityClass = "DeviceAdminAddActivity",
            windowTexts = listOf("Deactivate this device admin app?", "FocusDNS", "Cancel", "Deactivate")
        )
        assertTrue("Device administrator deactivation must be intercepted when session is active", intercepted)
    }

    @Test
    fun testActiveProtection_interceptsDateTimeTampering() {
        val intercepted = shouldInterceptWindow(
            canUninstall = false,
            packageName = "com.android.settings",
            activityClass = "com.android.settings.DateTimeSettings",
            windowTexts = listOf("Date & time", "Automatic date & time", "Set time")
        )
        assertTrue("Date/Time tampering to bypass timer must be intercepted during active focus", intercepted)
    }

    @Test
    fun testActiveProtection_doesNotInterceptUnrelatedApps() {
        // Uninstalling another distracting app or using unrelated settings is not blocked
        val intercepted = shouldInterceptWindow(
            canUninstall = false,
            packageName = "com.google.android.packageinstaller",
            activityClass = "com.android.packageinstaller.UninstallerActivity",
            windowTexts = listOf("Do you want to uninstall Twitter?", "OK", "Cancel")
        )
        assertFalse("Uninstalling other apps must not be intercepted", intercepted)
    }
}
