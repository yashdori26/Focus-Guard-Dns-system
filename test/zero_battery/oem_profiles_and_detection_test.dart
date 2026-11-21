import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/daemon/oem/oem_device_profiles.dart';
import 'package:focus_dns/engine/daemon/oem/oem_registry.dart';
import 'package:focus_dns/engine/daemon/oem/oem_troubleshooting_guides.dart';

void main() {
  group('1. OEM Device Profiles & Catalog Integrity Tests', () {
    test('All 12 OEM profiles are defined with non-empty metadata', () {
      expect(OemDeviceProfiles.allProfiles.length, equals(12));

      for (final profile in OemDeviceProfiles.allProfiles) {
        expect(profile.displayName, isNotEmpty);
        expect(profile.romName, isNotEmpty);
        expect(profile.recommendedUserActions, isNotEmpty);
        expect(profile.defaultSurvivalScore, inInclusiveRange(10, 95));
      }
    });

    test('OEM profile JSON serialization round-trip', () {
      final profile = OemDeviceProfiles.xiaomi;
      final json = profile.toJson();
      expect(json['family'], equals('xiaomi'));
      expect(json['severity'], equals('extreme'));
      expect((json['autostartTargets'] as List).length, greaterThanOrEqualTo(2));
    });

    test('OemActivityTarget JSON serialization round-trip', () {
      final target = profileTarget();
      final json = target.toJson();
      final reconstructed = OemActivityTarget.fromJson(json);

      expect(reconstructed.packageName, equals(target.packageName));
      expect(reconstructed.activityName, equals(target.activityName));
      expect(reconstructed.action, equals(target.action));
      expect(reconstructed.description, equals(target.description));
    });

    test('Resolves Xiaomi / Redmi / POCO devices accurately', () {
      final xiaomi = OemDeviceProfiles.resolveProfile(manufacturer: 'Xiaomi', brand: 'Redmi');
      expect(xiaomi.family, equals(OemFamily.xiaomi));
      expect(xiaomi.severity, equals(OemKillSeverity.extreme));
      expect(xiaomi.requiresAutostartPermission, isTrue);

      final poco = OemDeviceProfiles.resolveProfile(manufacturer: 'Xiaomi', brand: 'POCO');
      expect(poco.family, equals(OemFamily.xiaomi));
    });

    test('Resolves Samsung Galaxy devices accurately', () {
      final samsung = OemDeviceProfiles.resolveProfile(manufacturer: 'Samsung', brand: 'Samsung');
      expect(samsung.family, equals(OemFamily.samsung));
      expect(samsung.severity, equals(OemKillSeverity.severe));
      expect(samsung.requiresRecentsLock, isTrue);
    });

    test('Resolves Huawei / Honor devices accurately', () {
      final huawei = OemDeviceProfiles.resolveProfile(manufacturer: 'HUAWEI', brand: 'HUAWEI');
      expect(huawei.family, equals(OemFamily.huawei));
      expect(huawei.severity, equals(OemKillSeverity.extreme));

      final honor = OemDeviceProfiles.resolveProfile(manufacturer: 'Honor', brand: 'Honor');
      expect(honor.family, equals(OemFamily.huawei));
    });

    test('Resolves OnePlus, Oppo and Vivo accurately', () {
      final oneplus = OemDeviceProfiles.resolveProfile(manufacturer: 'OnePlus', brand: 'OnePlus');
      expect(oneplus.family, equals(OemFamily.oneplus));

      final oppo = OemDeviceProfiles.resolveProfile(manufacturer: 'OPPO', brand: 'OPPO');
      expect(oppo.family, equals(OemFamily.oppo));

      final vivo = OemDeviceProfiles.resolveProfile(manufacturer: 'vivo', brand: 'vivo');
      expect(vivo.family, equals(OemFamily.vivo));
    });

    test('Resolves Asus, Sony, Motorola, Transsion, Nothing and Pixel', () {
      expect(OemDeviceProfiles.resolveProfile(manufacturer: 'Asus', brand: 'Asus').family, equals(OemFamily.asus));
      expect(OemDeviceProfiles.resolveProfile(manufacturer: 'Sony', brand: 'Sony').family, equals(OemFamily.sony));
      expect(OemDeviceProfiles.resolveProfile(manufacturer: 'Motorola', brand: 'Moto').family, equals(OemFamily.motorola));
      expect(OemDeviceProfiles.resolveProfile(manufacturer: 'Transsion', brand: 'Tecno').family, equals(OemFamily.transsion));
      expect(OemDeviceProfiles.resolveProfile(manufacturer: 'Nothing', brand: 'Nothing').family, equals(OemFamily.nothing));
      expect(OemDeviceProfiles.resolveProfile(manufacturer: 'Google', brand: 'Pixel').family, equals(OemFamily.pixel));
    });

    test('Unidentified brand falls back to Generic AOSP profile', () {
      final fallback = OemDeviceProfiles.resolveProfile(manufacturer: 'CustomLinuxPhone', brand: 'CustomOS');
      expect(fallback.family, equals(OemFamily.genericAosp));
      expect(fallback.defaultSurvivalScore, equals(70));
    });
  });

  group('2. OEM Troubleshooting Guides Integrity Tests', () {
    test('Every OEM family resolves a valid troubleshooting guide', () {
      for (final family in OemFamily.values) {
        final guide = OemTroubleshootingGuides.getGuide(family);
        expect(guide.headline, isNotEmpty);
        expect(guide.introWarning, isNotEmpty);
        expect(guide.steps, isNotEmpty);
        expect(guide.totalPotentialScore, greaterThan(0));
      }
    });

    test('Xiaomi troubleshooting guide provides 3 distinct hardening steps', () {
      final guide = OemTroubleshootingGuides.xiaomi;
      expect(guide.steps.length, equals(3));
      expect(guide.steps[0].actionButtonLabel, contains('AUTOSTART'));
      expect(guide.steps[1].actionButtonLabel, contains('BATTERY SAVER'));
      expect(guide.steps[2].actionButtonLabel, contains('OTHER PERMISSIONS'));
      expect(guide.developerOptionsTip, contains('MIUI optimization'));
    });

    test('OemSetupStep JSON serialization round-trip', () {
      final step = OemTroubleshootingGuides.xiaomi.steps.first;
      final json = step.toJson();
      expect(json['stepNumber'], equals(1));
      expect(json['survivalScoreImpact'], equals(35));
    });
  });

  group('3. OEM Registry Hardware Probe Tests', () {
    test('OemRegistry computes survivability score correctly for unshielded device', () {
      final probe = DeviceHardwareProbe.mockXiaomi();
      final registry = OemRegistry(initialProbe: probe);

      expect(registry.probe.manufacturer, equals('Xiaomi'));
      expect(registry.currentProfile.family, equals(OemFamily.xiaomi));
      expect(registry.calculateSurvivabilityScore(), equals(20)); // Base score when unshielded
    });

    test('OemRegistry boosts survivability score when exemptions are granted', () {
      const probe = DeviceHardwareProbe(
        manufacturer: 'Xiaomi',
        brand: 'Redmi',
        model: 'Redmi Note 13',
        hardware: 'garnet',
        buildFingerprint: 'xiaomi/garnet',
        romVersion: 'HyperOS 1.0',
        sdkInt: 34,
        isDozeExempted: true, // +30
        isAutostartGranted: true, // +25
        isLockedInRecents: true, // +15
      );
      final registry = OemRegistry(initialProbe: probe);

      // Base 20 + 30 + 25 + 15 = 90
      expect(registry.calculateSurvivabilityScore(), equals(90));
    });

    test('Google Pixel probe yields high default score', () {
      final probe = DeviceHardwareProbe.mockGeneric();
      final registry = OemRegistry(initialProbe: probe);

      expect(registry.calculateSurvivabilityScore(), inInclusiveRange(90, 100));
    });
  });
}

OemActivityTarget profileTarget() => const OemActivityTarget(
      packageName: 'com.test.oem',
      activityName: 'com.test.oem.MainActivity',
      action: 'android.intent.action.MAIN',
      description: 'Test target',
    );
