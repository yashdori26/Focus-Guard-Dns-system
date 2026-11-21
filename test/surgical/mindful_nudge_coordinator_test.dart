import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_subfeature_types.dart';
import 'package:focus_dns/engine/surgical/core/mindful_nudge_coordinator.dart';

void main() {
  group('Mindful Nudge Coordinator Tests', () {
    late MindfulNudgeCoordinator coordinator;

    setUp(() {
      coordinator = MindfulNudgeCoordinator(
        defaultPauseSeconds: 3,
        maxDailyBypassTokens: 2,
      );
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('Starts mindful nudge session with active countdown', () {
      final session = coordinator.startNudge(
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );

      expect(session.platformId, equals('instagram'));
      expect(session.subfeature, equals(SurgicalSubfeature.reelsOrShorts));
      expect(session.state, equals(MindfulNudgeState.countdownActive));
      expect(session.totalDurationSeconds, equals(3));
      expect(session.remainingSeconds, equals(3));
      expect(session.progress, equals(0.0));
      expect(session.motivationalPrompt.isNotEmpty, isTrue);
      expect(session.requiredPledgePhrase.isNotEmpty, isTrue);

      expect(coordinator.currentSession, isNotNull);
    });

    test('Cancel and redirect enforces focus and resets active session', () {
      coordinator.startNudge(
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );

      coordinator.cancelAndRedirect();
      expect(coordinator.currentSession, isNull);
    });

    test('Cognitive pledge verification requires matching text', () {
      final session = coordinator.startNudge(
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );

      final targetPledge = session.requiredPledgePhrase;

      // 1. Wrong text -> rejected
      final wrongResult = coordinator.submitPledge('random junk');
      expect(wrongResult, isFalse);

      // 2. Correct text (case-insensitive) -> accepted
      final correctResult = coordinator.submitPledge(targetPledge.toUpperCase());
      expect(correctResult, isTrue);
    });

    test('Daily bypass tokens are decremented and enforce quota limit', () {
      expect(coordinator.remainingBypassTokens, equals(2));

      // Token 1
      coordinator.startNudge(
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );
      final bypass1 = coordinator.grantBypass();
      expect(bypass1, isTrue);
      expect(coordinator.remainingBypassTokens, equals(1));

      // Token 2
      coordinator.startNudge(
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );
      final bypass2 = coordinator.grantBypass();
      expect(bypass2, isTrue);
      expect(coordinator.remainingBypassTokens, equals(0));

      // Token 3 (Quota exhausted)
      coordinator.startNudge(
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );
      final bypass3 = coordinator.grantBypass();
      expect(bypass3, isFalse, reason: 'Exceeded maxDailyBypassTokens');
      expect(coordinator.remainingBypassTokens, equals(0));
    });

    test('Contextual motivational prompts are adapted per subfeature', () {
      final reelsSession = coordinator.startNudge(
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );
      expect(reelsSession.motivationalPrompt, contains('Vertical video'));

      final feedSession = coordinator.startNudge(
        platformId: 'twitter',
        platformName: 'Twitter',
        subfeature: SurgicalSubfeature.feed,
      );
      expect(feedSession.motivationalPrompt, contains('Algorithmic feeds'));
    });
  });
}
