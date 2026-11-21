import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/profile/fleet_device_model.dart';
import 'package:focus_dns/engine/profile/cross_device_sync_coordinator.dart';

void main() {
  group('Cross-Device Sync Coordinator Tests', () {
    late CrossDeviceSyncCoordinator coordinator;

    setUp(() {
      coordinator = CrossDeviceSyncCoordinator(
        userId: 'usr_test_123',
        localDeviceId: 'dev_pixel8_pro',
      );
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('1. Start transitions coordinator to connected status with seeded fleet', () async {
      coordinator.start();
      expect(coordinator.status, equals(CrossDeviceSyncStatus.connecting));

      await Future.delayed(const Duration(milliseconds: 350));
      expect(coordinator.status, equals(CrossDeviceSyncStatus.connected));
      expect(coordinator.fleetDevices.length, greaterThanOrEqualTo(2));

      final chromeExt = coordinator.fleetDevices.firstWhere(
        (d) => d.platform == FleetPlatformType.chromeExtension,
      );
      expect(chromeExt.isOnline, isTrue);
      expect(chromeExt.clientVersion, equals('2.0.0'));
    });

    test('2. Broadcast focus lock propagates strict mode and remaining time across fleet', () async {
      coordinator.start();
      await Future.delayed(const Duration(milliseconds: 350));

      coordinator.broadcastFocusLock(durationMinutes: 45, isStrict: true);

      for (final dev in coordinator.fleetDevices) {
        expect(dev.activeMode, equals('focus'));
        expect(dev.isStrictLockActive, isTrue);
        expect(dev.sessionRemainingSeconds, equals(45 * 60));
      }
    });

    test('3. Broadcast break transitions all nodes to break mode', () async {
      coordinator.start();
      await Future.delayed(const Duration(milliseconds: 350));

      coordinator.broadcastBreak(breakMinutes: 5);

      for (final dev in coordinator.fleetDevices) {
        expect(dev.activeMode, equals('break'));
        expect(dev.sessionRemainingSeconds, equals(5 * 60));
      }
    });

    test('4. Incoming remote fleet event updates coordinator stream', () async {
      coordinator.start();
      await Future.delayed(const Duration(milliseconds: 350));

      RemoteFleetEvent? capturedEvent;
      final sub = coordinator.eventStream.listen((ev) {
        capturedEvent = ev;
      });

      coordinator.simulateIncomingRemoteEvent({
        'type': 'TRIGGER_FOCUS_LOCK',
        'durationMinutes': 50,
        'isStrict': true,
        'originDeviceId': 'remote_laptop_ext',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      await Future.delayed(const Duration(milliseconds: 50));
      expect(capturedEvent, isNotNull);
      expect(capturedEvent?.eventType, equals('TRIGGER_FOCUS_LOCK'));
      expect(capturedEvent?.originDeviceId, equals('remote_laptop_ext'));

      for (final dev in coordinator.fleetDevices) {
        expect(dev.sessionRemainingSeconds, equals(50 * 60));
      }

      await sub.cancel();
    });

    test('5. Fleet device model formattedRemainingTime renders MM:SS', () {
      final dev = FleetDeviceModel(
        deviceId: 'd1',
        deviceName: 'MacBook',
        platform: FleetPlatformType.macos,
        clientVersion: '2.0.0',
        lastHeartbeat: DateTime.now(),
        isOnline: true,
        activeMode: 'focus',
        isStrictLockActive: true,
        sessionRemainingSeconds: 125, // 2m 5s
        distractionsBlockedToday: 10,
        minutesReclaimedToday: 15,
      );

      expect(dev.formattedRemainingTime, equals('02:05'));
    });
  });
}
