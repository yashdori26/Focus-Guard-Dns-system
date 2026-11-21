import 'package:flutter/material.dart';
import 'oem_device_profiles.dart';

/// Represents a single actionable step in the OEM resilience setup guide.
@immutable
class OemSetupStep {
  final int stepNumber;
  final String title;
  final String instructions;
  final String settingPath;
  final IconData icon;
  final String actionButtonLabel;
  final bool isMandatory;
  final int survivalScoreImpact;

  const OemSetupStep({
    required this.stepNumber,
    required this.title,
    required this.instructions,
    required this.settingPath,
    required this.icon,
    required this.actionButtonLabel,
    this.isMandatory = true,
    required this.survivalScoreImpact,
  });

  Map<String, dynamic> toJson() => {
        'stepNumber': stepNumber,
        'title': title,
        'instructions': instructions,
        'settingPath': settingPath,
        'actionButtonLabel': actionButtonLabel,
        'isMandatory': isMandatory,
        'survivalScoreImpact': survivalScoreImpact,
      };
}

/// Complete guide document for an OEM manufacturer.
@immutable
class OemTroubleshootingGuide {
  final OemFamily family;
  final String headline;
  final String introWarning;
  final List<OemSetupStep> steps;
  final String recentsLockInstructions;
  final String developerOptionsTip;

  const OemTroubleshootingGuide({
    required this.family,
    required this.headline,
    required this.introWarning,
    required this.steps,
    required this.recentsLockInstructions,
    required this.developerOptionsTip,
  });

  int get totalPotentialScore => steps.fold(0, (sum, s) => sum + s.survivalScoreImpact);
}

/// Comprehensive registry of step-by-step troubleshooting guides for all OEM ecosystems.
class OemTroubleshootingGuides {
  OemTroubleshootingGuides._();

  // ===========================================================================
  // 1. XIAOMI / REDMI / POCO
  // ===========================================================================
  static const OemTroubleshootingGuide xiaomi = OemTroubleshootingGuide(
    family: OemFamily.xiaomi,
    headline: 'HyperOS & MIUI Background Persistence Guide',
    introWarning:
        'Xiaomi devices feature aggressive memory cleanup (PowerKeeper) that kills background VPN services within minutes unless explicitly exempted.',
    steps: [
      OemSetupStep(
        stepNumber: 1,
        title: 'Grant Autostart Permission',
        instructions:
            'Xiaomi prevents apps from starting on boot or receiving alarms without this permission. Enable Autostart for FocusDNS.',
        settingPath: 'Settings > Apps > Manage apps > FocusDNS > Autostart',
        icon: Icons.power_settings_new_rounded,
        actionButtonLabel: 'OPEN AUTOSTART SETTINGS',
        survivalScoreImpact: 35,
      ),
      OemSetupStep(
        stepNumber: 2,
        title: 'Set Battery Saver to "No Restrictions"',
        instructions:
            'MIUI PowerKeeper terminates background tasks when screen turns off. Select "No restrictions" so DNS filtering runs unthrottled.',
        settingPath: 'Settings > Apps > Manage apps > FocusDNS > Battery saver > No restrictions',
        icon: Icons.battery_saver_rounded,
        actionButtonLabel: 'OPEN BATTERY SAVER',
        survivalScoreImpact: 30,
      ),
      OemSetupStep(
        stepNumber: 3,
        title: 'Enable Secondary Launch & Pop-up Windows',
        instructions:
            'Allow FocusDNS to display the floating countdown HUD over other apps and respond to scheduled timer boundaries.',
        settingPath: 'Security > Manage apps > FocusDNS > Other permissions',
        icon: Icons.layers_rounded,
        actionButtonLabel: 'OPEN OTHER PERMISSIONS',
        survivalScoreImpact: 15,
      ),
    ],
    recentsLockInstructions:
        'Open the Recent Apps view, press and hold the FocusDNS card, then tap the padlock icon to lock it in memory.',
    developerOptionsTip:
        'If background disconnects persist on MIUI 12/13, enable Developer Options and toggle off "Turn on MIUI optimization".',
  );

