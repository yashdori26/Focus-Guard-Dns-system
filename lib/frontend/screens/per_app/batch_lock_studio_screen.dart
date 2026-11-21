import 'package:flutter/material.dart';
import 'package:focus_dns/engine/per_app/catalog/app_category_metadata.dart';
import 'package:focus_dns/engine/per_app/catalog/comprehensive_app_catalog.dart';
import 'package:focus_dns/engine/per_app/core/per_app_coordinator.dart';
import 'package:focus_dns/engine/per_app/per_app_database.dart';

/// Screen allowing one-tap batch locking across entire categories of applications.
class BatchLockStudioScreen extends StatefulWidget {
  final PerAppCoordinator coordinator;

  const BatchLockStudioScreen({
    super.key,
    required this.coordinator,
  });

  @override
  State<BatchLockStudioScreen> createState() => _BatchLockStudioScreenState();
}

class _BatchLockStudioScreenState extends State<BatchLockStudioScreen> {
  int _selectedBatchDurationMinutes = 240; // 4 hours

  void _lockCategory(AppCategory category) async {
    await widget.coordinator.lockCategory(
      category,
      durationMinutes: _selectedBatchDurationMinutes,
    );
    final meta = AppCategoryMetadata.of(category);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Locked all ${meta.displayName} applications for ${_selectedBatchDurationMinutes ~/ 60} hours'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Batch Category Locks',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Duration for Batch Action',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildDurationChip(60, '1 Hour'),
                const SizedBox(width: 8),
                _buildDurationChip(120, '2 Hours'),
                const SizedBox(width: 8),
                _buildDurationChip(240, '4 Hours'),
                const SizedBox(width: 8),
                _buildDurationChip(480, '8 Hours'),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'One-Tap Category Shields',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // High-Impact Category Cards
            _buildCategoryBatchTile(
              AppCategory.shortFormVideo,
              'Lock All Short-Form Video',
              'Immediately locks TikTok, Instagram Reels, and YouTube Shorts.',
              Icons.flash_on_rounded,
            ),
            const SizedBox(height: 12),
            _buildCategoryBatchTile(
              AppCategory.social,
              'Lock All Social Networks',
              'Immediately locks Instagram, X, Reddit, Facebook, and Threads.',
              Icons.share_rounded,
            ),
            const SizedBox(height: 12),
            _buildCategoryBatchTile(
              AppCategory.gaming,
              'Lock All Mobile Games',
              'Immediately locks PUBG, Roblox, Genshin Impact, and Brawl Stars.',
              Icons.sports_esports_rounded,
            ),
            const SizedBox(height: 12),
            _buildCategoryBatchTile(
              AppCategory.adult,
              'Block All Adult & 18+ Content',
              'Strict zero-tolerance block on all pornographic domains and apps.',
              Icons.warning_amber_rounded,
            ),
            const SizedBox(height: 12),
            _buildCategoryBatchTile(
              AppCategory.gambling,
              'Block All Gambling & Betting',
              'Strict zero-tolerance block on Stake, Bet365, casinos, and sportsbooks.',
              Icons.casino_rounded,
            ),
            const SizedBox(height: 12),
            _buildCategoryBatchTile(
              AppCategory.shopping,
              'Lock All Impulse E-Commerce',
              'Locks Amazon, Shein, Temu, and AliExpress flash deals.',
              Icons.shopping_bag_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationChip(int minutes, String label) {
    final isSelected = _selectedBatchDurationMinutes == minutes;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedBatchDurationMinutes = minutes),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF60A5FA) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBatchTile(
    AppCategory category,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final meta = AppCategoryMetadata.of(category);
    final count = ComprehensiveAppCatalog.getByCategory(category).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: meta.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: meta.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: meta.accentColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count configured apps affected',
                  style: TextStyle(color: meta.accentColor, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: meta.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: () => _lockCategory(category),
            child: const Text(
              'LOCK',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
