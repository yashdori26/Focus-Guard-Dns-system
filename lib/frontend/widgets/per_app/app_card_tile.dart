import 'package:flutter/material.dart';
import 'package:focus_dns/engine/per_app/catalog/app_category_metadata.dart';
import 'package:focus_dns/engine/per_app/catalog/app_definition.dart';
import 'package:focus_dns/engine/per_app/models/app_lock_config.dart';
import '../app_logo.dart';

/// Interactive tile displaying app lock status, category badge, and quick action toggle.
class AppCardTile extends StatelessWidget {
  final AppDefinition definition;
  final AppLockConfig? config;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleLock;

  const AppCardTile({
    super.key,
    required this.definition,
    required this.config,
    required this.onTap,
    required this.onToggleLock,
  });

  String _formatRemaining(int seconds) {
    if (seconds <= 0) return '0s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m >= 60) {
      final h = m ~/ 60;
      final remM = m % 60;
      return '${h}h ${remM}m';
    }
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final meta = AppCategoryMetadata.of(definition.category);
    final isLocked = config?.isCurrentlyLocked ?? false;
    final mode = config?.mode ?? AppLockMode.unlocked;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLocked ? const Color(0xFFEF4444).withValues(alpha: 0.6) : Colors.white10,
              width: isLocked ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // App Logo
              AppLogo(
                appName: definition.name,
                packageName: definition.primaryPackage,
                size: 44,
              ),
              const SizedBox(width: 14),

              // Title and metadata
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            definition.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (definition.isExtremeTrap) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFDC2626), width: 0.8),
                            ),
                            child: const Text(
                              'TRAP',
                              style: TextStyle(color: Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          meta.displayName,
                          style: TextStyle(
                            color: meta.accentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: TextStyle(color: Colors.white24, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isLocked
                              ? (mode == AppLockMode.independentTimer
                                  ? 'Locked (${_formatRemaining(config!.remainingTimerSeconds)})'
                                  : 'Locked (${mode.name})')
                              : 'Unlocked',
                          style: TextStyle(
                            color: isLocked ? const Color(0xFFEF4444) : Colors.white54,
                            fontSize: 12,
                            fontWeight: isLocked ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Lock Switch
              Switch(
                value: isLocked,
                activeColor: const Color(0xFFEF4444),
                inactiveThumbColor: Colors.white38,
                inactiveTrackColor: Colors.white12,
                onChanged: onToggleLock,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