  // ===========================================================================
  // 2. SAMSUNG (ONE UI)
  // ===========================================================================
  static const OemTroubleshootingGuide samsung = OemTroubleshootingGuide(
    family: OemFamily.samsung,
    headline: 'Samsung One UI Background Shield Guide',
    introWarning:
        'Samsung Device Care automatically puts inactive apps into "Deep Sleeping" mode, which disables background listeners and exact alarms.',
    steps: [
      OemSetupStep(
        stepNumber: 1,
        title: 'Add to "Never Sleeping Apps"',
        instructions:
            'Prevent One UI from automatically freezing the FocusDNS daemon after periods of screen inactivity.',
        settingPath: 'Settings > Battery > Background usage limits > Never sleeping apps > Add FocusDNS',
        icon: Icons.bedtime_off_rounded,
        actionButtonLabel: 'OPEN SLEEPING APPS',
        survivalScoreImpact: 40,
      ),
      OemSetupStep(
        stepNumber: 2,
        title: 'Set Battery Usage to "Unrestricted"',
        instructions:
            'Allow FocusDNS to use battery in the background without Android Doze restrictions or CPU throttling.',
        settingPath: 'App Info > FocusDNS > Battery > Select "Unrestricted"',
        icon: Icons.bolt_rounded,
        actionButtonLabel: 'OPEN APP BATTERY SETTINGS',
        survivalScoreImpact: 20,
      ),
    ],
    recentsLockInstructions:
        'Open Recent Apps, tap the FocusDNS icon at the top of the card, and select "Keep open" or "Lock this app".',
    developerOptionsTip:
        'In Settings > Device Care > Battery > More battery settings, you can disable "Put unused apps to sleep".',
  );

  // ===========================================================================
  // 3. HUAWEI & HONOR (EMUI & MAGICOS)
  // ===========================================================================
  static const OemTroubleshootingGuide huawei = OemTroubleshootingGuide(
    family: OemFamily.huawei,
    headline: 'Huawei EMUI & MagicOS Persistence Guide',
    introWarning:
        'Huawei PowerGenie aggressively terminates third-party background services unless manual app launch management is enabled.',
    steps: [
      OemSetupStep(
        stepNumber: 1,
        title: 'Switch App Launch to "Manage Manually"',
        instructions:
            'Find FocusDNS in the App Launch list, toggle off "Manage automatically", and enable Auto-launch, Secondary launch, and Run in background.',
        settingPath: 'Settings > Battery > App launch > FocusDNS > Manage manually',
        icon: Icons.play_arrow_rounded,
        actionButtonLabel: 'OPEN APP LAUNCH SETTINGS',
        survivalScoreImpact: 50,
      ),
      OemSetupStep(
        stepNumber: 2,
        title: 'Add to Protected Apps List',
        instructions:
            'Ensure Huawei Phone Manager exempts FocusDNS from memory cleanup during screen-off intervals.',
        settingPath: 'Optimizer / Phone Manager > Battery > Protected Apps',
        icon: Icons.shield_rounded,
        actionButtonLabel: 'OPEN PROTECTED APPS',
        survivalScoreImpact: 35,
      ),
    ],
    recentsLockInstructions:
        'In Recent tasks, swipe down on the FocusDNS card until the lock icon appears in the top right corner.',
    developerOptionsTip:
        'On EMUI devices, make sure "Ignore battery optimizations" is accepted in Phone Settings > Apps > Advanced > Ignore battery optimizations.',
  );

