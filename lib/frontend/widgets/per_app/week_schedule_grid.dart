import 'package:flutter/material.dart';

/// Interactive 7-day selector grid for recurring calendar schedules.
class WeekScheduleGrid extends StatelessWidget {
  final List<int> selectedDays; // 1 = Monday, 7 = Sunday
  final ValueChanged<List<int>> onSelectionChanged;
  final bool readOnly;

  const WeekScheduleGrid({
    super.key,
    required this.selectedDays,
    required this.onSelectionChanged,
    this.readOnly = false,
  });

  static const List<MapEntry<int, String>> _days = [
    MapEntry(1, 'M'),
    MapEntry(2, 'T'),
    MapEntry(3, 'W'),
    MapEntry(4, 'T'),
    MapEntry(5, 'F'),
    MapEntry(6, 'S'),
    MapEntry(7, 'S'),
  ];

  void _toggleDay(int day) {
    if (readOnly) return;
    final updated = List<int>.from(selectedDays);
    if (updated.contains(day)) {
      if (updated.length > 1) {
        updated.remove(day);
      }
    } else {
      updated.add(day);
      updated.sort();
    }
    onSelectionChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _days.map((entry) {
        final isSelected = selectedDays.contains(entry.key);
        final isWeekend = entry.key >= 6;

        return GestureDetector(
          onTap: () => _toggleDay(entry.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF3B82F6)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF60A5FA)
                    : (isWeekend ? Colors.white24 : Colors.white12),
                width: 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                entry.value,
                style: TextStyle(
                  color: isSelected ? Colors.white : (isWeekend ? Colors.white54 : Colors.white70),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
