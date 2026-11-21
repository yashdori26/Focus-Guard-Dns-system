import 'package:flutter/material.dart';

/// Duration selector offering preset chips and granular slider controls from 5m to 24h.
class DurationWheelPicker extends StatelessWidget {
  final int selectedMinutes;
  final ValueChanged<int> onDurationChanged;

  const DurationWheelPicker({
    super.key,
    required this.selectedMinutes,
    required this.onDurationChanged,
  });

  static const List<int> presets = [15, 30, 60, 120, 240, 480, 720, 1440];

  static String formatMinutes(int mins) {
    if (mins < 60) return '$mins min';
    final hours = mins ~/ 60;
    final rem = mins % 60;
    if (rem == 0) return '$hours hr${hours > 1 ? 's' : ''}';
    return '$hours hr $rem min';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Lock Duration',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
              ),
              child: Text(
                formatMinutes(selectedMinutes),
                style: const TextStyle(
                  color: Color(0xFF60A5FA),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((mins) {
            final isSelected = selectedMinutes == mins;
            return ChoiceChip(
              label: Text(formatMinutes(mins)),
              selected: isSelected,
              onSelected: (_) => onDurationChanged(mins),
              selectedColor: const Color(0xFF3B82F6),
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              side: BorderSide(
                color: isSelected ? const Color(0xFF60A5FA) : Colors.white12,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Slider(
          value: selectedMinutes.toDouble().clamp(5.0, 1440.0),
          min: 5.0,
          max: 1440.0,
          divisions: 95,
          activeColor: const Color(0xFF3B82F6),
          inactiveColor: Colors.white12,
          onChanged: (val) => onDurationChanged(val.round()),
        ),
      ],
    );
  }
}