  // ===========================================================================
  // 4. ONEPLUS (OXYGENOS)
  // ===========================================================================
  static const OemTroubleshootingGuide oneplus = OemTroubleshootingGuide(
    family: OemFamily.oneplus,
    headline: 'OnePlus OxygenOS Background Guard',
    introWarning:
        'OxygenOS employs Sleep Standby Optimization and Quick Launch task termination that freezes background sockets during sleep.',
    steps: [
      OemSetupStep(
        stepNumber: 1,
        title: 'Set Battery Optimization to "Don\'t Optimize"',
        instructions:
            'Exempt FocusDNS from OxygenOS deep sleep and background process killing.',
        settingPath: 'Settings > Battery > Battery optimization > FocusDNS > Don\'t optimize',
        icon: Icons.battery_charging_full_rounded,
        actionButtonLabel: 'OPEN BATTERY OPTIMIZATION',
        survivalScoreImpact: 40,
      ),
      OemSetupStep(
        stepNumber: 2,
        title: 'Disable Sleep Standby Optimization',
        instructions:
            'Prevent OxygenOS from turning off network radios and background VPN routing between 11 PM and 6 AM.',
        settingPath: 'Settings > Battery > Advanced settings > Sleep standby optimization > OFF',
        icon: Icons.nights_stay_rounded,
        actionButtonLabel: 'OPEN ADVANCED BATTERY',
        survivalScoreImpact: 25,
      ),
    ],
    recentsLockInstructions:
        'In the recent tasks switcher, tap the three dots on the FocusDNS preview card and select "Lock".',
    developerOptionsTip:
        'Ensure "Auto-launch" is enabled for FocusDNS in Settings > Apps > Auto-launch.',
  );

  // ===========================================================================
  // 5. OPPO & REALME (COLOROS & REALME UI)
  // ===========================================================================
  static const OemTroubleshootingGuide oppo = OemTroubleshootingGuide(
    family: OemFamily.oppo,
    headline: 'Oppo ColorOS & Realme UI Setup Guide',
    introWarning:
        'ColorOS restricts background apps through Quick Freeze and Startup App management.',
    steps: [
      OemSetupStep(
        stepNumber: 1,
        title: 'Enable Auto-Startup & Secondary Startup',
        instructions:
            'Allow FocusDNS to start automatically and keep running in the background.',
        settingPath: 'Settings > Apps > Auto-startup > FocusDNS > ON',
        icon: Icons.autorenew_rounded,
        actionButtonLabel: 'OPEN AUTO-STARTUP',
        survivalScoreImpact: 45,
      ),
      OemSetupStep(
        stepNumber: 2,
        title: 'Allow Background Activity',
        instructions:
            'In App Battery Management, enable "Allow background activity" and disable "Auto-freeze".',
        settingPath: 'Settings > Battery > More battery settings > App battery management > FocusDNS',
        icon: Icons.bolt_rounded,
        actionButtonLabel: 'OPEN BATTERY MANAGEMENT',
        survivalScoreImpact: 25,
      ),
    ],
    recentsLockInstructions:
        'In Recent Tasks, tap the menu dots on FocusDNS card and tap "Lock" to prevent clearing.',
    developerOptionsTip:
        'In Security Center, verify Floating Window permission is granted for FocusDNS.',
  );

  // ===========================================================================
  // 6. VIVO & IQOO (ORIGINOS & FUNTOUCHOS)
  // ===========================================================================
  static const OemTroubleshootingGuide vivo = OemTroubleshootingGuide(
    family: OemFamily.vivo,
    headline: 'Vivo & iQOO Background Persistence Guide',
    introWarning:
        'FuntouchOS and OriginOS enforce severe restrictions on background power consumption and autostart.',
    steps: [
      OemSetupStep(
        stepNumber: 1,
        title: 'Enable Autostart in Permission Manager',
        instructions:
            'Allow FocusDNS to run automatically upon boot and timer trigger.',
        settingPath: 'Settings > Apps & permissions > Permission management > Autostart > FocusDNS',
        icon: Icons.power_settings_new_rounded,
        actionButtonLabel: 'OPEN AUTOSTART MANAGER',
        survivalScoreImpact: 45,
      ),
      OemSetupStep(
        stepNumber: 2,
        title: 'Allow High Background Power Consumption',
        instructions:
            'Exempt FocusDNS from Vivo automatic background shutdown.',
        settingPath: 'Settings > Battery > High background power consumption > FocusDNS > ON',
        icon: Icons.flash_on_rounded,
        actionButtonLabel: 'OPEN POWER CONSUMPTION',
        survivalScoreImpact: 30,
      ),
    ],
    recentsLockInstructions:
        'In the recent apps tray, drag the FocusDNS card down to reveal and lock the padlock icon.',
    developerOptionsTip:
        'In iManager > Speed up, ensure FocusDNS is added to the white list.',
  );

