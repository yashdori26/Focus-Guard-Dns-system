// FocusDNS Columnar Timeseries Chart Widget - Custom Multi-Series Canvas Painter

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/enterprise_models.dart';

class ColumnarTimeseriesChart extends StatefulWidget {
  final List<TimeseriesPointModel> points;
  final String title;
  final void Function(int selectedSeconds)? onRangeChanged;

  const ColumnarTimeseriesChart({
    super.key,
    required this.points,
    this.title = 'DNS Query Volume & Security Drop Telemetry',
    this.onRangeChanged,
  });

  @override
  State<ColumnarTimeseriesChart> createState() => _ColumnarTimeseriesChartState();
}

class _ColumnarTimeseriesChartState extends State<ColumnarTimeseriesChart> {
  int _selectedRangeHours = 24;
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _buildRangeSelector(),
            ],
          ),
          const SizedBox(height: 14),
          _buildLegend(),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: widget.points.isEmpty
                ? const Center(
                    child: Text('No telemetry available', style: TextStyle(color: Colors.white54)),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onPanDown: (details) => _updateHover(details.localPosition.dx, constraints.maxWidth),
                        onPanUpdate: (details) => _updateHover(details.localPosition.dx, constraints.maxWidth),
                        child: CustomPaint(
                          size: Size(constraints.maxWidth, 180),
                          painter: _TimeseriesChartPainter(
                            points: widget.points,
                            hoverIndex: _hoverIndex,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_hoverIndex != null && _hoverIndex! >= 0 && _hoverIndex! < widget.points.length)
            _buildHoverDetails(widget.points[_hoverIndex!]),
        ],
      ),
    );
  }

  void _updateHover(double dx, double width) {
    if (widget.points.isEmpty) return;
    final count = widget.points.length;
    final itemWidth = width / count;
    final idx = (dx / itemWidth).floor().clamp(0, count - 1);
    setState(() {
      _hoverIndex = idx;
    });
  }

  Widget _buildRangeSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [1, 24, 168, 720].map((hours) {
        final label = hours == 1
            ? '1h'
            : hours == 24
                ? '24h'
                : hours == 168
                    ? '7d'
                    : '30d';
        final isSelected = _selectedRangeHours == hours;
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              setState(() {
                _selectedRangeHours = hours;
              });
              widget.onRangeChanged?.call(hours * 3600);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF64B5F6) : const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.black : Colors.white70,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _buildLegendItem('Total Ingested', const Color(0xFF90CAF9)),
        _buildLegendItem('Blocked Distractions', const Color(0xFFFFB74D)),
        _buildLegendItem('Zero-Day Threats', const Color(0xFFEF5350)),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
        ),
      ],
    );
  }

  Widget _buildHoverDetails(TimeseriesPointModel pt) {
    final dt = DateTime.fromMillisecondsSinceEpoch(pt.timestamp * 1000);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF333336)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            Text(
              'Total: ${pt.totalQueries}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF90CAF9)),
            ),
            Text(
              'Blocked: ${pt.blockedQueries}',
              style: const TextStyle(fontSize: 12, color: Color(0xFFFFB74D)),
            ),
            Text(
              'Threats: ${pt.threatCount}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFEF5350)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeseriesChartPainter extends CustomPainter {
  final List<TimeseriesPointModel> points;
  final int? hoverIndex;

  _TimeseriesChartPainter({required this.points, this.hoverIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final maxVal = points.map((p) => p.totalQueries).reduce(math.max).toDouble();
    final effectiveMax = maxVal == 0 ? 100.0 : maxVal * 1.15;

    final n = points.length;
    final barSlotWidth = size.width / n;
    final barWidth = math.max(2.0, barSlotWidth * 0.65);

    final totalPaint = Paint()..color = const Color(0xFF3A4B5D);
    final blockedPaint = Paint()..color = const Color(0xFFFFB74D);
    final threatPaint = Paint()..color = const Color(0xFFEF5350);
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    // Grid Lines
    final gridPaint = Paint()
      ..color = const Color(0xFF2C2C2E)
      ..strokeWidth = 1.0;
    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (int i = 0; i < n; i++) {
      final pt = points[i];
      final xCenter = (i * barSlotWidth) + (barSlotWidth / 2);
      final left = xCenter - (barWidth / 2);

      if (hoverIndex == i) {
        canvas.drawRect(Rect.fromLTWH(i * barSlotWidth, 0, barSlotWidth, size.height), highlightPaint);
      }

      // 1. Total Queries Bar
      final totalH = (pt.totalQueries / effectiveMax) * size.height;
      final totalRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, size.height - totalH, barWidth, totalH),
        const Radius.circular(2),
      );
      canvas.drawRRect(totalRect, totalPaint);

      // 2. Blocked Queries Overlay
      if (pt.blockedQueries > 0) {
        final blockedH = (pt.blockedQueries / effectiveMax) * size.height;
        final blockedRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - blockedH, barWidth, blockedH),
          const Radius.circular(2),
        );
        canvas.drawRRect(blockedRect, blockedPaint);
      }

      // 3. Threat Bar Overlay
      if (pt.threatCount > 0) {
        final threatH = (pt.threatCount / effectiveMax) * size.height;
        final threatRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - threatH, barWidth, threatH),
          const Radius.circular(2),
        );
        canvas.drawRRect(threatRect, threatPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimeseriesChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.hoverIndex != hoverIndex;
  }
}
