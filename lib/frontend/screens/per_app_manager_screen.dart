import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../engine/per_app/per_app_database.dart';
import '../../engine/per_app/per_app_scheduler.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets/app_logo.dart';
import 'per_app/per_app_main_studio_screen.dart';

/// Riverpod provider for the PerAppScheduler.
final perAppSchedulerProvider = ChangeNotifierProvider<PerAppScheduler>((ref) {
  return PerAppScheduler();
});

/// Full-screen App Lockout Studio for managing independent per-app timers and restrictions.
class PerAppManagerScreen extends ConsumerStatefulWidget {
  const PerAppManagerScreen({super.key});

  @override
  ConsumerState<PerAppManagerScreen> createState() => _PerAppManagerScreenState();
}

class _PerAppManagerScreenState extends ConsumerState<PerAppManagerScreen> {
  String _searchQuery = '';
  AppCategory? _selectedCategory;

  String _formatSeconds(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}h ${m}m ${s}s';
    }
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final scheduler = ref.watch(perAppSchedulerProvider);
    final allApps = scheduler.allAppsList;

    // Filter apps by query & category
    final filtered = allApps.where((app) {
      final matchesQuery = _searchQuery.isEmpty ||
          app.appName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          app.packageName.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCategory = _selectedCategory == null || app.category == _selectedCategory;
      return matchesQuery && matchesCategory;
    }).toList();

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        elevation: 0,
        iconTheme: IconThemeData(color: palette.ink),
        title: Text(
          'App Lockout Manager',
          style: GoogleFonts.plusJakartaSans(
            color: palette.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_clock_rounded, size: 14, color: palette.strictAccent),
                const SizedBox(width: 4),
                Text(
                  '${scheduler.activeLockedApps.length} LOCKED',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: palette.strictAccent,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.dashboard_customize_rounded),
            tooltip: 'Enterprise Studio',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PerAppMainStudioScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search applications or packages...',
                  hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: palette.mutedInk),
                  prefixIcon: Icon(Icons.search_rounded, color: palette.mutedInk, size: 20),
                  filled: true,
                  fillColor: palette.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.ink, width: 1.5),
                  ),
                ),
              ),
            ),

            // 2. Category Filter Chips
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _buildCategoryFilterChip(label: 'All Apps', category: null, palette: palette),
                  _buildCategoryFilterChip(label: 'Social', category: AppCategory.social, palette: palette),
                  _buildCategoryFilterChip(label: 'Short-Form Video', category: AppCategory.shortFormVideo, palette: palette),
                  _buildCategoryFilterChip(label: 'Long-Form Video', category: AppCategory.longFormVideo, palette: palette),
                  _buildCategoryFilterChip(label: 'Gaming', category: AppCategory.gaming, palette: palette),
                  _buildCategoryFilterChip(label: 'Shopping', category: AppCategory.shopping, palette: palette),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 3. App List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No matching applications found.',
                        style: GoogleFonts.plusJakartaSans(color: palette.mutedInk, fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 80),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _buildAppCard(filtered[index], scheduler, palette);
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  scheduler.lockCategory(AppCategory.shortFormVideo, durationMinutes: 240);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Locked all short-form video apps for 4 hours.'),
                      backgroundColor: palette.ink,
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: palette.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'LOCK ALL SHORT VIDEO (4h)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  scheduler.lockCategory(AppCategory.social, durationMinutes: 480);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Locked all social apps for 8 hours.'),
                      backgroundColor: palette.ink,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.ink,
                  foregroundColor: palette.canvas,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'LOCK ALL SOCIAL (8h)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilterChip({
    required String label,
    required AppCategory? category,
    required WabiSabiPalette palette,
  }) {
    final isSelected = _selectedCategory == category;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? palette.ink : palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? palette.ink : palette.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? palette.canvas : palette.mutedInk,
          ),
        ),
      ),
    );
  }

  Widget _buildAppCard(ManagedAppRecord app, PerAppScheduler scheduler, WabiSabiPalette palette) {
    final isLocked = app.isLockActive;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLocked ? palette.strictAccent.withOpacity(0.5) : palette.border,
          width: isLocked ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppLogo(appName: app.appName, packageName: app.packageName, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  app.appName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
              ),
              _buildRiskBadge(app.riskRating, palette),
            ],
          ),
          const SizedBox(height: 12),

          // Duration Slider / Lock Status
          if (!isLocked) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Independent Lock Duration:',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: palette.mutedInk),
                ),
                Text(
                  _formatDurationMinutes(app.allocatedLockMinutes),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: palette.ink,
                inactiveTrackColor: palette.border,
                thumbColor: palette.ink,
                trackHeight: 3,
              ),
              child: Slider(
                value: app.allocatedLockMinutes.toDouble(),
                min: 5,
                max: 480,
                divisions: 95,
                onChanged: (val) {
                  scheduler.setAllocatedMinutes(app.appId, val.toInt());
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => scheduler.lockApp(app.appId),
                icon: const Icon(Icons.lock_outline_rounded, size: 16),
                label: Text('ENGAGE ${app.allocatedLockMinutes}m LOCKOUT'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.ink,
                  foregroundColor: palette.canvas,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: palette.strictAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.hourglass_top_rounded, size: 16, color: palette.strictAccent),
                      const SizedBox(width: 8),
                      Text(
                        'LOCKED DOWN',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: palette.strictAccent,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _formatSeconds(app.remainingLockSeconds),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: palette.strictAccent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => scheduler.unlockApp(app.appId),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: palette.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  'UNLOCK NOW',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: palette.mutedInk,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDurationMinutes(int minutes) {
    if (minutes >= 60) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      return m > 0 ? '${h}h ${m}m' : '${h} hours';
    }
    return '$minutes minutes';
  }

  Widget _buildRiskBadge(DopamineRiskRating risk, WabiSabiPalette palette) {
    Color color;
    String label;

    switch (risk) {
      case DopamineRiskRating.extremeDopamineTrap:
        color = palette.strictAccent;
        label = 'EXTREME TRAP';
        break;
      case DopamineRiskRating.high:
        color = const Color(0xFFE67E22);
        label = 'HIGH RISK';
        break;
      case DopamineRiskRating.moderate:
        color = const Color(0xFFF1C40F);
        label = 'MODERATE';
        break;
      case DopamineRiskRating.low:
        color = const Color(0xFF2ECC71);
        label = 'LOW';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
