import 'package:flutter/foundation.dart';

/// Aggressiveness level of an OEM manufacturer's background task killer.
enum OemKillSeverity {
  /// Standard Android AOSP Doze behavior. Respects standard foreground services.
  standard,

  /// Mild background optimization. May delay alarms or jobs when screen is off.
  moderate,

  /// Aggressive killing. Terminates background services within 5-15 minutes of screen off.
  aggressive,

  /// Severe background slaughter. Terminates services on swipe-from-recents, restricts autostart.
  severe,

  /// Extreme hostility (e.g. Xiaomi MIUI/HyperOS, Huawei EMUI PowerGenie).
  /// Kills processes even with ongoing foreground notifications unless multi-permission bypass is granted.
  extreme,
}

/// Represents a distinct smartphone brand / operating system family.
enum OemFamily {
  xiaomi,
  samsung,
  huawei,
  oneplus,
  oppo,
  vivo,
  asus,
  sony,
  motorola,
  transsion,
  nothing,
  pixel,
  genericAosp,
}

/// A specific OEM battery/autostart management activity target.
@immutable
class OemActivityTarget {
  final String packageName;
  final String activityName;
  final String action;
  final Map<String, String> extras;
  final String description;
  final int minApiLevel;
  final int maxApiLevel;

  const OemActivityTarget({
    required this.packageName,
    required this.activityName,
    this.action = 'android.intent.action.MAIN',
    this.extras = const {},
    required this.description,
    this.minApiLevel = 21,
    this.maxApiLevel = 35,
  });

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'activityName': activityName,
        'action': action,
        'extras': extras,
        'description': description,
        'minApiLevel': minApiLevel,
        'maxApiLevel': maxApiLevel,
      };

  factory OemActivityTarget.fromJson(Map<String, dynamic> json) => OemActivityTarget(
        packageName: json['packageName'] as String,
        activityName: json['activityName'] as String,
        action: json['action'] as String? ?? 'android.intent.action.MAIN',
        extras: Map<String, String>.from(json['extras'] as Map? ?? {}),
        description: json['description'] as String? ?? '',
        minApiLevel: json['minApiLevel'] as int? ?? 21,
        maxApiLevel: json['maxApiLevel'] as int? ?? 35,
      );
}

/// Complete diagnostic profile for an OEM device ecosystem.
@immutable
class OemDeviceProfile {
  final OemFamily family;
  final String displayName;
  final String romName;
  final List<String> matchingManufacturers;
  final List<String> matchingBrands;
  final OemKillSeverity severity;
  final List<OemActivityTarget> autostartTargets;
  final List<OemActivityTarget> batteryOptimizationTargets;
  final List<OemActivityTarget> secondaryAppLaunchTargets;
  final List<String> killerComponentPackages;
  final List<String> recommendedUserActions;
  final bool requiresAutostartPermission;
  final bool requiresBatteryUnrestricted;
  final bool requiresRecentsLock;
  final bool requiresSecondaryLaunch;
  final int defaultSurvivalScore;

  const OemDeviceProfile({
    required this.family,
    required this.displayName,
    required this.romName,
    required this.matchingManufacturers,
    required this.matchingBrands,
    required this.severity,
    required this.autostartTargets,
    required this.batteryOptimizationTargets,
    this.secondaryAppLaunchTargets = const [],
    required this.killerComponentPackages,
    required this.recommendedUserActions,
    this.requiresAutostartPermission = true,
    this.requiresBatteryUnrestricted = true,
    this.requiresRecentsLock = true,
    this.requiresSecondaryLaunch = false,
    this.defaultSurvivalScore = 35,
  });

  bool matchesDevice({
    required String manufacturer,
    required String brand,
  }) {
    final m = manufacturer.toLowerCase();
    final b = brand.toLowerCase();
    return matchingManufacturers.any((item) => m.contains(item.toLowerCase())) ||
        matchingBrands.any((item) => b.contains(item.toLowerCase()));
  }

