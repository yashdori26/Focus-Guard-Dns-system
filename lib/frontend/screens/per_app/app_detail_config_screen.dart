import 'package:flutter/material.dart';
import 'package:focus_dns/engine/per_app/catalog/app_category_metadata.dart';
import 'package:focus_dns/engine/per_app/catalog/app_definition.dart';
import 'package:focus_dns/engine/per_app/catalog/productive_alternative_registry.dart';
import 'package:focus_dns/engine/per_app/core/per_app_coordinator.dart';
import 'package:focus_dns/engine/per_app/models/app_lock_config.dart';
import 'package:focus_dns/frontend/widgets/per_app/dopamine_risk_gauge.dart';
import 'package:focus_dns/frontend/widgets/per_app/duration_wheel_picker.dart';
import 'package:focus_dns/frontend/widgets/per_app/usage_hourly_bar_chart.dart';

/// Comprehensive configuration studio for an individual application.
class AppDetailConfigScreen extends StatefulWidget {
  final AppDefinition definition;
  final PerAppCoordinator coordinator;

  const AppDetailConfigScreen({
    super.key,
    required this.definition,
    required this.coordinator,
  });

  @override
  State<AppDetailConfigScreen> createState() => _AppDetailConfigScreenState();
}

class _AppDetailConfigScreenState extends State<AppDetailConfigScreen> {
  late AppLockConfig _currentConfig;
  late int _selectedMinutes;
  late int _selectedQuotaMinutes;
  late AppLockMode _selectedMode;
  late StrictnessTier _selectedStrictness;

  @override
  void initState() {
    super.initState();
    final existing = widget.coordinator.configs[widget.definition.id];
    _currentConfig = existing ??
        AppLockConfig(
          appId: widget.definition.id,
          packageName: widget.definition.primaryPackage,
          allocatedTimerMinutes: widget.definition.defaultAllocatedLockMinutes,
          dailyQuotaMinutes: widget.definition.defaultDailyQuotaMinutes,
          strictness: widget.definition.isExtremeTrap
              ? StrictnessTier.strictUnbreakable
              : StrictnessTier.frictionProtected,
          mode: widget.definition.isExtremeTrap
              ? AppLockMode.permanentBlock
              : AppLockMode.independentTimer,
        );

    _selectedMinutes = _currentConfig.allocatedTimerMinutes;
    _selectedQuotaMinutes = _currentConfig.dailyQuotaMinutes;
    _selectedMode = _currentConfig.mode == AppLockMode.unlocked
        ? AppLockMode.independentTimer
        : _currentConfig.mode;
    _selectedStrictness = _currentConfig.strictness;
  }

  void _applyLock() async {
    if (_selectedMode == AppLockMode.independentTimer) {
      await widget.coordinator.lockAppTimer(
        widget.definition.id,
        durationMinutes: _selectedMinutes,
        strictness: _selectedStrictness,
      );
    } else if (_selectedMode == AppLockMode.dailyQuota) {
      await widget.coordinator.configureDailyQuota(
        widget.definition.id,
        _selectedQuotaMinutes,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.definition.name} rules updated successfully'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  void _unlock() async {
    final success = await widget.coordinator.unlockApp(widget.definition.id);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.definition.name} unlocked'),
            backgroundColor: const Color(0xFF3B82F6),
          ),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot unlock: App is in Strict Unbreakable mode!'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = AppCategoryMetadata.of(widget.definition.category);
    final isLocked = _currentConfig.isCurrentlyLocked;
    final productiveSwap = widget.definition.recommendedProductiveSwapId != null
        ? ProductiveAlternativeRegistry.findById(widget.definition.recommendedProductiveSwapId!)
        : ProductiveAlternativeRegistry.getSuggestedForCategory(widget.definition.category.name);

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Text(
          widget.definition.name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero App Header
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: meta.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: meta.primaryColor.withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      widget.definition.iconGlyph,
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.definition.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.definition.primaryPackage,
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: meta.primaryColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              meta.displayName,
                              style: TextStyle(
                                color: meta.accentColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isLocked)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'LOCKED',
                                style: TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                DopamineRiskGauge(
                  score: widget.definition.dopamineScore,
                  size: 64,
                  showLabel: false,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Description card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF131B2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                widget.definition.description,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(height: 24),

            // Mode Selector
            const Text(
              'Enforcement Policy',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildModeChoice(AppLockMode.independentTimer, 'Timer Lock', Icons.timer_rounded),
                const SizedBox(width: 10),
                _buildModeChoice(AppLockMode.dailyQuota, 'Daily Allowance', Icons.hourglass_top_rounded),
                const SizedBox(width: 10),
                _buildModeChoice(AppLockMode.permanentBlock, 'Strict Block', Icons.block_rounded),
              ],
            ),
            const SizedBox(height: 24),

            // Mode-specific configuration view
            if (_selectedMode == AppLockMode.independentTimer) ...[
              DurationWheelPicker(
                selectedMinutes: _selectedMinutes,
                onDurationChanged: (m) => setState(() => _selectedMinutes = m),
              ),
            ] else if (_selectedMode == AppLockMode.dailyQuota) ...[
              const Text(
                'Daily Quota Limit',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Maximum Screen Time / Day:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text(
                    '$_selectedQuotaMinutes minutes',
                    style: const TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Slider(
                value: _selectedQuotaMinutes.toDouble(),
                min: 5.0,
                max: 180.0,
                divisions: 35,
                activeColor: const Color(0xFF3B82F6),
                inactiveColor: Colors.white12,
                onChanged: (val) => setState(() => _selectedQuotaMinutes = val.round()),
              ),
            ],
            const SizedBox(height: 24),

            // Strictness Tier Selector
            const Text(
              'Strictness Level',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF131B2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  _buildStrictnessOption(
                    StrictnessTier.strictUnbreakable,
                    'Strict Unbreakable (Recommended)',
                    'Zero bypass. Cannot be unlocked until duration expires.',
                    const Color(0xFFEF4444),
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  _buildStrictnessOption(
                    StrictnessTier.frictionProtected,
                    'Friction Protected',
                    'Allows emergency unlock only after typing a mindful oath.',
                    const Color(0xFFF59E0B),
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  _buildStrictnessOption(
                    StrictnessTier.flexible,
                    'Flexible',
                    'Gentle reminder. Can be disabled at any time.',
                    const Color(0xFF3B82F6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Productive Swap Card
            const Text(
              'Recommended Productive Swap',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Text(productiveSwap.iconGlyph, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productiveSwap.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          productiveSwap.slogan,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Action Buttons
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _applyLock,
                child: const Text(
                  'APPLY FOCUS RULES',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
            if (isLocked) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _unlock,
                  child: const Text(
                    'REQUEST UNLOCK',
                    style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeChoice(AppLockMode mode, String label, IconData icon) {
    final isSelected = _selectedMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3B82F6).withValues(alpha: 0.2) : const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF3B82F6) : Colors.white10,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF60A5FA) : Colors.white54, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStrictnessOption(StrictnessTier tier, String title, String subtitle, Color color) {
    final isSelected = _selectedStrictness == tier;
    return InkWell(
      onTap: () => setState(() => _selectedStrictness = tier),
      child: Row(
        children: [
          Radio<StrictnessTier>(
            value: tier,
            groupValue: _selectedStrictness,
            activeColor: color,
            onChanged: (val) {
              if (val != null) setState(() => _selectedStrictness = val);
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? color : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
