import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/frontend/auth/phone_auth_screen.dart';
import 'package:focus_dns/frontend/auth/views/otp_verification_view.dart';
import 'package:focus_dns/frontend/auth/views/profile_setup_view.dart';
import 'package:focus_dns/state_management/auth_state.dart';
import 'package:focus_dns/state_management/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _captureWidget(WidgetTester tester, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final image = await boundary.toImage(pixelRatio: 2.0);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final pngBytes = byteData!.buffer.asUint8List();
  File(path).writeAsBytesSync(pngBytes);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Capture Step 2 OTP Verification View', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) {
            final notifier = AuthNotifier(ref.watch(apiClientProvider));
            notifier.state = notifier.state.copyWith(
              currentStep: AuthStep.otpVerification,
              phoneNumber: '+1 (555) 019-2834',
              devOtp: '123456',
            );
            return notifier;
          }),
        ],
        child: const MaterialApp(
          home: RepaintBoundary(
            child: PhoneAuthScreen(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await _captureWidget(tester, '/home/ya5/Downloads/chrome_onboarding_step2_otp.png');
  });

  testWidgets('Capture Step 3 Profile Setup View', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) {
            final notifier = AuthNotifier(ref.watch(apiClientProvider));
            notifier.state = notifier.state.copyWith(
              currentStep: AuthStep.profileSetup,
              phoneNumber: '+1 (555) 019-2834',
              activeProfileName: 'Deep Focus Rig',
            );
            return notifier;
          }),
        ],
        child: const MaterialApp(
          home: RepaintBoundary(
            child: PhoneAuthScreen(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await _captureWidget(tester, '/home/ya5/Downloads/chrome_onboarding_step3_profile.png');
  });
}
