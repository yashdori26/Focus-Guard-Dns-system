import 'package:flutter/material.dart';
import 'package:focus_dns/engine/per_app/catalog/app_definition.dart';
import 'package:focus_dns/engine/per_app/catalog/comprehensive_app_catalog.dart';
import 'package:focus_dns/engine/per_app/core/per_app_coordinator.dart';
import 'package:focus_dns/engine/per_app/models/recurring_schedule_rule.dart';
import 'package:focus_dns/frontend/widgets/per_app/week_schedule_grid.dart';

/// Screen managing weekly recurring calendar focus blocks.
class RecurringSchedulesScreen extends StatefulWidget {
  final PerAppCoordinator coordinator;

  const RecurringSchedulesScreen({
    super.key,
    required this.coordinator,
  });

  @override
  State<RecurringSchedulesScreen> createState() => _RecurringSchedulesScreenState();
}

class _RecurringSchedulesScreenState extends State<RecurringSchedulesScreen> {
  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_onUpdate);
    super.dispose();
  }

  void _showAddRuleDialog() {
    String label = 'Workday Deep Focus';
    String selectedAppId = 'instagram';
    List<int> selectedDays = [1, 2, 3, 4, 5]; // Mon-Fri
    int startMinute = 540; // 09:00 AM
    int endMinute = 1020; // 05:00 PM

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create Recurring Focus Block',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Block Label',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                    controller: TextEditingController(text: label),
                    onChanged: (val) => label = val,
                  ),
                  const SizedBox(height: 16),
                  const Text('Active Days of Week:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  WeekScheduleGrid(
                    selectedDays: selectedDays,
                    onSelectionChanged: (days) => setModalState(() => selectedDays = days),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Time Window: ${_formatMinute(startMinute)} — ${_formatMinute(endMinute)}',
                        style: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        final newRule = RecurringScheduleRule(
                          id: 'rule_${DateTime.now().millisecondsSinceEpoch}',
                          appId: selectedAppId,
                          packageName: 'com.instagram.android',
                          label: label,
                          daysOfWeek: selectedDays,
                          startMinuteOfDay: startMinute,
                          endMinuteOfDay: endMinute,
                        );
                        await widget.coordinator.addRecurringSchedule(newRule);
                        if (mounted) Navigator.of(ctx).pop();
                      },
                      child: const Text('SAVE SCHEDULE RULE', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static String _formatMinute(int totalMinutes) {
    final hour = (totalMinutes ~/ 60).clamp(0, 23);
    final minute = (totalMinutes % 60).clamp(0, 59);
    final hStr = hour.toString().padLeft(2, '0');
    final mStr = minute.toString().padLeft(2, '0');
    return '$hStr:$mStr';
  }

  @override
  Widget build(BuildContext context) {
    final rules = widget.coordinator.recurringEngine.allRules;

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Weekly Focus Schedules',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            tooltip: 'Add Schedule Rule',
            onPressed: _showAddRuleDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Automated Calendar Blocks',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Apps automatically lock and unlock based on your weekly work hours.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),

            if (rules.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF131B2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: Colors.white38, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'No recurring schedules configured yet.',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _showAddRuleDialog,
                        child: const Text('Create Workday Focus Block'),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              ...rules.map((rule) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131B2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            rule.label,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                            onPressed: () => widget.coordinator.removeRecurringSchedule(rule.id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded, color: Color(0xFF60A5FA), size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '${rule.startTimeFormatted} — ${rule.endTimeFormatted}',
                            style: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      WeekScheduleGrid(
                        selectedDays: rule.daysOfWeek,
                        readOnly: true,
                        onSelectionChanged: (_) {},
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
