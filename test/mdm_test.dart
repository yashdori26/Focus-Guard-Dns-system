import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/mdm_service.dart';

void main() {
  group('FocusMdmManager Unit Tests', () {
    setUp(() {
      // Reset simulation state
      FocusMdmManager.setSimulatedProtection(false);
      FocusMdmManager.setSimulatedTimer(0);
    });

    test('Initial idle state permits uninstallation and admin deactivation', () async {
      final status = await FocusMdmManager.getLockStatus();

      expect(status.sessionState, 'IDLE');
      expect(status.isProtectionActive, false);
      expect(status.isTimerActive, false);
      expect(status.remainingSeconds, 0);
      expect(status.canUninstall, true);
      expect(status.canDeactivateAdmin, true);

      final canUn = await FocusMdmManager.canUninstall();
      expect(canUn, true);
    });

    test('Active Protection Mode strictly locks uninstallation', () async {
      FocusMdmManager.setSimulatedProtection(true);

      final status = await FocusMdmManager.getLockStatus();
      expect(status.sessionState, 'PROTECTION_ONLY');
      expect(status.isProtectionActive, true);
      expect(status.canUninstall, false);
      expect(status.canDeactivateAdmin, false);

      final canUn = await FocusMdmManager.canUninstall();
      expect(canUn, false);

      // Deactivation must be rejected while protection is active
      final deactivated = await FocusMdmManager.deactivateDeviceAdmin();
      expect(deactivated, false);
    });

    test('Active Countdown Timer strictly locks uninstallation even if protection is off', () async {
      FocusMdmManager.setSimulatedProtection(false);
      FocusMdmManager.setSimulatedTimer(1800); // 30 minutes

      final status = await FocusMdmManager.getLockStatus();
      expect(status.sessionState, 'TIMER_ACTIVE');
      expect(status.isTimerActive, true);
      expect(status.remainingSeconds, 1800);
      expect(status.formattedRemainingTime, '30:00');
      expect(status.canUninstall, false);
      expect(status.canDeactivateAdmin, false);

      final canUn = await FocusMdmManager.canUninstall();
      expect(canUn, false);
    });

    test('Both Protection ON and Timer ON completely locks session', () async {
      FocusMdmManager.setSimulatedProtection(true);
      FocusMdmManager.setSimulatedTimer(900); // 15 minutes

      final status = await FocusMdmManager.getLockStatus();
      expect(status.sessionState, 'LOCKED_PROTECTED');
      expect(status.isProtectionActive, true);
      expect(status.isTimerActive, true);
      expect(status.canUninstall, false);
      expect(status.canDeactivateAdmin, false);
    });

    test('Uninstallation unlocks naturally once timer expires and protection is turned off', () async {
      FocusMdmManager.setSimulatedProtection(true);
      FocusMdmManager.setSimulatedTimer(60);

      // Initially locked
      expect(await FocusMdmManager.canUninstall(), false);

      // Timer finishes
      FocusMdmManager.setSimulatedTimer(0);
      // Still locked because protection is on
      expect(await FocusMdmManager.canUninstall(), false);

      // Protection is turned off
      FocusMdmManager.setSimulatedProtection(false);
      // Now completely unlocked!
      expect(await FocusMdmManager.canUninstall(), true);

      final status = await FocusMdmManager.getLockStatus();
      expect(status.sessionState, 'IDLE');
      expect(status.canUninstall, true);
      expect(status.canDeactivateAdmin, true);
    });

    test('Split Tunneling App list management', () async {
      final initialApps = await FocusMdmManager.getSplitTunnelApps();
      expect(initialApps.isNotEmpty, true);

      // Select banking app
      final selected = ['com.google.android.apps.nbu.paisa.user', 'com.sbi.lotusintouch'];
      final success = await FocusMdmManager.setSplitTunnelPackages(selected);
      expect(success, true);

      final updatedApps = await FocusMdmManager.getSplitTunnelApps();
      final gpay = updatedApps.firstWhere((a) => a.packageName == 'com.google.android.apps.nbu.paisa.user');
      expect(gpay.isSelected, true);

      final chrome = updatedApps.firstWhere((a) => a.packageName == 'com.android.chrome');
      expect(chrome.isSelected, false);
    });

    test('Device Admin activation and deactivation flow', () async {
      expect(await FocusMdmManager.isDeviceAdminActive(), false);

      final enrolled = await FocusMdmManager.requestDeviceAdmin();
      expect(enrolled, true);
      expect(await FocusMdmManager.isDeviceAdminActive(), true);

      // Deactivate while idle succeeds
      final deactivated = await FocusMdmManager.deactivateDeviceAdmin();
      expect(deactivated, true);
      expect(await FocusMdmManager.isDeviceAdminActive(), false);
    });
  });
}
