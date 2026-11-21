import 'dart:async';
import 'package:flutter/material.dart';
import 'package:focus_dns/engine/per_app/models/friction_challenge_model.dart';

/// Interactive challenge screen demanding cognitive friction before allowing an emergency unlock.
class FrictionChallengeScreen extends StatefulWidget {
  final FrictionChallenge challenge;
  final String appName;
  final VoidCallback onChallengePassed;

  const FrictionChallengeScreen({
    super.key,
    required this.challenge,
    required this.appName,
    required this.onChallengePassed,
  });

  @override
  State<FrictionChallengeScreen> createState() => _FrictionChallengeScreenState();
}

class _FrictionChallengeScreenState extends State<FrictionChallengeScreen> {
  final TextEditingController _oathController = TextEditingController();
  late int _remainingDelaySeconds;
  Timer? _delayTimer;
  final List<TextEditingController> _mathControllers = [];

  @override
  void initState() {
    super.initState();
    _remainingDelaySeconds = widget.challenge.mandatoryDelaySeconds;

    if (widget.challenge.type == FrictionChallengeType.cooldownWaitDelay) {
      _startDelayTimer();
    } else if (widget.challenge.type == FrictionChallengeType.mentalMathEquations) {
      for (int i = 0; i < widget.challenge.equations.length; i++) {
        _mathControllers.add(TextEditingController());
      }
    }
  }

  void _startDelayTimer() {
    _delayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingDelaySeconds > 0) {
        setState(() => _remainingDelaySeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  void _verifyAndProceed() {
    if (widget.challenge.type == FrictionChallengeType.mindfulOathTyping) {
      if (widget.challenge.verifyOath(_oathController.text)) {
        widget.onChallengePassed();
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Oath text does not match character-for-character. Try again.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    } else if (widget.challenge.type == FrictionChallengeType.mentalMathEquations) {
      bool allCorrect = true;
      for (int i = 0; i < widget.challenge.equations.length; i++) {
        final parsed = int.tryParse(_mathControllers[i].text.trim());
        if (parsed == null || !widget.challenge.equations[i].verify(parsed)) {
          allCorrect = false;
          break;
        }
      }
      if (allCorrect) {
        widget.onChallengePassed();
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('One or more arithmetic answers are incorrect. Try again.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    } else if (widget.challenge.type == FrictionChallengeType.cooldownWaitDelay) {
      if (_remainingDelaySeconds <= 0) {
        widget.onChallengePassed();
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _oathController.dispose();
    for (final c in _mathControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Text(
          'Unlock Challenge: ${widget.appName}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.shield_rounded, color: Color(0xFFEF4444), size: 28),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Friction Barrier Active. To prevent impulsive doomscrolling, complete the challenge below.',
                      style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.challenge.promptMessage,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            if (widget.challenge.type == FrictionChallengeType.mindfulOathTyping) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF131B2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  widget.challenge.requiredOathText ?? '',
                  style: const TextStyle(
                    color: Color(0xFFFBBF24),
                    fontStyle: FontStyle.italic,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _oathController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Type the oath above exactly...',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF131B2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                ),
              ),
            ] else if (widget.challenge.type == FrictionChallengeType.mentalMathEquations) ...[
              ...List.generate(widget.challenge.equations.length, (i) {
                final eq = widget.challenge.equations[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131B2E),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          eq.expression,
                          style: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text('=', style: TextStyle(color: Colors.white, fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _mathControllers[i],
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Answer',
                            hintStyle: const TextStyle(color: Colors.white30),
                            filled: true,
                            fillColor: const Color(0xFF131B2E),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ] else if (widget.challenge.type == FrictionChallengeType.cooldownWaitDelay) ...[
              Center(
                child: Column(
                  children: [
                    Text(
                      '$_remainingDelaySeconds',
                      style: const TextStyle(
                        color: Color(0xFF3B82F6),
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('Seconds Remaining', style: TextStyle(color: Colors.white54, fontSize: 14)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _verifyAndProceed,
                child: const Text(
                  'CONFIRM & PROCEED',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
