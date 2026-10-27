package com.example.focus_dns

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class RulesStoreTest {

    @Before
    fun setUp() {
        RulesStore.clearAllTemporaryPasses()
    }

    @Test
    fun testVpnAppDetection() {
        assertTrue("NordVPN must be detected as VPN app", RulesStore.isVpnApp("com.nordvpn.android"))
        assertTrue("ExpressVPN must be detected as VPN app", RulesStore.isVpnApp("com.expressvpn.vpn"))
        assertTrue("ProtonVPN must be detected as VPN app", RulesStore.isVpnApp("ch.protonvpn.android"))
        assertTrue("WireGuard must be detected as VPN app", RulesStore.isVpnApp("com.wireguard.android"))
        assertTrue("Cloudflare 1.1.1.1 must be detected as VPN app", RulesStore.isVpnApp("com.cloudflare.onedotonedotonedtone"))

        assertFalse("Reddit is not a VPN app", RulesStore.isVpnApp("com.reddit.frontpage"))
        assertFalse("YouTube is not a VPN app", RulesStore.isVpnApp("com.google.android.youtube"))
    }

    @Test
    fun testEvaluateIsBlocked_deepFocusApp() {
        val blocked = setOf("com.reddit.frontpage", "com.instagram.android")

        // Blocked items return true
        assertTrue(RulesStore.evaluateIsBlocked("com.reddit.frontpage", blocked, isStrict = false, isVpnLost = false))
        assertTrue(RulesStore.evaluateIsBlocked("com.instagram.android", blocked, isStrict = false, isVpnLost = false))

        // Non-blocked items return false
        assertFalse(RulesStore.evaluateIsBlocked("com.google.android.youtube", blocked, isStrict = false, isVpnLost = false))
    }

    @Test
    fun testEvaluateIsBlocked_ourAppNeverBlocked() {
        val blocked = setOf("com.example.focus_dns")
        assertFalse(
            "FocusDNS must never block itself",
            RulesStore.evaluateIsBlocked("com.example.focus_dns", blocked, isStrict = true, isVpnLost = true, isOurApp = true)
        )
    }

    @Test
    fun testEvaluateIsBlocked_strictModeVpnApps() {
        val blocked = setOf("com.reddit.frontpage")

        // In normal mode, VPN apps are allowed unless explicitly in blocked list
        assertFalse(
            "NordVPN allowed in normal mode if not in blocked list",
            RulesStore.evaluateIsBlocked("com.nordvpn.android", blocked, isStrict = false, isVpnLost = false)
        )

        // In Strict Mode, VPN apps are automatically intercepted to prevent circumvention
        assertTrue(
            "NordVPN must be intercepted in Strict Mode",
            RulesStore.evaluateIsBlocked("com.nordvpn.android", blocked, isStrict = true, isVpnLost = false)
        )
        assertTrue(
            "ProtonVPN must be intercepted in Strict Mode",
            RulesStore.evaluateIsBlocked("ch.protonvpn.android", blocked, isStrict = true, isVpnLost = false)
        )
    }

    @Test
    fun testTemporaryPass() {
        val pkg = "com.reddit.test_pass"
        RulesStore.grantTemporaryPass(pkg, durationMs = 10000L)
        assertTrue("Temporary pass should be active immediately", RulesStore.isTemporaryPassActive(pkg))

        val blocked = setOf(pkg)
        assertFalse(
            "Active temporary pass must bypass blocking",
            RulesStore.evaluateIsBlocked(pkg, blocked, isStrict = true, isVpnLost = false)
        )

        RulesStore.clearTemporaryPass(pkg)
        assertFalse("Pass must be inactive after clear", RulesStore.isTemporaryPassActive(pkg))
        assertTrue(
            "Package must be blocked again after pass clearance",
            RulesStore.evaluateIsBlocked(pkg, blocked, isStrict = true, isVpnLost = false)
        )
    }

    @Test
    fun testVpnLostLockdown() {
        val blocked = emptySet<String>()

        // When VPN is lost in Strict Mode, third-party apps are locked down
        assertTrue(
            "Arbitrary app must be locked down when VPN is lost in Strict Mode",
            RulesStore.evaluateIsBlocked("com.random.socialapp", blocked, isStrict = true, isVpnLost = true, isSystemWhitelisted = false)
        )

        // Essential system components remain whitelisted
        assertFalse(
            "System UI must not be locked down",
            RulesStore.evaluateIsBlocked("com.android.systemui", blocked, isStrict = true, isVpnLost = true, isSystemWhitelisted = true)
        )
    }

    @Test
    fun testRoleBasedWhitelisting() {
        // Essential framework and system UI
        assertTrue("Android OS must be whitelisted", RulesStore.isSystemWhitelisted(null, "android"))
        assertTrue("System UI must be whitelisted", RulesStore.isSystemWhitelisted(null, "com.android.systemui"))
        assertTrue("Phone telephony must be whitelisted", RulesStore.isSystemWhitelisted(null, "com.android.phone"))
        assertTrue("Telecom server must be whitelisted", RulesStore.isSystemWhitelisted(null, "com.android.server.telecom"))
        assertTrue("Nexus launcher must be whitelisted", RulesStore.isSystemWhitelisted(null, "com.google.android.apps.nexuslauncher"))
        assertTrue("AOSP launcher3 must be whitelisted", RulesStore.isSystemWhitelisted(null, "com.android.launcher3"))

        // In-Call UI & Dialer components
        assertTrue("AOSP InCallUI must be whitelisted", RulesStore.isSystemWhitelisted(null, "com.android.incallui"))
        assertTrue("Samsung InCallUI must be whitelisted", RulesStore.isSystemWhitelisted(null, "com.samsung.android.incallui"))
        assertTrue("Google Dialer must be whitelisted", RulesStore.isSystemWhitelisted(null, "com.google.android.dialer"))
        assertTrue("OEM InCallUI must be whitelisted", RulesStore.isSystemWhitelisted(null, "com.oem.incallui.app"))

        // Malicious sideloaded apps containing 'launcher' substring must NOT be whitelisted
        assertFalse("Malicious launcher package must NOT be whitelisted", RulesStore.isSystemWhitelisted(null, "com.malicious.launcher"))
        assertFalse("Fake launcher must NOT be whitelisted", RulesStore.isSystemWhitelisted(null, "evil.launcher.app"))
        assertFalse("Social app must NOT be whitelisted", RulesStore.isSystemWhitelisted(null, "com.reddit.frontpage"))
    }

    @Test
    fun testVpnConsentWhitelisting() {
        // Strict Mode: FocusDNS's own consent dialog is allowed so user can re-grant/restore VPN
        assertFalse(
            "FocusDNS consent dialog must be ALLOWED (not guarded)",
            RulesStore.evaluateShouldGuardVpnConsent(
                "com.android.vpndialogs",
                listOf("FocusDNS", "wants to set up a VPN connection"),
                isStrict = true
            )
        )
        assertFalse(
            "focus_dns (underscore) consent dialog must be ALLOWED (not guarded)",
            RulesStore.evaluateShouldGuardVpnConsent(
                "com.android.vpndialogs",
                listOf("focus_dns", "wants to set up a VPN connection"),
                isStrict = true
            )
        )

        // Strict Mode: Third-party VPN consent dialog must be BLOCKED
        assertTrue(
            "NordVPN consent dialog must be BLOCKED (guarded)",
            RulesStore.evaluateShouldGuardVpnConsent(
                "com.android.vpndialogs",
                listOf("NordVPN", "wants to set up a VPN connection"),
                isStrict = true
            )
        )

        // Normal mode: Never guards consent dialogs
        assertFalse(
            RulesStore.evaluateShouldGuardVpnConsent(
                "com.android.vpndialogs",
                listOf("ExpressVPN"),
                isStrict = false
            )
        )
    }

    @Test
    fun testSettingsGuardingLogic() {
        // Normal mode: Never guards settings
        assertFalse(
            RulesStore.evaluateShouldGuardSettings(
                "com.android.vpndialogs", null, listOf("NordVPN"), isStrict = false
            )
        )
        assertFalse(
            RulesStore.evaluateShouldGuardSettings(
                "com.android.settings", "com.android.settings.VpnSettings", listOf("VPN", "Disconnect"), isStrict = false
            )
        )

        // Strict Mode: Allows FocusDNS consent, guards 3rd party
        assertFalse(
            "FocusDNS VPN consent dialog must NOT be guarded",
            RulesStore.evaluateShouldGuardSettings(
                "com.android.vpndialogs", null, listOf("FocusDNS", "Connection request"), isStrict = true
            )
        )
        assertTrue(
            "Third-party VPN dialogs must be guarded in Strict Mode",
            RulesStore.evaluateShouldGuardSettings(
                "com.android.vpndialogs", null, listOf("NordVPN", "Connection request"), isStrict = true
            )
        )

        // Strict Mode: Guards FocusDNS accessibility settings
        assertTrue(
            "FocusDNS accessibility settings must be guarded in Strict Mode",
            RulesStore.evaluateShouldGuardSettings(
                "com.android.settings",
                "com.android.settings.SubSettings",
                listOf("FocusDNS App Blocker", "Use service"),
                isStrict = true
            )
        )

        // Strict Mode: Guards Date & Time settings to prevent clock tampering
        assertTrue(
            "Date and Time settings must be guarded in Strict Mode",
            RulesStore.evaluateShouldGuardSettings(
                "com.android.settings",
                "com.android.settings.DateTimeSettings",
                listOf("Date & time", "Set time automatically"),
                isStrict = true
            )
        )
        assertTrue(
            "Zone picker must be guarded in Strict Mode",
            RulesStore.evaluateShouldGuardSettings(
                "com.android.settings",
                "com.android.settings.ZonePicker",
                listOf("Select time zone"),
                isStrict = true
            )
        )

        // Strict Mode: Guards Developer Options & USB Debugging
        assertTrue(
            "Developer options must be guarded in Strict Mode",
            RulesStore.evaluateShouldGuardSettings(
                "com.android.settings",
                "com.android.settings.DevelopmentSettings",
                listOf("Developer options", "USB debugging"),
                isStrict = true
            )
        )

        // Strict Mode: Guards VPN disconnect screens
        assertTrue(
            "VPN settings with disconnect text must be guarded in Strict Mode",
            RulesStore.evaluateShouldGuardSettings(
                "com.android.settings",
                "com.android.settings.VpnSettings",
                listOf("FocusDNS", "Always-on VPN", "Disconnect"),
                isStrict = true
            )
        )

        // Strict Mode: OEM settings (Samsung & Xiaomi)
        assertTrue(
            "Samsung settings with FocusDNS uninstall must be guarded",
            RulesStore.evaluateShouldGuardSettings(
                "com.samsung.android.settings",
                "com.android.settings.applications.InstalledAppDetailsTop",
                listOf("FocusDNS", "Uninstall", "Force stop"),
                isStrict = true
            )
        )
        assertTrue(
            "MIUI Security Center guarding FocusDNS accessibility must be guarded",
            RulesStore.evaluateShouldGuardSettings(
                "com.miui.securitycenter",
                "com.miui.securitycenter.activity.AppDetailsActivity",
                listOf("FocusDNS", "Turn off"),
                isStrict = true
            )
        )

        // Strict Mode: Unrelated settings screens are allowed
        assertFalse(
            "Display settings must not be guarded",
            RulesStore.evaluateShouldGuardSettings(
                "com.android.settings",
                "com.android.settings.DisplaySettings",
                listOf("Brightness level", "Dark theme"),
                isStrict = true
            )
        )
    }

    @Test
    fun testInstallerGuardingLogic() {
        // Normal mode: Never guards installer
        assertFalse(
            RulesStore.evaluateShouldGuardInstaller(
                "com.android.packageinstaller",
                "com.android.packageinstaller.UninstallerActivity",
                listOf("FocusDNS", "Do you want to uninstall this app?"),
                isStrict = false
            )
        )

        // Strict Mode: Guards FocusDNS uninstall attempts
        assertTrue(
            "Google Package Installer uninstalling FocusDNS must be guarded",
            RulesStore.evaluateShouldGuardInstaller(
                "com.google.android.packageinstaller",
                "com.android.packageinstaller.UninstallerActivity",
                listOf("FocusDNS", "Do you want to uninstall this app?"),
                isStrict = true
            )
        )
        assertTrue(
            "AOSP Package Installer uninstalling FocusDNS must be guarded",
            RulesStore.evaluateShouldGuardInstaller(
                "com.android.packageinstaller",
                "com.android.packageinstaller.UninstallAppProgress",
                listOf("FocusDNS", "Uninstalling..."),
                isStrict = true
            )
        )

        // Strict Mode: Uninstalling OTHER apps is permitted
        assertFalse(
            "Uninstalling unrelated app must not be blocked",
            RulesStore.evaluateShouldGuardInstaller(
                "com.android.packageinstaller",
                "com.android.packageinstaller.UninstallerActivity",
                listOf("SomeOtherApp", "Do you want to uninstall this app?"),
                isStrict = true
            )
        )
    }

    @Test
    fun testEvaluateTimedStrictState() {
        // 1. Timed strict mode disabled
        val (active0, rem0) = RulesStore.evaluateTimedStrictState(nowElapsed = 1000L, strictUntilElapsed = 5000L, isEnabled = false)
        assertFalse("Disabled strict mode must not be active", active0)
        assertEquals(0, rem0)

        // 2. Active timed strict mode with 15 minutes remaining
        val now = 10_000L
        val until = now + (15 * 60 * 1000L)
        val (active1, rem1) = RulesStore.evaluateTimedStrictState(nowElapsed = now, strictUntilElapsed = until, isEnabled = true)
        assertTrue("Active timed strict mode must be active", active1)
        assertEquals(15 * 60, rem1)

        // 3. Exactly expired
        val (active2, rem2) = RulesStore.evaluateTimedStrictState(nowElapsed = until, strictUntilElapsed = until, isEnabled = true)
        assertFalse("Expired timed strict mode must not be active", active2)
        assertEquals(0, rem2)

        // 4. Past expiration
        val (active3, rem3) = RulesStore.evaluateTimedStrictState(nowElapsed = until + 5000L, strictUntilElapsed = until, isEnabled = true)
        assertFalse("Past expiration timed strict mode must not be active", active3)
        assertEquals(0, rem3)

        // 5. Untimed strict mode (strictUntilElapsed == 0L)
        val (active4, rem4) = RulesStore.evaluateTimedStrictState(nowElapsed = now, strictUntilElapsed = 0L, isEnabled = true)
        assertTrue("Untimed strict mode must be active", active4)
        assertEquals(0, rem4)
    }
}
