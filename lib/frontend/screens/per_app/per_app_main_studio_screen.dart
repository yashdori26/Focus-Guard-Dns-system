import 'package:flutter/material.dart';
import 'package:focus_dns/engine/per_app/catalog/app_category_metadata.dart';
import 'package:focus_dns/engine/per_app/catalog/app_definition.dart';
import 'package:focus_dns/engine/per_app/catalog/comprehensive_app_catalog.dart';
import 'package:focus_dns/engine/per_app/core/per_app_coordinator.dart';
import 'package:focus_dns/engine/per_app/per_app_database.dart';
import 'package:focus_dns/frontend/widgets/per_app/app_card_tile.dart';
import 'app_detail_config_screen.dart';
import 'batch_lock_studio_screen.dart';
import 'daily_quota_studio_screen.dart';
import 'recurring_schedules_screen.dart';

/// Master studio screen for managing independent per-app timers, category filters, and lock states.
class PerAppMainStudioScreen extends StatefulWidget {
  final PerAppCoordinator? coordinator;

  const PerAppMainStudioScreen({
    super.key,
    this.coordinator,
  });

  @override
  State<PerAppMainStudioScreen> createState() => _PerAppMainStudioScreenState();
}

class _PerAppMainStudioScreenState extends State<PerAppMainStudioScreen> {
  late final PerAppCoordinator _coordinator;
  AppCategory? _selectedCategory;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _coordinator = widget.coordinator ?? PerAppCoordinator();
    _coordinator.addListener(_onCoordinatorUpdate);
  }

  void _onCoordinatorUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _coordinator.removeListener(_onCoordinatorUpdate);
    if (widget.coordinator == null) {
      _coordinator.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  List<AppDefinition> _filterApps() {
    return ComprehensiveAppCatalog.allDefinitions.where((app) {
      if (_selectedCategory != null && app.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesName = app.name.toLowerCase().contains(query);
        final matchesPackage = app.primaryPackage.toLowerCase().contains(query);
        final matchesDomain = app.networkDomains.any((d) => d.toLowerCase().contains(query));
        if (!matchesName && !matchesPackage && !matchesDomain) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filterApps();
    final activeLocksCount = _coordinator.activeLocks.length;

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Per-App Lockout Studio',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Colors.white70),
            tooltip: 'Batch Category Locks',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BatchLockStudioScreen(coordinator: _coordinator),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.pie_chart_rounded, color: Colors.white70),
            tooltip: 'Daily Quota Manager',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DailyQuotaStudioScreen(coordinator: _coordinator),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded, color: Colors.white70),
            tooltip: 'Weekly Recurring Schedules',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RecurringSchedulesScreen(coordinator: _coordinator),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Hero metrics card
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('MONITORED', '${ComprehensiveAppCatalog.allDefinitions.length}', const Color(0xFF3B82F6)),
                Container(width: 1, height: 36, color: Colors.white12),
                _buildStatItem('ACTIVE LOCKS', '$activeLocksCount', const Color(0xFFEF4444)),
                Container(width: 1, height: 36, color: Colors.white12),
                _buildStatItem('DEFENSE', 'Strict 0-Bypass', const Color(0xFF10B981)),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search app, package, or domain...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white38),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF131B2E),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Category Chips horizontal list
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildCategoryFilterChip(null, 'All Apps'),
                ...AppCategoryMetadata.registry.entries.map((entry) {
                  return _buildCategoryFilterChip(entry.key, entry.value.displayName);
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // App List
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'No matching applications found.',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final app = filtered[index];
                      final config = _coordinator.configs[app.id];

                      return AppCardTile(
                        definition: app,
                        config: config,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AppDetailConfigScreen(
                                definition: app,
                                coordinator: _coordinator,
                              ),
                            ),
                          );
                        },
                        onToggleLock: (shouldLock) {
                          if (shouldLock) {
                            _coordinator.lockAppTimer(app.id);
                          } else {
                            _coordinator.unlockApp(app.id);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryFilterChip(AppCategory? category, String label) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedCategory = category),
        backgroundColor: const Color(0xFF131B2E),
        selectedColor: const Color(0xFF3B82F6),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        side: BorderSide(
          color: isSelected ? const Color(0xFF60A5FA) : Colors.white10,
        ),
      ),
    );
  }
}
