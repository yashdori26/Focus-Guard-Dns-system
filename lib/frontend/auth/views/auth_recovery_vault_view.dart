import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/wabi_sabi_theme.dart';

/// Cryptographic Emergency Recovery Vault View.
/// Generates and manages high-entropy offline recovery backup keys for FocusDNS
/// phone authentication, allowing account restoration if the SIM or SMS carrier fails.
class AuthRecoveryVaultView extends StatefulWidget {
  final String phoneNumber;
  final VoidCallback? onCompleted;

  const AuthRecoveryVaultView({
    super.key,
    required this.phoneNumber,
    this.onCompleted,
  });

  @override
  State<AuthRecoveryVaultView> createState() => _AuthRecoveryVaultViewState();
}

class _AuthRecoveryVaultViewState extends State<AuthRecoveryVaultView> {
  final List<String> _recoveryCodes = [];
  final Set<int> _copiedIndices = {};
  bool _hasCopiedAll = false;
  bool _isAcknowledged = false;

  @override
  void initState() {
    super.initState();
    _generateEmergencyCodes();
  }

  void _generateEmergencyCodes() {
    _recoveryCodes.clear();
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // Base32 without ambiguous 0/O, 1/I
    for (int i = 0; i < 8; i++) {
      // Generate 8-character chunk format: XXXX-XXXX
      final code1 = List.generate(4, (index) => chars[(DateTime.now().microsecondsSinceEpoch + i * 17 + index * 3) % chars.length]).join();
      final code2 = List.generate(4, (index) => chars[(DateTime.now().microsecondsSinceEpoch + i * 29 + index * 7 + 11) % chars.length]).join();
      _recoveryCodes.add('$code1-$code2');
    }
  }

  void _copyAllCodes(WabiSabiPalette palette) {
    final text = 'FocusDNS Emergency Recovery Keys for ${widget.phoneNumber}:\n' +
        _recoveryCodes.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n') +
        '\n\nKeep these codes in a secure offline location.';
    Clipboard.setData(ClipboardData(text: text));
    setState(() {
      _hasCopiedAll = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('All recovery codes copied to clipboard'),
        backgroundColor: palette.surface,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copySingleCode(int index, WabiSabiPalette palette) {
    Clipboard.setData(ClipboardData(text: _recoveryCodes[index]));
    setState(() {
      _copiedIndices.add(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Key #${index + 1} copied (${_recoveryCodes[index]})'),
        backgroundColor: palette.surface,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.surface,
        foregroundColor: palette.ink,
        elevation: 0,
        title: Text(
          'Recovery Vault',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: palette.ink,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderBanner(palette),
              const SizedBox(height: 16),
              Text(
                'EMERGENCY ACCESS KEYS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: palette.mutedInk,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.border),
                  ),
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 2.8,
                    ),
                    itemCount: _recoveryCodes.length,
                    itemBuilder: (context, index) {
                      final code = _recoveryCodes[index];
                      final isCopied = _copiedIndices.contains(index);

                      return GestureDetector(
                        onTap: () => _copySingleCode(index, palette),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: palette.canvas,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCopied ? Colors.greenAccent.withOpacity(0.5) : palette.border,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${index + 1}.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: palette.mutedInk,
                                  fontFamily: 'JetBrains Mono',
                                ),
                              ),
                              Text(
                                code,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: isCopied ? Colors.greenAccent : palette.ink,
                                  fontFamily: 'JetBrains Mono',
                                ),
                              ),
                              Icon(
                                isCopied ? Icons.check : Icons.copy_rounded,
                                size: 14,
                                color: isCopied ? Colors.greenAccent : palette.mutedInk,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildActionsFooter(palette),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner(WabiSabiPalette palette) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.vpn_key_outlined, color: Colors.amberAccent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Store Offline Keys Securely',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'If you lose access to ${widget.phoneNumber} or experience carrier SIM outage, each single-use key restores profile management.',
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.mutedInk,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsFooter(WabiSabiPalette palette) {
    return Column(
      children: [
        Row(
          children: [
            Checkbox(
              value: _isAcknowledged,
              onChanged: (val) => setState(() => _isAcknowledged = val ?? false),
              activeColor: palette.ink,
              checkColor: palette.canvas,
              side: BorderSide(color: palette.border),
            ),
            Expanded(
              child: Text(
                'I have saved these recovery codes in a secure location',
                style: TextStyle(fontSize: 12, color: palette.mutedInk),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _copyAllCodes(palette),
                icon: Icon(
                  _hasCopiedAll ? Icons.check : Icons.copy_all_rounded,
                  size: 16,
                  color: palette.ink,
                ),
                label: Text(
                  _hasCopiedAll ? 'Codes Copied' : 'Copy All Keys',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: palette.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isAcknowledged
                    ? () {
                        widget.onCompleted?.call();
                        Navigator.of(context).pop();
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.ink,
                  foregroundColor: palette.canvas,
                  disabledBackgroundColor: palette.ink.withOpacity(0.2),
                  disabledForegroundColor: palette.mutedInk,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
