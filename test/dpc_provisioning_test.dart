import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/dpc_service.dart';
import 'package:focus_dns/frontend/device_owner_provisioning_screen.dart';
import 'package:focus_dns/frontend/dpc_qr_code_widget.dart';
import 'package:focus_dns/frontend/lock_task_kiosk_card.dart';
import 'package:focus_dns/frontend/managed_config_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('focus_dns/mdm'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'isDeviceOwner') {
          return true;
        }
        if (methodCall.method == 'isProfileOwner') {
          return false;
        }
        if (methodCall.method == 'getDpcDiagnostics') {
          return {
            'isDeviceOwner': true,
            'isProfileOwner': false,
            'isEnterpriseDpcActive': true,
            'canUninstallApp': false,
            'activeRestrictions': {
              'no_uninstall_apps': true,
              'no_control_apps': true,
              'no_safe_boot': true,
              'no_config_vpn': true,
              'no_debugging_features': true,
              'no_factory_reset': true,
            },
            'coreRestrictionsEnforced': true,
          };
        }
        if (methodCall.method == 'applyConditionalFocusPolicy') {
          final isProt = methodCall.arguments['isProtected'] == true;
          return {
            'no_uninstall_apps': isProt,
            'no_safe_boot': isProt,
            'no_config_vpn': isProt,
          };
        }
        if (methodCall.method == 'setUsbDebuggingDisabled') {
          return true;
        }
        if (methodCall.method == 'startKioskMode') {
          return true;
        }
        if (methodCall.method == 'stopKioskMode') {
          return true;
        }
        if (methodCall.method == 'isKioskModeActive') {
          return false;
        }
        if (methodCall.method == 'getManagedConfiguration') {
          return {
            'serverUrl': 'https://dns.focusguard.internal',
            'tenantId': 'default_enterprise',
            'enrollmentToken': 'tok_test_123',
            'enforceStrictUninstallLock': true,
            'whitelistedPackages': ['com.slack', 'com.zoom'],
            'kioskEnabled': false,
            'approvedDotHost': 'dns.focusguard.internal',
          };
        }
        if (methodCall.method == 'triggerEmergencyCall') {
          return true;
        }
        return null;
      },
    );
  });

  group('Phase 3 DPC & Managed Config Unit Tests', () {
    test('DpcDiagnosticModel serialization', () {
      const model = DpcDiagnosticModel();
      expect(model.isDeviceOwner, isFalse);
      expect(model.canUninstallApp, isTrue);

      final map = model.toMap();
      final fromMap = DpcDiagnosticModel.fromMap(map);
      expect(fromMap.isDeviceOwner, model.isDeviceOwner);
      expect(fromMap.canUninstallApp, model.canUninstallApp);
    });

    test('ManagedConfigModel serialization', () {
      final config = ManagedConfigModel.fromMap(const {
        'serverUrl': 'https://custom.dns.org',
        'tenantId': 'tenant_abc',
        'enrollmentToken': 'token_999',
        'enforceStrictUninstallLock': true,
        'whitelistedPackages': ['com.slack'],
        'kioskEnabled': true,
        'approvedDotHost': 'dot.custom.org',
      });
      expect(config.serverUrl, 'https://custom.dns.org');
      expect(config.tenantId, 'tenant_abc');
      expect(config.enforceStrictUninstallLock, isTrue);
      expect(config.whitelistedPackages, ['com.slack']);
      expect(config.kioskEnabled, isTrue);
    });

    test('FocusDpcService operations', () async {
      final isDo = await FocusDpcService.isDeviceOwner();
      expect(isDo, isTrue);

      final diag = await FocusDpcService.getDpcDiagnostics();
      expect(diag.isDeviceOwner, isTrue);
      expect(diag.coreRestrictionsEnforced, isTrue);

      final policyRes = await FocusDpcService.applyConditionalFocusPolicy(true);
      expect(policyRes['no_uninstall_apps'], isTrue);

      final adbOk = await FocusDpcService.setUsbDebuggingDisabled(true);
      expect(adbOk, isTrue);

      final kioskStart = await FocusDpcService.startKioskMode();
      expect(kioskStart, isTrue);

      final kioskStop = await FocusDpcService.stopKioskMode();
      expect(kioskStop, isTrue);

      final cfg = await FocusDpcService.getManagedConfiguration();
      expect(cfg.serverUrl, 'https://dns.focusguard.internal');
      expect(cfg.tenantId, 'default_enterprise');
    });

    test('ZeroTouchPayloadModel serialization and deserialization', () {
      final json = {
        'android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME': 'com.focusdns.app',
        'android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME': 'com.focusdns.app/.FocusDeviceAdminReceiver',
        'android.app.extra.PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM': '4a24cd80388b818606eb02eb55b650c4035787207dd6551724d2968a07a9e163',
        'android.app.extra.PROVISIONING_WIFI_SSID': 'Enterprise-Office-WiFi',
        'android.app.extra.PROVISIONING_WIFI_PASSWORD': 'SecureWiFiPassword123!',
        'android.app.extra.PROVISIONING_WIFI_SECURITY_TYPE': 'WPA2',
        'android.app.extra.PROVISIONING_WIFI_HIDDEN': false,
        'android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE': {
          'server_url': 'https://dns.focusdns.io',
          'tenant_id': 'tenant_marketing',
          'enrollment_token': 'tok_test_abc',
          'enforce_strict_uninstall_lock': false,
        },
        'android.app.extra.PROVISIONING_LOCALE': 'en_US',
        'android.app.extra.PROVISIONING_TIME_ZONE': 'America/New_York',
        'android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED': true,
      };

      final model = FocusDpcService.parseZeroTouchPayload(json);
      expect(model.packageName, 'com.focusdns.app');
      expect(model.wifiConfig?.ssid, 'Enterprise-Office-WiFi');
      expect(model.wifiConfig?.password, 'SecureWiFiPassword123!');
      expect(model.wifiConfig?.securityType, 'WPA2');
      expect(model.wifiConfig?.hidden, isFalse);
      expect(model.adminExtras.serverUrl, 'https://dns.focusdns.io');
      expect(model.adminExtras.tenantId, 'tenant_marketing');
      // In normal mode, strict uninstallation lock is false
      expect(model.adminExtras.enforceStrictUninstallLock, isFalse);
      expect(model.leaveAllSystemAppsEnabled, isTrue);

      final outJson = model.toJson();
      expect(outJson['android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME'], 'com.focusdns.app');
      expect(outJson['android.app.extra.PROVISIONING_WIFI_SSID'], 'Enterprise-Office-WiFi');
    });

    test('FocusDpcService createDefaultZeroTouchBundle respects normal uninstallation', () {
      final defaultBundle = FocusDpcService.createDefaultZeroTouchBundle(
        tenantId: 'acme_corp',
        enforceStrictUninstallLock: false,
      );
      expect(defaultBundle.adminExtras.tenantId, 'acme_corp');
      expect(defaultBundle.adminExtras.enforceStrictUninstallLock, isFalse);
      expect(defaultBundle.packageName, 'com.focusdns.app');
    });
  });

  group('Phase 3 Widget Tests', () {
    testWidgets('DeviceOwnerProvisioningScreen renders DPC status and bundle', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: DeviceOwnerProvisioningScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enterprise DPC Provisioning'), findsOneWidget);
      expect(find.text('DEVICE OWNER (FULL DPC)'), findsOneWidget);
      expect(find.text('Inviolable Uninstallation Law'), findsOneWidget);
      expect(find.text('Zero-Touch Provisioning Bundle'), findsOneWidget);

      final copyBtn = find.text('Copy JSON');
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Android Enterprise Zero-Touch JSON copied to clipboard.'), findsOneWidget);
    });

    testWidgets('LockTaskKioskCard renders manifest and emergency dialer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LockTaskKioskCard()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dedicated LockTask (Kiosk)'), findsOneWidget);
      expect(find.text('STANDBY'), findsOneWidget);
      expect(find.textContaining('Emergency Phone Dialer'), findsOneWidget);

      final sosBtn = find.byTooltip('Emergency SOS 112');
      expect(sosBtn, findsOneWidget);
      await tester.tap(sosBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Emergency dialer launched (112 exempt).'), findsOneWidget);
    });

    testWidgets('ManagedConfigScreen renders enterprise schema and whitelisted apps', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ManagedConfigScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Managed Configurations'), findsOneWidget);
      expect(find.text('Managed by Enterprise EMM'), findsOneWidget);
      expect(find.text('Active AppConfig Schema'), findsOneWidget);
      expect(find.text('https://dns.focusguard.internal'), findsOneWidget);
      expect(find.text('default_enterprise'), findsOneWidget);
      expect(find.text('com.slack'), findsOneWidget);
      expect(find.text('com.zoom'), findsOneWidget);
    });

    testWidgets('DpcQrCodeWidget renders QR canvas painter and action buttons', (tester) async {
      final samplePayload = {
        'android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME': 'com.focusdns.app',
        'android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE': {
          'server_url': 'https://dns.focusdns.io',
          'tenant_id': 'test_corp',
        },
      };

      bool copied = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DpcQrCodeWidget(
              payload: samplePayload,
              onCopied: () => copied = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('Android Enterprise Enrollment QR'), findsOneWidget);
      expect(find.byKey(const Key('copy_qr_payload_btn')), findsOneWidget);
      expect(find.byKey(const Key('inspect_qr_payload_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('copy_qr_payload_btn')));
      await tester.pump();
      expect(copied, isTrue);
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.byKey(const Key('inspect_qr_payload_btn')));
      await tester.pumpAndSettle();
      expect(find.text('Provisioning Admin Extras'), findsOneWidget);
    });
  });
}

