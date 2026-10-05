import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ⟳ "refresh subscription" icon that spins while [active].
class SpinningSyncIcon extends StatefulWidget {
  final bool active;
  final double size;
  final Color? color;
  const SpinningSyncIcon({super.key, required this.active, this.size = 24, this.color});
  @override
  State<SpinningSyncIcon> createState() => _SpinningSyncIconState();
}

class _SpinningSyncIconState extends State<SpinningSyncIcon> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(SpinningSyncIcon old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.animateTo(1).then((_) => _c.reset());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        // sync arrows rotate clockwise visually when the turn is negative
        turns: Tween<double>(begin: 0, end: -1).animate(_c),
        child: Icon(Icons.sync_rounded, size: widget.size, color: widget.color),
      );
}

/// Speedometer "ping" icon (like Happ). While [active] the needle sweeps
/// back and forth; idle it rests at ~60%.
class SpeedometerIcon extends StatefulWidget {
  final bool active;
  final double size;
  final Color? color;
  const SpeedometerIcon({super.key, required this.active, this.size = 24, this.color});
  @override
  State<SpeedometerIcon> createState() => _SpeedometerIconState();
}

class _SpeedometerIconState extends State<SpeedometerIcon> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700), value: 0.6);

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(SpeedometerIcon old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.active && _c.isAnimating) _c.animateTo(0.6, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: Size.square(widget.size),
        painter: _GaugePainter(Curves.easeInOut.transform(_c.value), color),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double t; // 0..1 needle position
  final Color color;
  _GaugePainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s * 0.56);
    final r = s * 0.40;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.085
      ..strokeCap = StrokeCap.round;
    const start = math.pi * 0.80; // 144°
    const sweep = math.pi * 1.40; // 252°
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, false, stroke);
    // ticks
    final tick = Paint()
      ..color = color
      ..strokeWidth = s * 0.06
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 4; i++) {
      final a = start + sweep * i / 4;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r * 0.62, c + Offset(math.cos(a), math.sin(a)) * r * 0.78, tick);
    }
    // needle
    final a = start + sweep * t;
    final needle = Paint()
      ..color = color
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * r * 0.70, needle);
    canvas.drawCircle(c, s * 0.075, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.t != t || old.color != color;
}
