import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/frontend/audit/distraction_audit_sheet.dart';
import 'package:focus_dns/frontend/theme/wabi_sabi_theme.dart';
import 'package:focus_dns/models/app_audit_models.dart';
import 'package:focus_dns/state_management/app_audit_state.dart';
import 'package:focus_dns/state_management/deep_focus_state.dart';

void main() {
  testWidgets('DistractionAuditSheet displays forensic grade, apps and 1-Tap Block button',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('focus_dns/audit_scanner'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'scanDeviceApps') {
          return {
            'totalScanned': 5,
            'playStoreVerifiedCount': 5,
            'distractionCount': 4,
            'auditGrade': 'C',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'apps': [
              {
                'packageName': 'com.instagram.android',
                'appName': 'Instagram',
                'installerPackage': 'com.android.vending',
                'isPlayStoreVerified': true,
                'isSystemApp': false,
                'category': 'social',
                'distractionScore': 98,
                'isDistraction': true,
                'installTimeMs': 1672531199000,
                'lastUpdateTimeMs': 1672531199000,
                'targetSdkVersion': 34,
                'versionName': '315.0.0.0',
                'associatedDomains': ['instagram.com'],
              },
              {
                'packageName': 'com.google.android.youtube',
                'appName': 'YouTube',
                'installerPackage': 'com.android.vending',
                'isPlayStoreVerified': true,
                'isSystemApp': false,
                'category': 'video',
                'distractionScore': 95,
                'isDistraction': true,
                'installTimeMs': 1672531199000,
                'lastUpdateTimeMs': 1672531199000,
                'targetSdkVersion': 34,
                'versionName': '19.10.35',
                'associatedDomains': ['youtube.com'],
              },
              {
                'packageName': 'com.reddit.frontpage',
                'appName': 'Reddit',
                'installerPackage': 'com.android.vending',
                'isPlayStoreVerified': true,
                'isSystemApp': false,
                'category': 'social',
                'distractionScore': 90,
                'isDistraction': true,
                'installTimeMs': 1672531199000,
                'lastUpdateTimeMs': 1672531199000,
                'targetSdkVersion': 34,
                'versionName': '2024.12.0',
                'associatedDomains': ['reddit.com'],
              },
              {
                'packageName': 'com.roblox.client',
                'appName': 'Roblox',
                'installerPackage': 'com.android.vending',
                'isPlayStoreVerified': true,
                'isSystemApp': false,
                'category': 'gaming',
                'distractionScore': 92,
                'isDistraction': true,
                'installTimeMs': 1672531199000,
                'lastUpdateTimeMs': 1672531199000,
                'targetSdkVersion': 34,
                'versionName': '2.615.524',
                'associatedDomains': ['roblox.com'],
              },
            ],
          };
        }
        return null;
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: WabiSabiTheme.darkTheme,
          home: const Scaffold(
            body: DistractionAuditSheet(),
          ),
        ),
      ),
    );

    final container = ProviderScope.containerOf(
        tester.element(find.byType(DistractionAuditSheet)));
    await container.read(appAuditProvider.notifier).runScan();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Title & header badges
    expect(find.text('Distraction Audit Scanner'), findsOneWidget);
    expect(find.text('Google Play Store Cross-Verified'), findsOneWidget);

    // Should render forensic grade & verified metrics
    expect(find.text('Distraction Exposure Grade'), findsOneWidget);
    expect(find.textContaining('High Distractions'), findsOneWidget);
    expect(find.textContaining('verified user apps scanned'), findsOneWidget);

    // Verify Category Filter Chips
    expect(find.textContaining('All Apps'), findsOneWidget);
    expect(find.text('Distractions (4)'), findsOneWidget);
    expect(find.text('Social Media'), findsWidgets);
    expect(find.text('Streaming'), findsWidgets);
    expect(find.text('Games'), findsWidgets);

    // Verify Play Store Apps rendered
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Reddit'), findsOneWidget);
    expect(find.text('Roblox'), findsOneWidget);

    // Verify 1-Tap Block Action Button exists
    expect(find.textContaining('1-TAP BLOCK'), findsOneWidget);

    // Tap 1-Tap Block button
    await tester.tap(find.textContaining('1-TAP BLOCK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
