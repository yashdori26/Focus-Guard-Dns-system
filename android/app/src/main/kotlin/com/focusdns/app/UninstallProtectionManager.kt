package com.focusdns.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * UninstallProtectionManager
 * ==========================
 * Intercepts package uninstallation, application data clearing, and settings tampering
 * strictly during active focus sessions or running protection.
 *
 * Golden Rule:
 * - If ProtectionStateCoordinator.canUninstall() == TRUE:
 *     NEVER INTERCEPT! Allow user full freedom to uninstall, force-stop, or clear data.
 * - If ProtectionStateCoordinator.canUninstall() == FALSE:
 *     INTERCEPT! Prevent the package manager / settings from removing the application,
 *     and display the live countdown warning overlay.
 */
object UninstallProtectionManager {

    private const val TAG = "UninstallProtection"

    val KNOWN_PACKAGE_INSTALLERS = setOf(
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.samsung.android.packageinstaller",
        "com.miui.packageinstaller",
        "com.coloros.packageinstaller",
        "com.oppo.packageinstaller",
        "com.vivo.packageinstaller"
    )

    val KNOWN_SETTINGS_PACKAGES = setOf(
        "com.android.settings",
        "com.samsung.android.settings",
        "com.miui.securitycenter",
        "com.coloros.safecenter",
        "com.huawei.systemmanager",
        "com.oppo.safecenter",
        "com.iqoo.secure"
    )

    /**
     * Evaluates whether an uninstallation, force-stop, or tampering attempt should be blocked.
     * Pure function for unit testing.
     */
    fun evaluateShouldIntercept(
        packageName: String,
        className: String?,
        nodeTexts: List<String>,
        canUninstall: Boolean,
        isOurApp: Boolean = false
    ): Pair<Boolean, String> {
        // Never intercept inside FocusDNS itself
        if (isOurApp) {
            return Pair(false, "OUR_APP")
        }

        // Never intercept emergency telecom services
        if (EmergencyCallExemptionManager.isEmergencyPackage(packageName)) {
            return Pair(false, "EMERGENCY_EXEMPT")
        }

        // If uninstallation is allowed, NEVER intercept!
        if (canUninstall) {
            return Pair(false, "UNINSTALL_ALLOWED")
        }

        val cls = className ?: ""

        // 1. Package Installer attempting to delete or uninstall FocusDNS
        if (KNOWN_PACKAGE_INSTALLERS.contains(packageName)) {
            val isUninstallScreen = cls.contains("Uninstall", ignoreCase = true) ||
                cls.contains("Delete", ignoreCase = true) ||
                cls.contains("PackageInstaller", ignoreCase = true)

            val mentionsFocus = nodeTexts.any {
                val l = it.lowercase()
                l.contains("focusdns") || l.contains("focus dns") || l.contains("focus guard") || l.contains("focus_dns")
            }

            val mentionsRemoval = nodeTexts.any {
                val l = it.lowercase()
                l.contains("uninstall") || l.contains("delete") || l.contains("remove") || l.contains("do you want to uninstall")
            }

            if (mentionsFocus && (isUninstallScreen || mentionsRemoval)) {
                return Pair(true, "PACKAGE_INSTALLER_UNINSTALL_ATTEMPT")
            }
        }

        // 2. Settings App Details Screen (targeting FocusDNS)
        if (KNOWN_SETTINGS_PACKAGES.contains(packageName)) {
            val hasFocusName = nodeTexts.any {
                val l = it.lowercase()
                l.contains("focusdns") || l.contains("focus dns") || l.contains("focus guard") || l.contains("focus_dns")
            }

            val isAppManagementScreen = cls.contains("AppDetail", ignoreCase = true) ||
                cls.contains("InstalledApp", ignoreCase = true) ||
                cls.contains("ManageApplications", ignoreCase = true) ||
                cls.contains("SubSettings", ignoreCase = true)

            if (hasFocusName) {
                val hasDangerousAction = nodeTexts.any {
                    val l = it.lowercase()
                    l.contains("uninstall") ||
                    l.contains("force stop") ||
                    l.contains("clear data") ||
                    l.contains("clear storage") ||
                    l.contains("disable") ||
                    l.contains("deactivate")
                }

                if (hasDangerousAction || isAppManagementScreen) {
                    return Pair(true, "SETTINGS_APP_DELETION_ATTEMPT")
                }
            }

            // 3. Date & Time tampering (trying to fast-forward countdown clock)
            val isDateTimeSection = cls.contains("DateTime", ignoreCase = true) ||
                cls.contains("ZonePicker", ignoreCase = true) ||
                nodeTexts.any {
                    val l = it.lowercase()
                    l.contains("date & time") || l.contains("date and time") ||
                    l.contains("set time automatically") || l.contains("use network-provided time")
                }

            if (isDateTimeSection) {
                return Pair(true, "SETTINGS_DATE_TIME_TAMPERING_ATTEMPT")
            }

            // 4. Developer options (preventing ADB uninstallation)
            val isDevOptions = cls.contains("Development", ignoreCase = true) ||
                nodeTexts.any {
                    val l = it.lowercase()
                    l.contains("developer options") || l.contains("usb debugging")
                }

            if (isDevOptions) {
                return Pair(true, "SETTINGS_DEVELOPER_OPTIONS_ATTEMPT")
            }

            // 5. Device Admin settings screen
            val isDeviceAdminScreen = cls.contains("DeviceAdmin", ignoreCase = true) ||
                nodeTexts.any {
                    val l = it.lowercase()
                    l.contains("device admin") || l.contains("device administrators")
                }

            if (isDeviceAdminScreen && hasFocusName) {
                return Pair(true, "SETTINGS_DEVICE_ADMIN_DEACTIVATION_ATTEMPT")
            }
        }

        // 4. Delegate to MultiOemSettingsSandbox for deep multi-vendor inspection
        val (oemIntercept, oemReason) = MultiOemSettingsSandbox.evaluateWindow(
            packageName = packageName,
            className = className,
            nodeTexts = nodeTexts,
            canUninstall = canUninstall,
            isOurApp = isOurApp
        )
        if (oemIntercept) {
            return Pair(true, oemReason.name)
        }

        return Pair(false, "SAFE_WINDOW")
    }

    /**
     * Intercepts an accessibility window event if uninstallation protection is active.
     */
    fun handleWindowInspection(
        service: AccessibilityService,
        packageName: String,
        className: String?,
        nodeTexts: List<String>
    ): Boolean {
        val canUninstall = ProtectionStateCoordinator.canUninstall(service)
        val isOurApp = (packageName == service.packageName)

        val (shouldIntercept, reason) = evaluateShouldIntercept(
            packageName = packageName,
            className = className,
            nodeTexts = nodeTexts,
            canUninstall = canUninstall,
            isOurApp = isOurApp
        )

        if (shouldIntercept) {
            Log.w(TAG, "Shield triggered! Intercepting action. Reason: $reason (pkg=$packageName, cls=$className)")

            // Dismiss the offending screen by performing BACK or HOME
            service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)

            // Launch the countdown overlay
            val remainingSec = ProtectionStateCoordinator.getRemainingTimerSeconds(service)
            val warningIntent = Intent(service, ProtectionLockWarningActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("EXTRA_REMAINING_SECONDS", remainingSec)
                putExtra("EXTRA_REASON", reason)
            }
            service.startActivity(warningIntent)
            return true
        }

        return false
    }
}
