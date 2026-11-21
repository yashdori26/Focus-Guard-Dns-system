import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state_management/providers.dart';
import '../../theme/wabi_sabi_theme.dart';
import '../country_picker_dialog.dart';

class PhoneInputView extends ConsumerStatefulWidget {
  const PhoneInputView({super.key});

  @override
  ConsumerState<PhoneInputView> createState() => _PhoneInputViewState();
}

class _PhoneInputViewState extends ConsumerState<PhoneInputView> {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    if (auth.phoneNumber != null && auth.phoneNumber!.isNotEmpty) {
      // Remove dial code prefix if present for clean editing
      var num = auth.phoneNumber!;
      if (num.startsWith(auth.detectedDialCode)) {
        num = num.substring(auth.detectedDialCode.length);
      }
      _phoneController.text = num;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _openCountryPicker() {
    final auth = ref.read(authProvider);
    final palette = WabiSabiPalette.of(context);

    CountryPickerDialog.show(
      context,
      countries: auth.countries,
      palette: palette,
      onSelected: (code, dial, flag) {
        ref.read(authProvider.notifier).selectCountry(code, dial, flag);
      },
    );
  }

  Future<void> _submitPhone() async {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty || rawPhone.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid phone number (at least 6 digits)'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final auth = ref.read(authProvider);
    final fullPhone = rawPhone.startsWith('+') ? rawPhone : '${auth.detectedDialCode}$rawPhone';

    await ref.read(authProvider.notifier).sendOtp(fullPhone);
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final auth = ref.watch(authProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Client GeoIP Discovery Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF2ECC71),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'IP GEO LOCATION DISCOVERED',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.bold,
                          color: palette.mutedInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${auth.detectedIp} • ${auth.detectedFlag} ${auth.detectedCountryCode} (${auth.detectedDialCode})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: _openCountryPicker,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: palette.ink.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Change',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Title & Description
          Text(
            'Enter Mobile Number',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: palette.ink,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'FocusDNS uses instant SMS verification for frictionless, passwordless profile access across all your devices.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: palette.mutedInk,
            ),
          ),

          const SizedBox(height: 28),

          // Phone Input Form
          Text(
            'PHONE NUMBER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: palette.mutedInk,
            ),
          ),
          const SizedBox(height: 8),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Country Dial Code Box
              InkWell(
                onTap: _openCountryPicker,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.border, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(auth.detectedFlag, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text(
                        auth.detectedDialCode,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: palette.ink,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, color: palette.mutedInk, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Number Input
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: TextField(
                    controller: _phoneController,
                    focusNode: _focusNode,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                      letterSpacing: 1.2,
                      fontFamily: 'JetBrains Mono',
                    ),
                    decoration: InputDecoration(
                      hintText: '98765 43210',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        color: palette.mutedInk.withOpacity(0.4),
                        letterSpacing: 1.2,
                      ),
                      filled: true,
                      fillColor: palette.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border, width: 1.2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border, width: 1.2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.ink, width: 1.8),
                      ),
                      suffixIcon: _phoneController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 16, color: palette.mutedInk),
                              onPressed: () {
                                setState(() => _phoneController.clear());
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submitPhone(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Information Features List
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surface.withOpacity(0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border.withOpacity(0.8)),
            ),
            child: Column(
              children: [
                _buildInfoRow(
                  palette,
                  icon: Icons.flash_on_rounded,
                  title: 'Instant 1-Tap Verification',
                  subtitle: 'No complex passwords to remember or reset.',
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  palette,
                  icon: Icons.cloud_sync_rounded,
                  title: 'Automatic Cloud Profile Sync',
                  subtitle: 'Seamlessly access your blocklists and DNS rules anywhere.',
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  palette,
                  icon: Icons.shield_outlined,
                  title: 'Privacy Guarantee',
                  subtitle: 'Your phone number is only used for authentication security.',
                ),
              ],
            ),
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

          // Continue CTA Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: auth.isLoading ? null : _submitPhone,
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
                          'Continue with SMS',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 16),

          Center(
            child: Text(
              'Standard carrier SMS rates may apply • Terms of Service',
              style: TextStyle(fontSize: 11, color: palette.mutedInk.withOpacity(0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    WabiSabiPalette palette, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: palette.ink),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: palette.mutedInk),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
