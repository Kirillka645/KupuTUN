import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// Tiny dependency-free line chart used for history sparklines and the live
/// speed graph. Null values are drawn as gaps (failed tests).
class Sparkline extends StatelessWidget {
  final List<double?> values;
  final Color color;
  final double height;
  final bool fill;
  final double? maxY;
  const Sparkline({super.key, required this.values, required this.color, this.height = 32, this.fill = true, this.maxY});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: CustomPaint(painter: _SparkPainter(values, color, fill, maxY), size: Size.infinite),
      );
}

class _SparkPainter extends CustomPainter {
  final List<double?> v;
  final Color color;
  final bool fill;
  final double? maxY;
  _SparkPainter(this.v, this.color, this.fill, this.maxY);

  @override
  void paint(Canvas canvas, Size size) {
    final pts = v.whereType<double>().toList();
    if (pts.isEmpty || v.length < 2) return;
    final hi = maxY ?? pts.reduce(max) * 1.15;
    final lo = 0.0;
    final dx = size.width / (v.length - 1);
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final area = Paint()..color = color.withValues(alpha: 0.15);
    Path? path;
    Path? fillPath;
    double? lastX;
    void flush() {
      if (path != null) {
        canvas.drawPath(path!, line);
        if (fill && fillPath != null && lastX != null) {
          fillPath!
            ..lineTo(lastX, size.height)
            ..close();
          canvas.drawPath(fillPath!, area);
        }
      }
      path = null;
      fillPath = null;
    }

    for (var i = 0; i < v.length; i++) {
      final y0 = v[i];
      final x = i * dx;
      if (y0 == null) {
        flush();
        canvas.drawCircle(Offset(x, size.height - 2), 2, Paint()..color = Colors.red.withValues(alpha: 0.7));
        continue;
      }
      final y = size.height - ((y0 - lo) / (hi - lo == 0 ? 1 : hi - lo)) * size.height;
      if (path == null) {
        path = Path()..moveTo(x, y);
        fillPath = Path()
          ..moveTo(x, size.height)
          ..lineTo(x, y);
      } else {
        path!.lineTo(x, y);
        fillPath!.lineTo(x, y);
      }
      lastX = x;
    }
    flush();
  }

  @override
  // Compare the contents, not the list identity: callers append samples to the
  // same list instance, so an identity check never repainted the live graph.
  bool shouldRepaint(_SparkPainter o) =>
      o.color != color || o.fill != fill || o.maxY != maxY || !listEquals(o.v, v);
}
