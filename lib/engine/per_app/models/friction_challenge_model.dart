import 'dart:math';
import 'package:flutter/foundation.dart';

enum FrictionChallengeType {
  mindfulOathTyping,
  mentalMathEquations,
  cooldownWaitDelay,
}

@immutable
class MathEquation {
  final String expression;
  final int expectedAnswer;

  const MathEquation({
    required this.expression,
    required this.expectedAnswer,
  });

  bool verify(int userAnswer) => userAnswer == expectedAnswer;
}

/// Dynamic friction challenge presented when user attempts an emergency unlock in flexible mode.
@immutable
class FrictionChallenge {
  final String challengeId;
  final FrictionChallengeType type;
  final String promptMessage;
  final String? requiredOathText;
  final List<MathEquation> equations;
  final int mandatoryDelaySeconds;

  const FrictionChallenge({
    required this.challengeId,
    required this.type,
    required this.promptMessage,
    this.requiredOathText,
    this.equations = const [],
    this.mandatoryDelaySeconds = 60,
  });

  /// Factory creating a mindful commitment oath challenge.
  factory FrictionChallenge.createOathChallenge() {
    const oaths = [
      'I acknowledge that opening this app will fracture my focus and derail my daily goals.',
      'I consciously choose to trade my finite life energy and long-term potential for cheap algorithmic stimulation.',
      'I am aware of the doomscroll trap and am deliberately breaking my commitment to deep work.',
      'I recognize that instant gratification weakens my willpower and delays my true aspirations.',
    ];
    final selectedOath = oaths[Random().nextInt(oaths.length)];
    return FrictionChallenge(
      challengeId: 'oath_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}',
      type: FrictionChallengeType.mindfulOathTyping,
      promptMessage: 'Type the exact mindful oath below to confirm you consciously choose to break your focus:',
      requiredOathText: selectedOath,
    );
  }

  /// Factory creating a mental math challenge consisting of 3 arithmetic problems.
  factory FrictionChallenge.createMathChallenge() {
    final rng = Random();
    final eqs = <MathEquation>[];

    for (int i = 0; i < 3; i++) {
      final a = rng.nextInt(30) + 12;
      final b = rng.nextInt(20) + 7;
      final c = rng.nextInt(50) + 10;
      eqs.add(MathEquation(
        expression: '$a + $b - $c',
        expectedAnswer: a + b - c,
      ));
    }

    return FrictionChallenge(
      challengeId: 'math_${DateTime.now().microsecondsSinceEpoch}_${rng.nextInt(99999)}',
      type: FrictionChallengeType.mentalMathEquations,
      promptMessage: 'Solve these 3 mental arithmetic equations to engage prefrontal cognitive control:',
      equations: eqs,
    );
  }

  /// Factory creating a mandatory cooldown delay challenge.
  factory FrictionChallenge.createDelayChallenge({int delaySeconds = 60}) {
    return FrictionChallenge(
      challengeId: 'delay_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}',
      type: FrictionChallengeType.cooldownWaitDelay,
      promptMessage: 'Mandatory reflection cooldown. Wait for the counter to complete before proceeding:',
      mandatoryDelaySeconds: delaySeconds,
    );
  }

  /// Verifies an oath text submission.
  bool verifyOath(String submitted) {
    if (requiredOathText == null) return false;
    return submitted.trim() == requiredOathText!.trim();
  }
}
