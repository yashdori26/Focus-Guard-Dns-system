import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/email_otp_service.dart';
import '../theme/wabi_sabi_theme.dart';
import 'auth_widgets.dart';

/// Tactile bottom sheet allowing users to configure Gmail/SMTP credentials for real email delivery
class SmtpSettingsSheet extends StatefulWidget {
  const SmtpSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const SmtpSettingsSheet(),
    );
  }

  @override
  State<SmtpSettingsSheet> createState() => _SmtpSettingsSheetState();
}

class _SmtpSettingsSheetState extends State<SmtpSettingsSheet> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _hostController = TextEditingController(text: 'smtp.gmail.com');
  final TextEditingController _portController = TextEditingController(text: '465');
  bool _obscurePass = true;
  bool _saving = false;
  String? _savedMessage;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final cfg = await EmailOtpService.getSmtpConfig();
    if (mounted) {
      setState(() {
        _userController.text = cfg['user'] ?? '';
        _passController.text = cfg['pass'] ?? '';
        _hostController.text = cfg['host']?.isNotEmpty == true ? cfg['host']! : 'smtp.gmail.com';
        _portController.text = cfg['port']?.isNotEmpty == true ? cfg['port']! : '465';
      });
    }
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = _userController.text.trim();
    final pass = _passController.text.trim();
    if (user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter sender email and app password')),
      );
      return;
    }

    setState(() => _saving = true);
    await EmailOtpService.saveSmtpConfig(
      user: user,
      pass: pass,
      host: _hostController.text.trim(),
      port: _portController.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedMessage = 'SMTP credentials saved successfully';
    });

    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottomInset + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.border),
                ),
                child: Icon(Icons.mark_email_read_outlined, size: 22, color: palette.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Email Sender Setup',
                      style: GoogleFonts.fraunces(fontSize: 20, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                    Text(
                      'Sends real 6-digit verification codes to user emails',
                      style: GoogleFonts.inter(fontSize: 12, color: palette.mutedInk),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: palette.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'For Gmail: Enter your Gmail address and a 16-character Google App Password (generated from Google Account > Security > 2-Step Verification > App Passwords).',
                    style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: palette.body),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('SENDER GMAIL / EMAIL', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: palette.mutedInk, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          AuthCardTextField(
            controller: _userController,
            hintText: 'e.g. sender@gmail.com',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          Text('16-CHAR APP PASSWORD', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: palette.mutedInk, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          AuthCardTextField(
            controller: _passController,
            hintText: 'xxxx xxxx xxxx xxxx',
            icon: Icons.key_rounded,
            obscureText: _obscurePass,
            suffixIcon: IconButton(
              icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, size: 18, color: palette.mutedInk),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
          ),
          if (_savedMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _savedMessage!,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: palette.accent),
            ),
          ],
          const SizedBox(height: 20),
          WabiSabiButton(
            label: _saving ? 'Saving...' : 'Save & Enable Real Email OTP',
            onTap: _save,
            loading: _saving,
          ),
        ],
      ),
    );
  }
}
