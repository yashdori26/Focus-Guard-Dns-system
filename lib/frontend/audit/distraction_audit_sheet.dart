import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/app_audit_models.dart';
import '../../state_management/app_audit_state.dart';
import '../../state_management/deep_focus_state.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets/app_logo.dart';

class DistractionAuditSheet extends ConsumerStatefulWidget {
  const DistractionAuditSheet({super.key});

  @override
  ConsumerState<DistractionAuditSheet> createState() => _DistractionAuditSheetState();
}

class _DistractionAuditSheetState extends ConsumerState<DistractionAuditSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // Auto-run scan if not already scanned
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(appAuditProvider);
      if (state.report == null && !state.isScanning) {
        ref.read(appAuditProvider.notifier).runScan();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final auditState = ref.watch(appAuditProvider);
    final deepFocusState = ref.watch(deepFocusProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: palette.strictAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: palette.strictAccent.withOpacity(0.3)),
                        ),
                        child: Icon(Icons.radar_rounded, color: palette.strictAccent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Distraction Audit Scanner',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: palette.ink,
                              ),
                            ),
                            Text(
                              'Google Play Store Cross-Verified',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11.5,
                                color: palette.mutedInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: palette.mutedInk),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: palette.border, height: 1),

          // Body
          Expanded(
            child: auditState.isScanning
                ? _buildScanningView(palette)
                : auditState.report != null
                    ? _buildReportView(palette, auditState, deepFocusState)
                    : _buildInitialView(palette),
          ),

          // 1-Tap Block Action Footer
          if (auditState.report != null && !auditState.isScanning)
            _buildFooter(palette, auditState),
        ],
      ),
    );
  }

  Widget _buildScanningView(WabiSabiPalette palette) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.08).animate(
              CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.strictAccent.withOpacity(0.1),
                border: Border.all(color: palette.strictAccent.withOpacity(0.4), width: 2),
              ),
              child: Center(
                child: Icon(Icons.security_update_good_rounded,
                    color: palette.strictAccent, size: 44),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Auditing Installed Applications...',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Cross-verifying Google Play Store installer certificates & isolating user apps from system packages...',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: palette.mutedInk,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialView(WabiSabiPalette palette) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () => ref.read(appAuditProvider.notifier).runScan(),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Start Phone Audit'),
      ),
    );
  }

  Widget _buildReportView(
      WabiSabiPalette palette, AppAuditState state, DeepFocusState deepFocusState) {
    final report = state.report!;
    final filtered = state.filteredApps;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        // Forensic Score Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: _gradeColor(report.auditGrade).withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _gradeColor(report.auditGrade).withOpacity(0.4)),
                ),
                child: Center(
                  child: Text(
                    report.auditGrade,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: _gradeColor(report.auditGrade),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Distraction Exposure Grade',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: palette.mutedInk,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${report.distractionCount} High Distractions',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${report.playStoreVerifiedCount} verified user apps scanned (system apps excluded)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: palette.mutedInk,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: palette.mutedInk, size: 20),
                tooltip: 'Re-scan phone',
                onPressed: () => ref.read(appAuditProvider.notifier).runScan(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip(palette, state, 'all', 'All Apps (${report.playStoreUserApps.length})'),
              _buildFilterChip(palette, state, 'distractions', 'Distractions (${report.distractionCount})'),
              _buildFilterChip(palette, state, 'social', 'Social Media'),
              _buildFilterChip(palette, state, 'video', 'Streaming'),
              _buildFilterChip(palette, state, 'gaming', 'Games'),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Select All / Deselect All Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${filtered.length} Applications',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => ref.read(appAuditProvider.notifier).selectAll(),
                  child: Text('Select All', style: TextStyle(color: palette.ink, fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => ref.read(appAuditProvider.notifier).deselectAll(),
                  child: Text('Deselect', style: TextStyle(color: palette.mutedInk, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Application Rows
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: Text(
                'No applications found in this category.',
                style: TextStyle(color: palette.mutedInk, fontSize: 13),
              ),
            ),
          )
        else
          ...filtered.map((app) {
            final isSelected = state.selectedPackages.contains(app.packageName);
            final isAlreadyBlocked = deepFocusState.websites.any((w) =>
                w.packages.contains(app.packageName) ||
                w.name.toLowerCase() == app.appName.toLowerCase());

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? palette.strictAccent.withOpacity(0.5) : palette.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    activeColor: palette.strictAccent,
                    onChanged: (val) {
                      ref.read(appAuditProvider.notifier).toggleAppSelection(app.packageName);
                    },
                  ),
                  const SizedBox(width: 4),
                  AppLogo(
                    appName: app.appName,
                    packageName: app.packageName,
                    size: 38,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                app.appName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: palette.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (app.isPlayStoreVerified)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_rounded, size: 10, color: Colors.green.shade700),
                                    const SizedBox(width: 2),
                                    Text(
                                      'PLAY',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              app.categoryDisplayName,
                              style: TextStyle(fontSize: 11, color: palette.mutedInk),
                            ),
                            if (isAlreadyBlocked) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: palette.border,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'BLOCKED',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: palette.mutedInk),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Distraction Score Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: app.isDistraction
                          ? palette.strictAccent.withOpacity(0.12)
                          : palette.border.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${app.distractionScore}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: app.isDistraction ? palette.strictAccent : palette.mutedInk,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildFilterChip(
      WabiSabiPalette palette, AppAuditState state, String filterKey, String label) {
    final isSelected = state.activeFilter == filterKey;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: palette.ink,
        backgroundColor: palette.surface,
        labelStyle: TextStyle(
          color: isSelected ? palette.canvas : palette.ink,
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: isSelected ? palette.ink : palette.border),
        ),
        onSelected: (_) => ref.read(appAuditProvider.notifier).setFilter(filterKey),
      ),
    );
  }

  Widget _buildFooter(WabiSabiPalette palette, AppAuditState state) {
    final count = state.selectedPackages.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: count == 0
                ? null
                : () {
                    final blockedCount =
                        ref.read(appAuditProvider.notifier).oneTapBlockSelectedDistractions();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('🛡️ Successfully shielded $blockedCount distracting apps.'),
                        backgroundColor: palette.surface,
                      ),
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.strictAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.bolt_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  count > 0 ? '1-TAP BLOCK ($count APPS)' : 'SELECT APPS TO BLOCK',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _gradeColor(String grade) {
    if (grade.startsWith('A')) return const Color(0xFF10B981);
    if (grade.startsWith('B')) return const Color(0xFF3B82F6);
    if (grade.startsWith('C')) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}
