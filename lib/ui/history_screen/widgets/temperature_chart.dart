import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../domain/entities/app_settings.dart';
import '../../../domain/entities/temperature_reading.dart';

String readingTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
}

class TemperatureChart extends StatelessWidget {
  const TemperatureChart({super.key, required this.readings, required this.unit});
  final List<TemperatureReading> readings;
  final TemperatureUnit unit;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 300,
    width: double.infinity,
    child: CustomPaint(painter: _TemperaturePainter(readings, unit, Theme.of(context).colorScheme)),
  );
}

class _TemperaturePainter extends CustomPainter {
  _TemperaturePainter(this.readings, this.unit, this.colors);
  final List<TemperatureReading> readings;
  final TemperatureUnit unit;
  final ColorScheme colors;

  // Plot actual timestamps, leaving gaps when sensor updates were unavailable.
  @override
  void paint(Canvas canvas, Size size) {
    if (readings.isEmpty) return;
    final plot = Rect.fromLTRB(64, 20, size.width - 20, size.height - 40);
    if (plot.width <= 0) return;
    final values = readings.map((r) => displayTemperature(r.celsius, unit)).toList();
    final low = values.reduce(math.min), high = values.reduce(math.max);
    final padding = math.max(1.0, (high - low) * .15);
    final bottom = low - padding, top = high + padding;
    final span = readings.last.timestamp.difference(readings.first.timestamp).inMilliseconds;
    Offset point(int index) => Offset(
      span == 0
          ? plot.center.dx
          : plot.left +
                plot.width * readings[index].timestamp.difference(readings.first.timestamp).inMilliseconds / span,
      plot.bottom - plot.height * (values[index] - bottom) / (top - bottom),
    );
    void label(String text, Offset at, {bool alignRight = false}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(alignRight ? at.dx - painter.width : at.dx, at.dy));
    }

    for (var i = 0; i < 4; i++) {
      final y = plot.top + plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), Paint()..color = colors.outlineVariant);
      label((top - (top - bottom) * i / 3).toStringAsFixed(1), Offset(plot.left - 8, y - 7), alignRight: true);
    }
    final line = Path();
    for (var i = 0; i < readings.length; i++) {
      final position = point(i);
      if (i == 0 || readings[i].timestamp.difference(readings[i - 1].timestamp) > const Duration(seconds: 30)) {
        line.moveTo(position.dx, position.dy);
      } else {
        line.lineTo(position.dx, position.dy);
      }
      canvas.drawCircle(position, readings.length == 1 ? 5 : 2, Paint()..color = colors.primary);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = colors.primary
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    label(readingTime(readings.first.timestamp), Offset(plot.left, plot.bottom + 12));
    if (readings.length > 1) {
      label(readingTime(readings.last.timestamp), Offset(plot.right, plot.bottom + 12), alignRight: true);
    }
  }

  @override
  bool shouldRepaint(_TemperaturePainter old) => old.readings != readings || old.unit != unit || old.colors != colors;
}
