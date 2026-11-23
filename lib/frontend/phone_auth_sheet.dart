import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state_management/providers.dart';
import 'theme/wabi_sabi_theme.dart';

/// Frictionless Phone Authentication Bottom Sheet
/// Automatically checks client IP, extracts country code, pre-fills country flag and dial code,
/// sends SMS OTP, and supports 1-tap instant verification.
class PhoneAuthSheet extends ConsumerStatefulWidget {
  const PhoneAuthSheet({super.key});

  @override
  ConsumerState<PhoneAuthSheet> createState() => _PhoneAuthSheetState();
}

class _PhoneAuthSheetState extends ConsumerState<PhoneAuthSheet> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  bool _codeSent = false;
  String? _devOtp;
  String? _statusMessage;
  bool _isSending = false;
  bool _isVerifying = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _openCountryPicker() {
    final auth = ref.read(authProvider);
    final countries = auth.countries;
    final palette = WabiSabiPalette.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _CountryPickerModal(
          countries: countries,
          palette: palette,
          onSelected: (code, dial, flag) {
            ref.read(authProvider.notifier).selectCountry(code, dial, flag);
            Navigator.pop(ctx);
          },
        );
      },
    );
  }

  Future<void> _handleSendCode() async {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty) {
      setState(() => _statusMessage = 'Please enter a valid phone number');
      return;
    }

    final auth = ref.read(authProvider);
    final fullPhone = rawPhone.startsWith('+') ? rawPhone : '${auth.detectedDialCode}$rawPhone';

    setState(() {
      _isSending = true;
      _statusMessage = null;
    });

    final res = await ref.read(authProvider.notifier).sendOtp(fullPhone);

    if (mounted) {
      setState(() {
        _isSending = false;
        if (res['success'] == true) {
          _codeSent = true;
          _devOtp = res['dev_otp']?.toString();
          _statusMessage = res['message'] ?? 'Code sent successfully!';
        } else {
          _statusMessage = res['error']?.toString() ?? 'Failed to send SMS code';
        }
      });
    }
  }

  Future<void> _handleVerify({String? overrideOtp}) async {
    final rawPhone = _phoneController.text.trim();
    final auth = ref.read(authProvider);
    final fullPhone = rawPhone.startsWith('+') ? rawPhone : '${auth.detectedDialCode}$rawPhone';
    final otp = (overrideOtp ?? _otpController.text).trim();

    if (otp.isEmpty) {
      setState(() => _statusMessage = 'Please enter the 6-digit code');
      return;
    }

    setState(() {
      _isVerifying = true;
      _statusMessage = null;
    });

    final res = await ref.read(authProvider.notifier).verifyOtp(fullPhone, otp);

    if (mounted) {
      setState(() => _isVerifying = false);
      if (res['success'] == true) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1B1B1E),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF00E699), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Authenticated as ${res['profile_name'] ?? 'Local Shield'}',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        setState(() {
          _statusMessage = res['error']?.toString() ?? 'Invalid verification code';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final auth = ref.watch(authProvider);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: palette.border, width: 1.2)),
      ),
      padding: EdgeInsets.only(
        left: 22,
        right: 22,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Instant Phone Access',
                        style: GoogleFonts.fraunces(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: palette.ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: palette.canvas,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: palette.border, width: 0.8),
                            ),
                            child: Text(
                              'IP: ${auth.detectedIp}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                color: palette.mutedInk,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: palette.canvas,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: palette.border, width: 0.8),
                            ),
                            child: Text(
                              '${auth.detectedFlag} ${auth.detectedCountryCode}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: palette.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: palette.mutedInk, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // Phone Number Input Row
              Text(
                'PHONE NUMBER',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: palette.mutedInk,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // Country Flag & Dial Code Pill (Clickable)
                  InkWell(
                    onTap: _openCountryPicker,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                      decoration: BoxDecoration(
                        color: palette.canvas,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.border, width: 1.1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(auth.detectedFlag, style: const TextStyle(fontSize: 19)),
                          const SizedBox(width: 7),
                          Text(
                            auth.detectedDialCode,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: palette.ink,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down_rounded, size: 18, color: palette.mutedInk),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Phone Input Field
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      enabled: !_codeSent,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: palette.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: '98765 43210',
                        hintStyle: TextStyle(fontSize: 13.5, color: palette.mutedInk.withOpacity(0.5)),
                        filled: true,
                        fillColor: palette.canvas,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: palette.border, width: 1.1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: palette.border, width: 1.1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: palette.accent, width: 1.8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // SEND CODE Button
              if (!_codeSent)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSending ? null : _handleSendCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.canvas,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSending
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: palette.canvas),
                          )
                        : Text(
                            'Send Verification Code →',
                            style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),

              // Verification Section (Shown after code is sent)
              if (_codeSent) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ENTER 6-DIGIT SMS CODE',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: palette.mutedInk,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _codeSent = false),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Change Number',
                        style: GoogleFonts.inter(fontSize: 12, color: palette.accent, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // OTP Input Field
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 22,
                    letterSpacing: 10,
                    fontWeight: FontWeight.bold,
                    color: palette.ink,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '• • • • • •',
                    hintStyle: TextStyle(
                      fontSize: 20,
                      letterSpacing: 10,
                      color: palette.mutedInk.withOpacity(0.35),
                    ),
                    filled: true,
                    fillColor: palette.canvas,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.border, width: 1.1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.border, width: 1.1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.accent, width: 1.8),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Instant Dev Test Chip (Frictionless 1-Tap Verification)
                InkWell(
                  onTap: () {
                    final code = _devOtp ?? '123456';
                    _otpController.text = code;
                    _handleVerify(overrideOtp: code);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5A00D).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5A00D).withOpacity(0.35), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.flash_on_rounded, size: 15, color: Color(0xFFE5A00D)),
                        const SizedBox(width: 8),
                        Text(
                          'Instant Dev Code: ${_devOtp ?? '123456'} (Tap to auto-fill)',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Verify Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isVerifying ? null : () => _handleVerify(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.canvas,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isVerifying
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: palette.canvas),
                          )
                        : Text(
                            'Verify & Sync Profiles →',
                            style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],

              // Status / Error message
              if (_statusMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _statusMessage!.toLowerCase().contains('success') || _statusMessage!.toLowerCase().contains('sent')
                        ? palette.safeAccent.withOpacity(0.1)
                        : const Color(0xFFE05252).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _statusMessage!.toLowerCase().contains('success') || _statusMessage!.toLowerCase().contains('sent')
                          ? palette.safeAccent.withOpacity(0.3)
                          : const Color(0xFFE05252).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _statusMessage!.toLowerCase().contains('success') || _statusMessage!.toLowerCase().contains('sent')
                          ? palette.safeAccent
                          : const Color(0xFFE05252),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CountryPickerModal extends StatefulWidget {
  final List<Map<String, dynamic>> countries;
  final WabiSabiPalette palette;
  final Function(String code, String dial, String flag) onSelected;

  const _CountryPickerModal({
    required this.countries,
    required this.palette,
    required this.onSelected,
  });

  @override
  State<_CountryPickerModal> createState() => _CountryPickerModalState();
}

class _CountryPickerModalState extends State<_CountryPickerModal> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.countries;
  }

  void _onSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = widget.countries);
      return;
    }
    setState(() {
      _filtered = widget.countries.where((c) {
        final name = (c['country_name'] ?? '').toString().toLowerCase();
        final code = (c['country_code'] ?? '').toString().toLowerCase();
        final dial = (c['dial_code'] ?? '').toString().toLowerCase();
        return name.contains(q) || code.contains(q) || dial.contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: palette.border, width: 1.2)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Country',
                style: GoogleFonts.fraunces(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: palette.mutedInk, size: 22),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Search input
          TextField(
            controller: _searchController,
            onChanged: _onSearch,
            style: GoogleFonts.inter(fontSize: 13.5, color: palette.ink),
            decoration: InputDecoration(
              hintText: 'Search by country name or dial code...',
              hintStyle: TextStyle(fontSize: 13, color: palette.mutedInk.withOpacity(0.6)),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: palette.mutedInk),
              filled: true,
              fillColor: palette.canvas,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.accent, width: 1.6),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Country list
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text('No countries found', style: GoogleFonts.inter(color: palette.mutedInk)),
                  )
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: palette.hairlineSoft),
                    itemBuilder: (ctx, i) {
                      final item = _filtered[i];
                      final code = item['country_code']?.toString() ?? '';
                      final name = item['country_name']?.toString() ?? code;
                      final dial = item['dial_code']?.toString() ?? '';
                      final flag = item['flag']?.toString() ?? '🌐';

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        leading: Text(flag, style: const TextStyle(fontSize: 22)),
                        title: Text(
                          name,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                        trailing: Text(
                          dial,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: palette.accent,
                          ),
                        ),
                        onTap: () => widget.onSelected(code, dial, flag),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
