import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/geofence_service.dart';
import 'package:focus_dns/backend/schedule_service.dart';
import 'package:focus_dns/frontend/geofence_screen.dart';
import 'package:focus_dns/frontend/enterprise_schedule_screen.dart';
import 'package:focus_dns/frontend/device_policy_audit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('focus_dns/geofence'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('focus_dns/schedule'),
      (call) async => null,
    );
  });

  group('Geofence Models & Service Unit Tests', () {
    test('GeofenceZoneModel fromMap and toMap serialization', () {
      final map = {
        'zoneId': 'geo_campus_01',
        'name': 'University Engineering Quad',
        'latitude': 37.8720,
        'longitude': -122.2580,
        'radiusMeters': 180.0,
        'enforceLock': true,
        'description': 'Restricted study quad with locked uninstallation',
      };

      final model = GeofenceZoneModel.fromMap(map);
      expect(model.zoneId, 'geo_campus_01');
      expect(model.name, 'University Engineering Quad');
      expect(model.latitude, 37.8720);
      expect(model.longitude, -122.2580);
      expect(model.radiusMeters, 180.0);
      expect(model.enforceLock, isTrue);
      expect(model.description, 'Restricted study quad with locked uninstallation');

      final serialized = model.toMap();
      expect(serialized['zoneId'], 'geo_campus_01');
      expect(serialized['name'], 'University Engineering Quad');
      expect(serialized['enforceLock'], isTrue);
    });

    test('GeofenceStatusModel conditional uninstallation rules', () {
      // 1. Outside restricted geofence -> Clean uninstallation 100% permitted
      const statusOutside = GeofenceStatusModel(
        insideRestrictedGeofence: false,
        matchedZoneName: 'None (Outside)',
        canUninstallApp: true,
        emergencyExemptionActive: true,
      );
      expect(statusOutside.insideRestrictedGeofence, isFalse);
      expect(statusOutside.canUninstallApp, isTrue);
      expect(statusOutside.emergencyExemptionActive, isTrue);

      // 2. Inside restricted geofence -> Uninstallation locked
      const statusInside = GeofenceStatusModel(
        insideRestrictedGeofence: true,
        matchedZoneName: 'FocusGuard Global HQ',
        canUninstallApp: false,
        emergencyExemptionActive: true,
      );
      expect(statusInside.insideRestrictedGeofence, isTrue);
      expect(statusInside.canUninstallApp, isFalse);
      expect(statusInside.emergencyExemptionActive, isTrue);

      final map = statusInside.toMap();
      final roundTrip = GeofenceStatusModel.fromMap(map);
      expect(roundTrip.insideRestrictedGeofence, isTrue);
      expect(roundTrip.canUninstallApp, isFalse);
      expect(roundTrip.emergencyExemptionActive, isTrue);
    });

    test('FocusGeofenceService mock simulation methods', () async {
      // Fetch zones
      final zones = await FocusGeofenceService.getGeofenceZones();
      expect(zones.isNotEmpty, isTrue);
      expect(zones.first.zoneId, contains('sf_hq'));

      // Evaluate at HQ coordinates (Inside)
      final statusHq = await FocusGeofenceService.evaluateLocation(37.7937, -122.4000);
      expect(statusHq.insideRestrictedGeofence, isTrue);
      expect(statusHq.canUninstallApp, isFalse);

      // Evaluate far outside (Outside)
      final statusOutside = await FocusGeofenceService.evaluateLocation(37.3382, -121.8863);
      expect(statusOutside.insideRestrictedGeofence, isFalse);
      expect(statusOutside.canUninstallApp, isTrue);

      // Emergency call trigger
      final emerResult = await FocusGeofenceService.triggerEmergencyCall();
      expect(emerResult, isTrue);
    });
  });

  group('Enterprise Schedule Models & Service Unit Tests', () {
    test('FocusScheduleIntervalModel serialization and time formatting', () {
      final map = {
        'intervalId': 'int_study_morning',
        'title': 'Library Quiet Study Hours',
        'startHour': 8,
        'startMinute': 30,
        'endHour': 12,
        'endMinute': 0,
        'daysOfWeek': [1, 2, 3, 4],
        'enforceLock': true,
      };

      final interval = FocusScheduleIntervalModel.fromMap(map);
      expect(interval.intervalId, 'int_study_morning');
      expect(interval.title, 'Library Quiet Study Hours');
      expect(interval.startTimeFormatted, '08:30');
      expect(interval.endTimeFormatted, '12:00');
      expect(interval.daysOfWeek, [1, 2, 3, 4]);
      expect(interval.enforceLock, isTrue);

      final serialized = interval.toMap();
      expect(serialized['intervalId'], 'int_study_morning');
      expect(serialized['startHour'], 8);
    });

    test('ScheduleStatusModel conditional uninstallation rules', () {
      // 1. Outside schedule -> Normal mode: uninstallation permitted
      const offHours = ScheduleStatusModel(
        inFocusWindow: false,
        activeWindowTitle: 'None (Outside Schedule)',
        canUninstallApp: true,
        emergencyExemptionActive: true,
      );
      expect(offHours.inFocusWindow, isFalse);
      expect(offHours.canUninstallApp, isTrue);
      expect(offHours.emergencyExemptionActive, isTrue);

      // 2. Inside schedule -> Uninstallation strictly locked
      const inSession = ScheduleStatusModel(
        inFocusWindow: true,
        activeWindowTitle: 'Corporate Work Hours',
        canUninstallApp: false,
        emergencyExemptionActive: true,
      );
      expect(inSession.inFocusWindow, isTrue);
      expect(inSession.canUninstallApp, isFalse);
      expect(inSession.emergencyExemptionActive, isTrue);

      final map = inSession.toMap();
      final roundTrip = ScheduleStatusModel.fromMap(map);
      expect(roundTrip.inFocusWindow, isTrue);
      expect(roundTrip.canUninstallApp, isFalse);
    });

    test('FocusScheduleService mock simulation methods', () async {
      // Fetch intervals
      final intervals = await FocusScheduleService.getScheduleIntervals();
      expect(intervals.isNotEmpty, isTrue);
      expect(intervals.first.title, contains('Business Focus'));

      // Evaluate at 10:30 AM (Inside business hours 09:00 - 17:00)
      final statusInside = await FocusScheduleService.evaluateSchedule(
        dayOfWeek: 1,
        hour: 10,
        minute: 30,
      );
      expect(statusInside.inFocusWindow, isTrue);
      expect(statusInside.canUninstallApp, isFalse);

      // Evaluate at 22:30 PM (Outside business & study hours)
      final statusNight = await FocusScheduleService.evaluateSchedule(
        dayOfWeek: 1,
        hour: 22,
        minute: 30,
      );
      expect(statusNight.inFocusWindow, isFalse);
      expect(statusNight.canUninstallApp, isTrue);

      // Emergency call trigger
      final emer = await FocusScheduleService.triggerEmergencyCall();
      expect(emer, isTrue);
    });
  });

  group('GeofenceScreen Widget Tests', () {
    testWidgets('Renders GeofenceScreen radar canvas and initial normal state', (WidgetTester tester) async {
      FocusGeofenceService.setSimulatedStatus(const GeofenceStatusModel(
        insideRestrictedGeofence: false,
        matchedZoneName: 'None (Outside)',
        closestZoneName: 'FocusGuard Global HQ',
        closestDistanceMeters: 450.0,
        canUninstallApp: true,
        emergencyExemptionActive: true,
      ));

      await tester.pumpWidget(
        const MaterialApp(
          home: GeofenceScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify app bar title and top radar widget
      expect(find.text('Geofenced Boundary Enforcer'), findsOneWidget);
      expect(find.text('Perimeter Proximity Radar'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byKey(const Key('emergency_sos_geofence_btn')), findsOneWidget);
    });

    testWidgets('Tapping Enter HQ simulates entering restricted zone and locks uninstallation', (WidgetTester tester) async {
      FocusGeofenceService.setSimulatedStatus(const GeofenceStatusModel(
        insideRestrictedGeofence: false,
        canUninstallApp: true,
      ));

      await tester.pumpWidget(
        const MaterialApp(
          home: GeofenceScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll to Enter HQ button
      final enterBtn = find.byKey(const Key('simulate_enter_hq_btn'));
      await tester.scrollUntilVisible(enterBtn, 200);
      expect(enterBtn, findsOneWidget);

      // Tap Enter HQ
      await tester.tap(enterBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll to top to view status card
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify uninstallation is now locked
      expect(find.text('RESTRICTED ZONE (LOCKED)'), findsOneWidget);

      // Scroll to Exit button
      final exitBtn = find.byKey(const Key('simulate_exit_btn'));
      await tester.scrollUntilVisible(exitBtn, 200);

      // Tap Exit
      await tester.tap(exitBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll to top to view restored normal mode
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify normal mode restored
      expect(find.text('STANDBY (NORMAL MODE)'), findsOneWidget);
    });

    testWidgets('Emergency Dial 112 button triggers emergency snackbar feedback', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GeofenceScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Emergency Dial SOS
      await tester.tap(find.byKey(const Key('emergency_sos_geofence_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify snackbar appears
      expect(find.text('Emergency SOS 112 dialer launched (Life Safety Exemption).'), findsOneWidget);
    });
  });

  group('EnterpriseScheduleScreen Widget Tests', () {
    testWidgets('Renders EnterpriseScheduleScreen timetable and status banner', (WidgetTester tester) async {
      FocusScheduleService.setSimulatedStatus(const ScheduleStatusModel(
        inFocusWindow: false,
        activeWindowTitle: 'None (Outside Schedule)',
        canUninstallApp: true,
        emergencyExemptionActive: true,
        dayOfWeek: 1,
        currentMinutes: 600,
      ));

      await tester.pumpWidget(
        const MaterialApp(
          home: EnterpriseScheduleScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify screen title
      expect(find.text('Enterprise Focus Schedule'), findsOneWidget);

      // Verify timetable compliance card
      expect(find.text('Timetable Posture'), findsOneWidget);
      expect(find.text('STANDBY (NORMAL MODE)'), findsOneWidget);
      expect(find.text('Inviolable Uninstallation Law'), findsOneWidget);

      // Scroll to buttons if needed and verify
      final inWindowBtn = find.byKey(const Key('simulate_work_hours_btn'));
      await tester.scrollUntilVisible(inWindowBtn, 200);
      expect(inWindowBtn, findsOneWidget);

      expect(find.byKey(const Key('simulate_off_hours_btn')), findsOneWidget);
      expect(find.byKey(const Key('emergency_sos_schedule_btn')), findsOneWidget);
    });

    testWidgets('Shifting clock inside work hours locks uninstallation and displays active event', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EnterpriseScheduleScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Scroll to In-Window button
      final inWindowBtn = find.byKey(const Key('simulate_work_hours_btn'));
      await tester.scrollUntilVisible(inWindowBtn, 200);

      // Tap In-Window button
      await tester.tap(inWindowBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Scroll up to view status card
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify locked status banner
      expect(find.text('FOCUS SESSION ACTIVE (LOCKED)'), findsOneWidget);

      // Scroll to Off-Hours button
      final offHoursBtn = find.byKey(const Key('simulate_off_hours_btn'));
      await tester.scrollUntilVisible(offHoursBtn, 200);

      // Tap Off-Hours button
      await tester.tap(offHoursBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Scroll up to view normal mode
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify clean uninstallation permitted
      expect(find.text('STANDBY (NORMAL MODE)'), findsOneWidget);
    });

    testWidgets('Emergency Dial SOS button shows snackbar in EnterpriseScheduleScreen', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EnterpriseScheduleScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('emergency_sos_schedule_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Emergency SOS 112 dialer launched (Life Safety Exemption).'), findsOneWidget);
    });
  });

  group('DevicePolicyAuditScreen Navigation Integration', () {
    testWidgets('DevicePolicyAuditScreen contains Geofence and Calendar navigation tiles', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DevicePolicyAuditScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify the list view exists
      expect(find.byType(ListView), findsOneWidget);

      // Scroll to Geofenced Boundary Enforcer tile
      final geofenceTile = find.byKey(const Key('geofence_audit_tile'));
      await tester.scrollUntilVisible(geofenceTile, 200);
      expect(geofenceTile, findsOneWidget);

      final scheduleTile = find.byKey(const Key('schedule_audit_tile'));
      await tester.scrollUntilVisible(scheduleTile, 200);
      expect(scheduleTile, findsOneWidget);
    });
  });
}
