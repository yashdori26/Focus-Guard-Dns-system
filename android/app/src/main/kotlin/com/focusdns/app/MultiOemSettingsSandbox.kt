package com.focusdns.app

import android.content.Context
import android.util.Log

/**
 * MultiOemSettingsSandbox
 * =======================
 * Advanced anti-circumvention sandboxing engine specialized across major Android
 * OEM vendor environments (Samsung OneUI, Xiaomi MIUI/HyperOS, Oppo ColorOS,
 * Vivo OriginOS/FuntouchOS, OnePlus OxygenOS, Huawei EMUI/HarmonyOS, Google Pixel).
 *
 * Core Responsibility:
 * 1. Analyzes window package, class, and view hierarchy texts against OEM-specific signatures.
 * 2. Detects destructive evasion actions (Force Stop, Clear Data, Deactivate Admin,
 *    Private DNS manipulation, Date/Time alteration, Developer Options toggling).
 * 3. Enforces the Conditional Uninstallation Law:
 *    - IF session is idle (Protection OFF & Timer 0) -> 100% permitted (no intervention).
 *    - IF focus session is active -> Intercepts evasion attempt and safeguards FocusDNS.
 */
object MultiOemSettingsSandbox {

    private const val TAG = "MultiOemSandbox"

    enum class OemVendor {
        SAMSUNG_ONEUI,
        XIAOMI_MIUI_HYPEROS,
        OPPO_COLOROS,
        VIVO_ORIGINOS,
        ONEPLUS_OXYGENOS,
        HUAWEI_EMUI,
        GOOGLE_PIXEL,
        AOSP_GENERIC
    }

    enum class InterceptReason {
        NONE,
        FORCE_STOP_ATTEMPT,
        CLEAR_STORAGE_ATTEMPT,
        DEVICE_ADMIN_REVOCATION,
        PRIVATE_DNS_BYPASS,
        SYSTEM_CLOCK_TAMPERING,
        NETWORK_SETTINGS_RESET,
        DEVELOPER_OPTIONS_EXPLOIT,
        PACKAGE_INSTALLER_UNINSTALL
    }

    // OEM Settings & Security Center Package Mapping
    val OEM_SETTINGS_PACKAGES = mapOf(
        "com.samsung.android.settings" to OemVendor.SAMSUNG_ONEUI,
        "com.samsung.android.sm_cn" to OemVendor.SAMSUNG_ONEUI,
        "com.sec.android.app.servicemodeapp" to OemVendor.SAMSUNG_ONEUI,
        "com.miui.securitycenter" to OemVendor.XIAOMI_MIUI_HYPEROS,
        "com.miui.cleanmaster" to OemVendor.XIAOMI_MIUI_HYPEROS,
        "com.miui.permcenter" to OemVendor.XIAOMI_MIUI_HYPEROS,
        "com.coloros.safecenter" to OemVendor.OPPO_COLOROS,
        "com.coloros.oppoguardelf" to OemVendor.OPPO_COLOROS,
        "com.oplus.securitypermission" to OemVendor.OPPO_COLOROS,
        "com.iqoo.secure" to OemVendor.VIVO_ORIGINOS,
        "com.vivo.permissionmanager" to OemVendor.VIVO_ORIGINOS,
        "com.oneplus.security" to OemVendor.ONEPLUS_OXYGENOS,
        "com.huawei.systemmanager" to OemVendor.HUAWEI_EMUI,
        "com.android.settings" to OemVendor.GOOGLE_PIXEL
    )

    // Dangerous Action Keywords
    val KEYWORDS_FORCE_STOP = setOf(
        "force stop", "forcestop", "force close", "stoppen erzwingen",
        "forzar detención", "interruption forcée", "forza arresto",
        "forçar parada", "закрыть принудительно", "强行停止", "強制停止"
    )

    val KEYWORDS_CLEAR_STORAGE = setOf(
        "clear storage", "clear data", "delete data", "clear all data",
        "speicher löschen", "daten löschen", "borrar datos", "effacer les données",
        "cancella dati", "limpar dados", "очистить хранилище", "очистить данные",
        "清除数据", "ストレージを消去"
    )

    val KEYWORDS_DEVICE_ADMIN = setOf(
        "device admin", "device administrator", "device administrators",
        "gerätemanager", "administrador de dispositivos", "administrateur de l'appareil",
        "amministratore dispositivo", "administrador do dispositivo",
        "администраторы устройства", "设备管理器", "デバイス管理者"
    )

    val KEYWORDS_PRIVATE_DNS = setOf(
        "private dns", "dns over tls", "privates dns", "dns privado",
        "dns privé", "dns privato", "частный dns", "私人 dns", "プライベート dns"
    )

    val KEYWORDS_DATE_TIME = setOf(
        "date & time", "date and time", "datum & uhrzeit", "fecha y hora",
        "date et heure", "data e ora", "data e hora", "дата и время",
        "日期和时间", "日付と時刻", "automatic date", "set time"
    )

    val KEYWORDS_NETWORK_RESET = setOf(
        "reset wi-fi, mobile & bluetooth", "reset network settings",
        "netzwerkeinstellungen zurücksetzen", "restablecer configuración de red",
        "réinitialiser les paramètres réseau", "ripristina impostazioni di rete",
        "redefinir configurações de rede", "сброс настроек сети", "还原网络设置"
    )

    val KEYWORDS_DEVELOPER_OPTIONS = setOf(
        "developer options", "entwickleroptionen", "opciones para desarrolladores",
        "options pour les développeurs", "opzioni sviluppatore", "opções do desenvolvedor",
        "для разработчиков", "开发者选项", "開発者向けオプション", "usb debugging"
    )