  Map<String, dynamic> toJson() => {
        'family': family.name,
        'displayName': displayName,
        'romName': romName,
        'matchingManufacturers': matchingManufacturers,
        'matchingBrands': matchingBrands,
        'severity': severity.name,
        'autostartTargets': autostartTargets.map((t) => t.toJson()).toList(),
        'batteryOptimizationTargets': batteryOptimizationTargets.map((t) => t.toJson()).toList(),
        'secondaryAppLaunchTargets': secondaryAppLaunchTargets.map((t) => t.toJson()).toList(),
        'killerComponentPackages': killerComponentPackages,
        'recommendedUserActions': recommendedUserActions,
        'requiresAutostartPermission': requiresAutostartPermission,
        'requiresBatteryUnrestricted': requiresBatteryUnrestricted,
        'requiresRecentsLock': requiresRecentsLock,
        'requiresSecondaryLaunch': requiresSecondaryLaunch,
        'defaultSurvivalScore': defaultSurvivalScore,
      };
}

/// Comprehensive registry containing profiles for 12 major smartphone OEM families.
class OemDeviceProfiles {
  OemDeviceProfiles._();

  // ===========================================================================
  // 1. XIAOMI / REDMI / POCO (MIUI & HYPEROS)
  // ===========================================================================
  static const OemDeviceProfile xiaomi = OemDeviceProfile(
    family: OemFamily.xiaomi,
    displayName: 'Xiaomi / Redmi / POCO',
    romName: 'HyperOS / MIUI',
    matchingManufacturers: ['xiaomi', 'redmi', 'poco', 'blackshark'],
    matchingBrands: ['xiaomi', 'redmi', 'poco'],
    severity: OemKillSeverity.extreme,
    autostartTargets: [
      OemActivityTarget(
        packageName: 'com.miui.securitycenter',
        activityName: 'com.miui.permcenter.autostart.AutoStartManagementActivity',
        description: 'MIUI / HyperOS Autostart Manager',
      ),
      OemActivityTarget(
        packageName: 'com.miui.securitycenter',
        activityName: 'com.miui.securityscan.MainActivity',
        description: 'MIUI Security Center Home',
      ),
      OemActivityTarget(
        packageName: 'com.miui.powerkeeper',
        activityName: 'com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
        description: 'HyperOS PowerKeeper Background App Config',
      ),
    ],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.miui.powerkeeper',
        activityName: 'com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
        description: 'Battery Saver - Select "No restrictions"',
      ),
      OemActivityTarget(
        packageName: 'com.miui.securitycenter',
        activityName: 'com.miui.powercenter.PowerSettings',
        description: 'MIUI Power Settings',
      ),
    ],
    secondaryAppLaunchTargets: [
      OemActivityTarget(
        packageName: 'com.miui.securitycenter',
        activityName: 'com.miui.permcenter.permissions.PermissionsEditorActivity',
        description: 'MIUI Secondary Launch & Pop-up Window Permissions',
      ),
    ],
    killerComponentPackages: [
      'com.miui.securitycenter',
      'com.miui.powerkeeper',
      'com.miui.cleanmaster',
    ],
    recommendedUserActions: [
      'Enable "Autostart" in Security > Manage apps > FocusDNS.',
      'Set Battery saver to "No restrictions" (PowerKeeper).',
      'Lock FocusDNS in Recents screen (pull down and tap padlock).',
      'Disable "Turn on MIUI optimization" in Developer options if service drops.',
    ],
    requiresAutostartPermission: true,
    requiresBatteryUnrestricted: true,
    requiresRecentsLock: true,
    requiresSecondaryLaunch: true,
    defaultSurvivalScore: 20,
  );

  // ===========================================================================
  // 2. SAMSUNG (ONE UI)
  // ===========================================================================
  static const OemDeviceProfile samsung = OemDeviceProfile(
    family: OemFamily.samsung,
    displayName: 'Samsung Galaxy',
    romName: 'One UI',
    matchingManufacturers: ['samsung'],
    matchingBrands: ['samsung'],
    severity: OemKillSeverity.severe,
    autostartTargets: [
      OemActivityTarget(
        packageName: 'com.samsung.android.lool',
        activityName: 'com.samsung.android.sm.ui.battery.BatteryActivity',
        description: 'Samsung Device Care Battery Settings',
      ),
      OemActivityTarget(
        packageName: 'com.samsung.android.sm',
        activityName: 'com.samsung.android.sm.ui.battery.BatteryActivity',
        description: 'Samsung Smart Manager Battery',
      ),
      OemActivityTarget(
        packageName: 'com.samsung.android.sm_cn',
        activityName: 'com.samsung.android.sm.ui.cstyle.ram.RamActivity',
        description: 'Samsung China RAM & Autostart Manager',
      ),
    ],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.samsung.android.lool',
        activityName: 'com.samsung.android.sm.battery.ui.BatteryActivity',
        description: 'One UI Never Sleeping Apps List',
      ),
      OemActivityTarget(
        packageName: 'com.samsung.android.sm',
        activityName: 'com.samsung.android.sm.ui.battery.AppSleepListActivity',
        description: 'Exclude FocusDNS from Sleeping Apps',
      ),
    ],
    killerComponentPackages: [
      'com.samsung.android.lool',
      'com.samsung.android.sm',
      'com.samsung.android.sm_cn',
    ],
    recommendedUserActions: [
      'Add FocusDNS to "Never sleeping apps" in Settings > Battery > Background usage limits.',
      'Set App battery usage to "Unrestricted" in App info.',
      'Disable "Put unused apps to sleep" if aggressive background drops occur.',
      'Lock FocusDNS in recent apps view.',
    ],
    requiresAutostartPermission: false,
    requiresBatteryUnrestricted: true,
    requiresRecentsLock: true,
    defaultSurvivalScore: 40,
  );

  // ===========================================================================
  // 3. HUAWEI & HONOR (EMUI & MAGICOS)
  // ===========================================================================
  static const OemDeviceProfile huawei = OemDeviceProfile(
    family: OemFamily.huawei,
    displayName: 'Huawei / Honor',
    romName: 'EMUI / MagicOS',
    matchingManufacturers: ['huawei', 'honor'],
    matchingBrands: ['huawei', 'honor'],
    severity: OemKillSeverity.extreme,
    autostartTargets: [
      OemActivityTarget(
        packageName: 'com.huawei.systemmanager',
        activityName: 'com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity',
        description: 'EMUI App Launch / Startup Manager',
      ),
      OemActivityTarget(
        packageName: 'com.huawei.systemmanager',
        activityName: 'com.huawei.systemmanager.optimize.process.ProtectActivity',
        description: 'Huawei Protected Apps List',
      ),
    ],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.huawei.systemmanager',
        activityName: 'com.huawei.systemmanager.power.ui.HwPowerManagerActivity',
        description: 'Huawei Battery Manager',
      ),
    ],
    secondaryAppLaunchTargets: [
      OemActivityTarget(
        packageName: 'com.huawei.systemmanager',
        activityName: 'com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity',
        description: 'Enable Auto-launch, Secondary launch, and Run in background',
      ),
    ],
    killerComponentPackages: [
      'com.huawei.systemmanager',
      'com.huawei.powergenie',
    ],
    recommendedUserActions: [
      'Go to Settings > Battery > App launch, find FocusDNS, toggle to "Manage manually".',
      'Enable Auto-launch, Secondary launch, and Run in background.',
      'Add FocusDNS to Protected Apps.',
      'Lock FocusDNS in task manager.',
    ],
    requiresAutostartPermission: true,
    requiresBatteryUnrestricted: true,
    requiresRecentsLock: true,
    requiresSecondaryLaunch: true,
    defaultSurvivalScore: 15,
  );

  // ===========================================================================
  // 4. ONEPLUS (OXYGENOS)
  // ===========================================================================
  static const OemDeviceProfile oneplus = OemDeviceProfile(
    family: OemFamily.oneplus,
    displayName: 'OnePlus',
    romName: 'OxygenOS',
    matchingManufacturers: ['oneplus'],
    matchingBrands: ['oneplus'],
    severity: OemKillSeverity.severe,
    autostartTargets: [
      OemActivityTarget(
        packageName: 'com.oneplus.security',
        activityName: 'com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity',
        description: 'OxygenOS Chain Launch / Auto-launch',
      ),
    ],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.android.settings',
        activityName: 'com.android.settings.Settings\$HighPowerApplicationsActivity',
        description: 'Battery Optimization - Select "Don\'t optimize"',
      ),
    ],
    killerComponentPackages: [
      'com.oneplus.security',
    ],
    recommendedUserActions: [
      'Set Battery optimization for FocusDNS to "Don\'t optimize".',
      'Disable "Sleep standby optimization" in Advanced battery settings.',
      'Enable Auto-launch in Apps > Auto-launch.',
      'Lock FocusDNS in Recents screen.',
    ],
    requiresAutostartPermission: true,
    requiresBatteryUnrestricted: true,
    requiresRecentsLock: true,
    defaultSurvivalScore: 35,
  );

  // ===========================================================================
  // 5. OPPO & REALME (COLOROS & REALME UI)
  // ===========================================================================
  static const OemDeviceProfile oppo = OemDeviceProfile(
    family: OemFamily.oppo,
    displayName: 'Oppo / Realme',
    romName: 'ColorOS / Realme UI',
    matchingManufacturers: ['oppo', 'realme'],
    matchingBrands: ['oppo', 'realme'],
    severity: OemKillSeverity.severe,
    autostartTargets: [
      OemActivityTarget(
        packageName: 'com.coloros.safecenter',
        activityName: 'com.coloros.safecenter.permission.startup.StartupAppListActivity',
        description: 'ColorOS Startup App List',
      ),
      OemActivityTarget(
        packageName: 'com.coloros.safecenter',
        activityName: 'com.coloros.safecenter.startupapp.StartupAppListActivity',
        description: 'ColorOS Legacy Startup Manager',
      ),
    ],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.coloros.safecenter',
        activityName: 'com.coloros.safecenter.permission.floatwindow.FloatWindowListActivity',
        description: 'ColorOS Background Activity & Floating Window',
      ),
    ],
    killerComponentPackages: [
      'com.coloros.safecenter',
      'com.oppo.launcher',
    ],
    recommendedUserActions: [
      'Allow Auto-startup in App Management > Auto-startup apps.',
      'Enable "Allow background activity" in Battery > App battery management.',
      'Disable "Quick Freeze" for FocusDNS.',
      'Lock app in the recent tasks view.',
    ],
    requiresAutostartPermission: true,
    requiresBatteryUnrestricted: true,
    requiresRecentsLock: true,
    defaultSurvivalScore: 30,
  );

  // ===========================================================================
  // 6. VIVO & IQOO (ORIGINOS & FUNTOUCHOS)
  // ===========================================================================
  static const OemDeviceProfile vivo = OemDeviceProfile(
    family: OemFamily.vivo,
    displayName: 'Vivo / iQOO',
    romName: 'OriginOS / FuntouchOS',
    matchingManufacturers: ['vivo'],
    matchingBrands: ['vivo', 'iqoo'],
    severity: OemKillSeverity.severe,
    autostartTargets: [
      OemActivityTarget(
        packageName: 'com.vivo.permissionmanager',
        activityName: 'com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
        description: 'Vivo Background Start Manager',
      ),
      OemActivityTarget(
        packageName: 'com.iqoo.secure',
        activityName: 'com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity',
        description: 'iQOO Speedup Whitelist',
      ),
    ],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.vivo.abe',
        activityName: 'com.vivo.applicationbehaviorengine.ui.ExcessivePowerManagerActivity',
        description: 'Vivo High Background Power Consumption Exemption',
      ),
    ],
    killerComponentPackages: [
      'com.vivo.permissionmanager',
      'com.iqoo.secure',
      'com.vivo.abe',
    ],
    recommendedUserActions: [
      'Turn on "Autostart" in Settings > More Settings > Applications > Autostart.',
      'Allow "High background power consumption" in Battery settings.',
      'Lock FocusDNS in background task manager.',
    ],
    requiresAutostartPermission: true,
    requiresBatteryUnrestricted: true,
    requiresRecentsLock: true,
    defaultSurvivalScore: 25,
  );

  // ===========================================================================
  // 7. ASUS (ZENUI & ROG UI)
  // ===========================================================================
  static const OemDeviceProfile asus = OemDeviceProfile(
    family: OemFamily.asus,
    displayName: 'Asus / ROG',
    romName: 'ZenUI / ROG UI',
    matchingManufacturers: ['asus'],
    matchingBrands: ['asus'],
    severity: OemKillSeverity.aggressive,
    autostartTargets: [
      OemActivityTarget(
        packageName: 'com.asus.mobilemanager',
        activityName: 'com.asus.mobilemanager.autostart.AutoStartActivity',
        description: 'Asus Mobile Manager Auto-Start',
      ),
      OemActivityTarget(
        packageName: 'com.asus.mobilemanager',
        activityName: 'com.asus.mobilemanager.entry.FunctionActivity',
        description: 'Asus PowerMaster Management',
      ),
    ],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.asus.mobilemanager',
        activityName: 'com.asus.mobilemanager.powersaver.PowerSaverSettings',
        description: 'Asus PowerSaver Settings',
      ),
    ],
    killerComponentPackages: [
      'com.asus.mobilemanager',
    ],
    recommendedUserActions: [
      'Enable FocusDNS in Auto-start Manager.',
      'Disable PowerMaster clean-up in suspend mode.',
    ],
    requiresAutostartPermission: true,
    requiresBatteryUnrestricted: true,
    defaultSurvivalScore: 50,
  );

  // ===========================================================================
  // 8. SONY (XPERIA)
  // ===========================================================================
  static const OemDeviceProfile sony = OemDeviceProfile(
    family: OemFamily.sony,
    displayName: 'Sony Xperia',
    romName: 'Xperia UI',
    matchingManufacturers: ['sony'],
    matchingBrands: ['sony'],
    severity: OemKillSeverity.moderate,
    autostartTargets: [],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.sonymobile.superstamina',
        activityName: 'com.sonymobile.superstamina.XperiaBatteryOptimizationActivity',
        description: 'Sony STAMINA Mode Whitelist',
      ),
    ],
    killerComponentPackages: [
      'com.sonymobile.superstamina',
    ],
    recommendedUserActions: [
      'Add FocusDNS to STAMINA mode whitelist in Settings > Battery.',
      'Grant unrestricted battery optimization.',
    ],
    requiresAutostartPermission: false,
    requiresBatteryUnrestricted: true,
    defaultSurvivalScore: 65,
  );

  // ===========================================================================
  // 9. MOTOROLA & LENOVO
  // ===========================================================================
  static const OemDeviceProfile motorola = OemDeviceProfile(
    family: OemFamily.motorola,
    displayName: 'Motorola / Lenovo',
    romName: 'My UX',
    matchingManufacturers: ['motorola', 'lenovo'],
    matchingBrands: ['motorola', 'lenovo', 'moto'],
    severity: OemKillSeverity.moderate,
    autostartTargets: [],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.motorola.ccc.ota',
        activityName: 'com.motorola.ccc.ota.BatteryOptimizationActivity',
        description: 'Moto Battery Optimization',
      ),
    ],
    killerComponentPackages: [],
    recommendedUserActions: [
      'Set Battery usage to Unrestricted.',
      'Disable Adaptive battery optimization for FocusDNS.',
    ],
    requiresAutostartPermission: false,
    requiresBatteryUnrestricted: true,
    defaultSurvivalScore: 75,
  );

  // ===========================================================================
  // 10. TRANSSION (TECNO, INFINIX, ITEL)
  // ===========================================================================
  static const OemDeviceProfile transsion = OemDeviceProfile(
    family: OemFamily.transsion,
    displayName: 'Tecno / Infinix / Itel',
    romName: 'HiOS / XOS / itelOS',
    matchingManufacturers: ['transsion', 'tecno', 'infinix', 'itel'],
    matchingBrands: ['tecno', 'infinix', 'itel'],
    severity: OemKillSeverity.severe,
    autostartTargets: [
      OemActivityTarget(
        packageName: 'com.transsion.phonemaster',
        activityName: 'com.cyin.himgr.autostart.AutoStartActivity',
        description: 'Phone Master Auto-Start Management',
      ),
    ],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.transsion.phonemaster',
        activityName: 'com.cyin.himgr.batterysave.BatterySaveActivity',
        description: 'Phone Master Battery Saver',
      ),
    ],
    killerComponentPackages: [
      'com.transsion.phonemaster',
    ],
    recommendedUserActions: [
      'Open Phone Master > Auto-start management, toggle FocusDNS ON.',
      'Set FocusDNS to Unrestricted in Battery optimization.',
      'Lock in task switcher.',
    ],
    requiresAutostartPermission: true,
    requiresBatteryUnrestricted: true,
    requiresRecentsLock: true,
    defaultSurvivalScore: 30,
  );

  // ===========================================================================
  // 11. NOTHING PHONE
  // ===========================================================================
  static const OemDeviceProfile nothing = OemDeviceProfile(
    family: OemFamily.nothing,
    displayName: 'Nothing Phone',
    romName: 'Nothing OS',
    matchingManufacturers: ['nothing'],
    matchingBrands: ['nothing'],
    severity: OemKillSeverity.moderate,
    autostartTargets: [],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.android.settings',
        activityName: 'com.android.settings.Settings\$HighPowerApplicationsActivity',
        description: 'Nothing OS Battery Optimization',
      ),
    ],
    killerComponentPackages: [],
    recommendedUserActions: [
      'Set App battery usage to "Unrestricted".',
      'Lock FocusDNS in Recents screen.',
    ],
    requiresAutostartPermission: false,
    requiresBatteryUnrestricted: true,
    defaultSurvivalScore: 80,
  );

  // ===========================================================================
  // 12. GOOGLE PIXEL & STOCK AOSP
  // ===========================================================================
  static const OemDeviceProfile pixel = OemDeviceProfile(
    family: OemFamily.pixel,
    displayName: 'Google Pixel / Stock Android',
    romName: 'Pixel UI / Stock AOSP',
    matchingManufacturers: ['google'],
    matchingBrands: ['google', 'pixel'],
    severity: OemKillSeverity.standard,
    autostartTargets: [],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.android.settings',
        activityName: 'com.android.settings.Settings\$HighPowerApplicationsActivity',
        description: 'Standard Android Battery Optimization',
      ),
    ],
    killerComponentPackages: [],
    recommendedUserActions: [
      'Set App battery usage to "Unrestricted" in App info > Battery.',
      'Standard Android Doze will respect FocusDNS Foreground VPN service.',
    ],
    requiresAutostartPermission: false,
    requiresBatteryUnrestricted: true,
    requiresRecentsLock: false,
    defaultSurvivalScore: 90,
  );

  /// Default fallback profile for unidentified Android devices.
  static const OemDeviceProfile genericAosp = OemDeviceProfile(
    family: OemFamily.genericAosp,
    displayName: 'Generic Android',
    romName: 'AOSP',
    matchingManufacturers: [],
    matchingBrands: [],
    severity: OemKillSeverity.standard,
    autostartTargets: [],
    batteryOptimizationTargets: [
      OemActivityTarget(
        packageName: 'com.android.settings',
        activityName: 'com.android.settings.Settings\$HighPowerApplicationsActivity',
        description: 'Standard Android Battery Optimization',
      ),
    ],
    killerComponentPackages: [],
    recommendedUserActions: [
      'Grant Battery Optimization exemption ("Don\'t optimize" or "Unrestricted").',
    ],
    requiresAutostartPermission: false,
    requiresBatteryUnrestricted: true,
    requiresRecentsLock: false,
    defaultSurvivalScore: 70,
  );

  /// All 12 curated OEM profiles in prioritized detection order.
  static const List<OemDeviceProfile> allProfiles = [
    xiaomi,
    samsung,
    huawei,
    oneplus,
    oppo,
    vivo,
    asus,
    sony,
    motorola,
    transsion,
    nothing,
    pixel,
  ];

  /// Resolves the device profile matching manufacturer and brand strings.
  static OemDeviceProfile resolveProfile({
    required String manufacturer,
    required String brand,
  }) {
    for (final profile in allProfiles) {
      if (profile.matchesDevice(manufacturer: manufacturer, brand: brand)) {
        return profile;
      }
    }
    return genericAosp;
  }
}
