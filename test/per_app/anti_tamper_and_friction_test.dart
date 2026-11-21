import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/per_app/core/anti_tamper_clock.dart';
import 'package:focus_dns/engine/per_app/models/friction_challenge_model.dart';

void main() {
  group('AntiTamperClock & FrictionChallenge Tests', () {
    test('1. AntiTamperClock monotonic progression advances continuously', () {
      final base = DateTime(2026, 11, 7, 12, 0, 0);
      final clock = AntiTamperClock(initialAnchor: base);

      final t1 = clock.monotonicNow;
      expect(t1.isAfter(base) || t1.isAtSameMomentAs(base), isTrue);
      expect(clock.tamperingStrikeCount, equals(0));
    });

    test('2. AntiTamperClock detects wall clock rollback tampering', () {
      final base = DateTime(2026, 11, 7, 12, 0, 0);
      final clock = AntiTamperClock(initialAnchor: base);

      // Normal wall clock close to monotonic anchor (30s drift) -> valid
      final normalTime = base.add(const Duration(seconds: 30));
      final isValid = clock.verifyAgainstWallClock(normalTime);
      expect(isValid, isTrue);
      expect(clock.tamperingStrikeCount, equals(0));

      // Attacker rolls back device time by 2 hours (7200 seconds)
      final rolledBackTime = base.subtract(const Duration(hours: 2));
      final isTampered = clock.verifyAgainstWallClock(rolledBackTime);

      expect(isTampered, isFalse);
      expect(clock.tamperingStrikeCount, equals(1));
      expect(clock.lastTamperingDetectedAt, equals(rolledBackTime));
    });

    test('3. FrictionChallenge oath verification enforces exact character matching', () {
      final challenge = FrictionChallenge.createOathChallenge();
      expect(challenge.type, equals(FrictionChallengeType.mindfulOathTyping));
      expect(challenge.requiredOathText, isNotNull);

      // Incorrect oath submission fails
      expect(challenge.verifyOath('I want to open this app now!'), isFalse);

      // Exact match passes
      expect(challenge.verifyOath(challenge.requiredOathText!), isTrue);
    });

    test('4. FrictionChallenge math equations verify answers accurately', () {
      final challenge = FrictionChallenge.createMathChallenge();
      expect(challenge.type, equals(FrictionChallengeType.mentalMathEquations));
      expect(challenge.equations.length, equals(3));

      for (final eq in challenge.equations) {
        expect(eq.verify(eq.expectedAnswer), isTrue);
        expect(eq.verify(eq.expectedAnswer + 1), isFalse);
      }
    });

    test('5. FrictionChallenge delay challenge sets mandatory countdown seconds', () {
      final delay = FrictionChallenge.createDelayChallenge(delaySeconds: 45);
      expect(delay.type, equals(FrictionChallengeType.cooldownWaitDelay));
      expect(delay.mandatoryDelaySeconds, equals(45));
    });
  });
}