    /**
     * Identifies the OEM vendor from the package name.
     */
    fun detectVendor(packageName: String): OemVendor {
        return OEM_SETTINGS_PACKAGES[packageName] ?: OemVendor.AOSP_GENERIC
    }

    /**
     * Evaluates window inspection heuristics.
     * Pure function for unit testing and deterministic verification.
     */
    fun evaluateWindow(
        packageName: String,
        className: String?,
        nodeTexts: List<String>,
        canUninstall: Boolean,
        isOurApp: Boolean = false
    ): Pair<Boolean, InterceptReason> {
        // Never intercept inside FocusDNS itself
        if (isOurApp || packageName == "com.focusdns.app") {
            return Pair(false, InterceptReason.NONE)
        }

        // Never intercept if life-safety emergency package is active
        if (EmergencyCallExemptionManager.isEmergencyPackage(packageName)) {
            return Pair(false, InterceptReason.NONE)
        }

        // CORE LAW: When uninstallation is permitted (Protection OFF & Timer 0),
        // we NEVER intercept! Normal Android device behavior is completely unlocked.
        if (canUninstall) {
            return Pair(false, InterceptReason.NONE)
        }

        val cls = className ?: ""
        val lowerClass = cls.lowercase()
        val allTextsLower = nodeTexts.joinToString(" ").lowercase()

        val referencesFocusDns = lowerClass.contains("focusdns") ||
            allTextsLower.contains("focusdns") ||
            allTextsLower.contains("focus dns") ||
            allTextsLower.contains("focus guard") ||
            allTextsLower.contains("focus_dns") ||
            allTextsLower.contains("com.focusdns.app")

        // 1. Package Installer Uninstallation Attempt
        val isPackageInstaller = UninstallProtectionManager.KNOWN_PACKAGE_INSTALLERS.contains(packageName)
        if (isPackageInstaller && referencesFocusDns) {
            val hasUninstallAction = allTextsLower.contains("uninstall") ||
                allTextsLower.contains("delete") ||
                allTextsLower.contains("remove") ||
                lowerClass.contains("uninstall")
            if (hasUninstallAction) {
                return Pair(true, InterceptReason.PACKAGE_INSTALLER_UNINSTALL)
            }
        }

        // 2. Settings App Details Targeting FocusDNS
        if (referencesFocusDns) {
            if (KEYWORDS_FORCE_STOP.any { allTextsLower.contains(it) || lowerClass.contains(it) }) {
                return Pair(true, InterceptReason.FORCE_STOP_ATTEMPT)
            }
            if (KEYWORDS_CLEAR_STORAGE.any { allTextsLower.contains(it) || lowerClass.contains(it) }) {
                return Pair(true, InterceptReason.CLEAR_STORAGE_ATTEMPT)
            }
            if (KEYWORDS_DEVICE_ADMIN.any { allTextsLower.contains(it) || lowerClass.contains(it) }) {
                return Pair(true, InterceptReason.DEVICE_ADMIN_REVOCATION)
            }
            // General app details screen for FocusDNS while locked
            if (lowerClass.contains("appdetail") || lowerClass.contains("installedapp") || lowerClass.contains("manageapplications")) {
                return Pair(true, InterceptReason.FORCE_STOP_ATTEMPT)
            }
        }

        // 3. System-Wide Circumvention Attempts during Active Focus
        // A. Private DNS bypass (forcing DoT away from FocusDNS local VPN)
        if (KEYWORDS_PRIVATE_DNS.any { allTextsLower.contains(it) || lowerClass.contains(it) }) {
            return Pair(true, InterceptReason.PRIVATE_DNS_BYPASS)
        }

        // B. Date & Time tampering (attempting to fast-forward focus timer)
        if (KEYWORDS_DATE_TIME.any { allTextsLower.contains(it) || lowerClass.contains(it) }) {
            if (lowerClass.contains("datetime") || lowerClass.contains("zonepicker") || allTextsLower.contains("set time")) {
                return Pair(true, InterceptReason.SYSTEM_CLOCK_TAMPERING)
            }
        }

        // C. Network settings reset (clearing VPN profile)
        if (KEYWORDS_NETWORK_RESET.any { allTextsLower.contains(it) || lowerClass.contains(it) }) {
            return Pair(true, InterceptReason.NETWORK_SETTINGS_RESET)
        }

        // D. Developer Options enabling USB Debugging to force uninstall via ADB
        if (KEYWORDS_DEVELOPER_OPTIONS.any { allTextsLower.contains(it) || lowerClass.contains(it) }) {
            if (lowerClass.contains("development") || allTextsLower.contains("usb debugging")) {
                return Pair(true, InterceptReason.DEVELOPER_OPTIONS_EXPLOIT)
            }
        }

        return Pair(false, InterceptReason.NONE)
    }

    /**
     * Real-time inspection hook called from FocusAccessibilityService.
     */
    fun handleInspection(
        context: Context,
        packageName: String,
        className: String?,
        nodeTexts: List<String>
    ): Boolean {
        val canUninstall = ProtectionStateCoordinator.canUninstall(context)
        val (shouldBlock, reason) = evaluateWindow(
            packageName = packageName,
            className = className,
            nodeTexts = nodeTexts,
            canUninstall = canUninstall,
            isOurApp = packageName == context.packageName
        )

        if (shouldBlock) {
            Log.w(TAG, "Multi-OEM Sandbox intercepted circumvention attempt: $reason ($packageName / $className)")
            ProtectionLockWarningActivity.launch(context, reason.name)
            return true
        }

        return false
    }
}