  // ===========================================================================
  // 7. ASUS (ZENUI & ROG UI)
  // ===========================================================================
  static const OemTroubleshootingGuide asus = OemTroubleshootingGuide(
    family: OemFamily.asus,
    headline: 'Asus ZenUI & ROG Phone Guide',
    introWarning:
        'Asus Mobile Manager Auto-Start manager kills non-whitelisted apps during screen standby.',
    steps: [
      OemSetupStep(
        stepNumber: 1,
        title: 'Enable in Auto-Start Manager',
        instructions:
            'Open Mobile Manager, tap Auto-start Manager, and switch FocusDNS to "Allow".',
        settingPath: 'Mobile Manager > PowerMaster > Auto-start Manager > FocusDNS > Allow',
        icon: Icons.play_circle_filled_rounded,
        actionButtonLabel: 'OPEN AUTO-START MANAGER',
        survivalScoreImpact: 50,
      ),
    ],
    recentsLockInstructions:
        'Lock FocusDNS in recent apps list by tapping the lock icon.',
    developerOptionsTip:
        'In PowerMaster > Battery saver, ensure cleanup in suspend mode is disabled.',
  );

  // ===========================================================================
  // 8. SONY (XPERIA)
  // ===========================================================================
  static const OemTroubleshootingGuide sony = OemTroubleshootingGuide(
    family: OemFamily.sony,
    headline: 'Sony Xperia STAMINA Guide',
    introWarning:
        'Sony STAMINA mode disables background data and pauses background execution during standby.',
    steps: [
      OemSetupStep(
        stepNumber: 1,
        title: 'Whitelist in STAMINA Mode',
        instructions:
            'Ensure FocusDNS is allowed to operate when STAMINA mode is active.',
        settingPath: 'Settings > Battery > STAMINA mode > Apps unaffected by STAMINA > Add FocusDNS',
        icon: Icons.shield_rounded,
        actionButtonLabel: 'OPEN STAMINA SETTINGS',
        survivalScoreImpact: 35,
      ),
    ],
    recentsLockInstructions:
        'Standard Android Recents behavior applies.',
    developerOptionsTip:
        'Keep Battery Care active without setting extreme restrictions.',
  );

  // ===========================================================================
  // 9. MOTOROLA & LENOVO
  // ===========================================================================
  static const OemTroubleshootingGuide motorola = OemTroubleshootingGuide(
    family: OemFamily.motorola,
    headline: 'Motorola Background Setup',
    introWarning:
        'Motorola devices run close to stock Android with minor Adaptive Battery throttling.',
    steps: [
      OemSetupStep(
        stepNumber: 1,
        title: 'Set Battery Usage to Unrestricted',
        instructions:
            'Prevent Adaptive Battery from pausing background filtering.',
        settingPath: 'Settings > Apps > FocusDNS > Battery > Unrestricted',
        icon: Icons.battery_full_rounded,
        actionButtonLabel: 'OPEN BATTERY USAGE',
        survivalScoreImpact: 25,
      ),
    ],
    recentsLockInstructions:
        'Locking in recents is optional on Motorola devices.',
    developerOptionsTip:
        'Adaptive battery can remain on if FocusDNS is set to Unrestricted.',
  );

