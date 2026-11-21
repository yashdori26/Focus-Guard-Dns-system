import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state_management/providers.dart';
import '../../theme/wabi_sabi_theme.dart';

class OtpVerificationView extends ConsumerStatefulWidget {
  const OtpVerificationView({super.key});

  @override
  ConsumerState<OtpVerificationView> createState() => _OtpVerificationViewState();
}

class _OtpVerificationViewState extends ConsumerState<OtpVerificationView> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  int _secondsRemaining = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    // Auto-focus first digit
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focusNodes.isNotEmpty && mounted) {
        _focusNodes[0].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsRemaining = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        t.cancel();
      }
    });
  }

  String get _currentOtp => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty) {
      if (value.length > 1) {
        // Handle paste of multiple characters
        final digits = value.replaceAll(RegExp(r'\D'), '');
        for (int i = 0; i < digits.length && (index + i) < 6; i++) {
          _controllers[index + i].text = digits[i];
        }
        final nextIndex = (index + digits.length < 6) ? index + digits.length : 5;
        _focusNodes[nextIndex].requestFocus();
      } else {
        if (index < 5) {
          _focusNodes[index + 1].requestFocus();
        } else {
          _focusNodes[index].unfocus();
        }
      }
    } else {
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
    }

    if (_currentOtp.length == 6) {
      _verifyCode();
    }
    setState(() {});
  }

  Future<void> _verifyCode({String? overrideCode}) async {
    final code = overrideCode ?? _currentOtp;
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter all 6 digits of your SMS code'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final auth = ref.read(authProvider);
    final phone = auth.phoneNumber ?? '';

    await ref.read(authProvider.notifier).verifyOtp(phone, code);
  }

  void _fillInstantDevCode(String code) {
    for (int i = 0; i < 6 && i < code.length; i++) {
      _controllers[i].text = code[i];
    }
    setState(() {});
    _verifyCode(overrideCode: code);
  }

  Future<void> _resendCode() async {
    if (_secondsRemaining > 0) return;
    final auth = ref.read(authProvider);
    if (auth.phoneNumber != null) {
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
      await ref.read(authProvider.notifier).sendOtp(auth.phoneNumber!);
      _startCountdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final auth = ref.watch(authProvider);
    final devCode = auth.devOtp ?? '123456';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Phone and Change button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verification Code',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: palette.ink,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Sent to ${auth.phoneNumber ?? ""}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  ref.read(authProvider.notifier).goToStep(AuthStep.phoneInput);
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  backgroundColor: palette.ink.withOpacity(0.06),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  'Change',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: palette.ink),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // 6-Digit PIN Boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              final isFilled = _controllers[index].text.isNotEmpty;
              final hasFocus = _focusNodes[index].hasFocus;

              return Container(
                width: 48,
                height: 56,
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasFocus
                        ? palette.ink
                        : isFilled
                            ? palette.ink.withOpacity(0.4)
                            : palette.border,
                    width: hasFocus ? 2.0 : 1.2,
                  ),
                  boxShadow: hasFocus
                      ? [
                          BoxShadow(
                            color: palette.ink.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Center(
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: palette.ink,
                      fontFamily: 'JetBrains Mono',
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) => _onDigitChanged(index, val),
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 20),

          // Instant Dev Testing Chip (1-Tap Auto-fill & Submit)
          InkWell(
            onTap: () => _fillInstantDevCode(devCode),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 18, color: Color(0xFFF1C40F)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'INSTANT DEV TEST CODE: $devCode',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: palette.ink,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                        Text(
                          'Tap to immediately fill & verify without waiting for SMS delivery.',
                          style: TextStyle(fontSize: 10, color: palette.mutedInk),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: palette.ink,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Auto-Fill',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: palette.canvas),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Resend Timer Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_outlined, size: 15, color: palette.mutedInk),
              const SizedBox(width: 6),
              if (_secondsRemaining > 0)
                Text(
                  'Resend code in ${_secondsRemaining}s',
                  style: TextStyle(fontSize: 12, color: palette.mutedInk, fontFamily: 'JetBrains Mono'),
                )
              else
                TextButton(
                  onPressed: _resendCode,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Resend SMS Code',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: palette.ink),
                  ),
                ),
            ],
          ),

          if (auth.errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE05252).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE05252).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 18, color: Color(0xFFD32F2F)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      auth.errorMessage!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD32F2F), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 28),

          // Verify Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: auth.isLoading ? null : () => _verifyCode(),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.ink,
                foregroundColor: palette.canvas,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: auth.isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: palette.canvas),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Verify Code',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.check_circle_outline_rounded, size: 18),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
