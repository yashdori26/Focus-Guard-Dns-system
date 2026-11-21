import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_dns/engine/profile/accountability_partner_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Accountability Partner Manager Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('1. Assign partner stores verified guardian in memory and preferences', () async {
      final manager = await AccountabilityPartnerManager.create();
      expect(manager.partner, isNull);

      await manager.assignPartner(
        name: 'Alex Johnson',
        email: 'alex@example.com',
        phone: '+15551234567',
      );

      expect(manager.partner, isNotNull);
      expect(manager.partner?.name, equals('Alex Johnson'));
      expect(manager.partner?.email, equals('alex@example.com'));
      expect(manager.partner?.isVerified, isTrue);
      expect(manager.partner?.trustScore, equals(100));
    });

    test('2. Creating unlock request enters pending state', () async {
      final manager = await AccountabilityPartnerManager.create();
      final req = await manager.createUnlockRequest(
        deviceId: 'dev_laptop_1',
        reason: 'Urgent client Instagram DM for advertising campaign',
      );

      expect(req.requestId, isNotEmpty);
      expect(req.status, equals(EmergencyRequestStatus.pending));
      expect(manager.requests.length, equals(1));
      expect(manager.requests.first.isPending, isTrue);
    });

    test('3. Approving request updates status and partner review count', () async {
      final manager = await AccountabilityPartnerManager.create();
      await manager.assignPartner(name: 'Sarah', email: 'sarah@example.com');

      final req = await manager.createUnlockRequest(
        deviceId: 'dev_laptop_1',
        reason: 'Need medical exam study group chat',
      );

      final success = await manager.approveRequest(req.requestId, 'PIN_PARTNER_99');
      expect(success, isTrue);

      final updatedReq = manager.requests.firstWhere((r) => r.requestId == req.requestId);
      expect(updatedReq.status, equals(EmergencyRequestStatus.approved));
      expect(updatedReq.isApproved, isTrue);
      expect(updatedReq.approvalSignature, isNotNull);

      expect(manager.partner?.totalRequestsReviewed, equals(1));
      expect(manager.partner?.totalRequestsApproved, equals(1));
    });

    test('4. Rejecting request marks rejected and preserves lock', () async {
      final manager = await AccountabilityPartnerManager.create();
      await manager.assignPartner(name: 'Sarah', email: 'sarah@example.com');

      final req = await manager.createUnlockRequest(
        deviceId: 'dev_laptop_1',
        reason: 'Just want to scroll memes for 5 minutes',
      );

      final success = await manager.rejectRequest(req.requestId);
      expect(success, isTrue);

      final updatedReq = manager.requests.firstWhere((r) => r.requestId == req.requestId);
      expect(updatedReq.status, equals(EmergencyRequestStatus.rejected));
      expect(manager.partner?.totalRequestsReviewed, equals(1));
      expect(manager.partner?.totalRequestsApproved, equals(0)); // Did not approve
    });
  });
}