  // ===========================================================================
  // 10. TRANSSION (TECNO / INFINIX / ITEL)
  // ===========================================================================
  static const OemTroubleshootingGuide transsion = OemTroubleshootingGuide(
    family: OemFamily.transsion,
    headline: 'Tecno, Infinix & Itel Phone Master Guide',
    introWarning:
        'HiOS and XOS Phone Master automatically terminates non-whitelisted apps to save RAM.',
    steps: [
      OemSetupStep(
        stepNumber: 1,
        title: 'Enable Auto-start in Phone Master',
        instructions:
            'Open Phone Master > Auto-start management, find FocusDNS and toggle ON.',
        settingPath: 'Phone Master > Toolbox > Auto-start management > FocusDNS > ON',
        icon: Icons.autorenew_rounded,
        actionButtonLabel: 'OPEN PHONE MASTER',
        survivalScoreImpact: 50,
      ),
      OemSetupStep(
        stepNumber: 2,
        title: 'Add to Battery Whitelist',
        instructions:
            'In Battery Lab, add FocusDNS to the protected apps list.',
        settingPath: 'Settings > Battery Lab > App power consumption management',
        icon: Icons.bolt_rounded,
        actionButtonLabel: 'OPEN BATTERY LAB',
        survivalScoreImpact: 20,
      ),
    ],
    recentsLockInstructions:
        'In task switcher, drag down the FocusDNS card to lock it.',
    developerOptionsTip:
        'Ensure "Power boost" does not kill FocusDNS on screen off.',
  );

  // ===========================================================================
  // 11. NOTHING PHONE
  // ===========================================================================
  static const OemTroubleshootingGuide nothing = OemTroubleshootingGuide(
    family: OemFamily.nothing,
    headline: 'Nothing OS Background Setup',
    introWarning:
        'Nothing OS is lightweight and respects foreground services with unrestricted battery enabled.',
    steps: [
      OemSetupStep(
        stepNumber: 1,
        title: 'Set Battery Usage to "Unrestricted"',
        instructions:
            'Allow FocusDNS to run without App Standby limits.',
        settingPath: 'Settings > Apps > All Apps > FocusDNS > App battery usage > Unrestricted',
        icon: Icons.battery_full_rounded,
        actionButtonLabel: 'OPEN APP BATTERY SETTINGS',
        survivalScoreImpact: 20,
      ),
    ],
    recentsLockInstructions:
        'Locking in recent apps tray is recommended for unbroken focus.',
    developerOptionsTip:
        'Standard stock AOSP rules apply.',
  );

  // ===========================================================================
  // 12. GOOGLE PIXEL & STOCK AOSP
  // ===========================================================================
  static const OemTroubleshootingGuide pixel = OemTroubleshootingGuide(
    family: OemFamily.pixel,
    headline: 'Google Pixel & Stock Android Setup',
    introWarning:
        'Stock Android provides reliable background execution for Foreground Services. Setting Unrestricted battery gives 100% reliability.',
    steps: [
      OemSetupStep(
        stepNumber: 1,
        title: 'Set App Battery Usage to "Unrestricted"',
        instructions:
            'Prevents standard Android Doze from delaying timer countdowns or socket processing when phone is stationary.',
        settingPath: 'Settings > Apps > FocusDNS > App battery usage > Unrestricted',
        icon: Icons.battery_full_rounded,
        actionButtonLabel: 'OPEN APP BATTERY SETTINGS',
        survivalScoreImpact: 10,
      ),
    ],
    recentsLockInstructions:
        'Pixel does not require locking in recents as long as notification is active.',
    developerOptionsTip:
        'No custom vendor hacks needed. FocusDNS runs at maximum efficiency.',
  );

  /// Resolves the troubleshooting guide corresponding to an OEM family.
  static OemTroubleshootingGuide getGuide(OemFamily family) {
    switch (family) {
      case OemFamily.xiaomi:
        return xiaomi;
      case OemFamily.samsung:
        return samsung;
      case OemFamily.huawei:
        return huawei;
      case OemFamily.oneplus:
        return oneplus;
      case OemFamily.oppo:
        return oppo;
      case OemFamily.vivo:
        return vivo;
      case OemFamily.asus:
        return asus;
      case OemFamily.sony:
        return sony;
      case OemFamily.motorola:
        return motorola;
      case OemFamily.transsion:
        return transsion;
      case OemFamily.nothing:
        return nothing;
      case OemFamily.pixel:
      case OemFamily.genericAosp:
        return pixel;
    }
  }
}
