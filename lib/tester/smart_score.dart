import 'dart:math';

import '../core/models/test_result.dart';

/// User-tunable weights (Settings -> Testing). They don't need to sum to 1;
/// they are normalised.
class ScoreWeights {
  final double ping;
  final double speed;
  final double stability; // jitter
  final double loss;
  const ScoreWeights({this.ping = 0.35, this.speed = 0.35, this.stability = 0.15, this.loss = 0.15});

  Map<String, double> toJson() => {'ping': ping, 'speed': speed, 'stability': stability, 'loss': loss};
  factory ScoreWeights.fromJson(Map<String, dynamic> j) => ScoreWeights(
        ping: (j['ping'] as num?)?.toDouble() ?? 0.35,
        speed: (j['speed'] as num?)?.toDouble() ?? 0.35,
        stability: (j['stability'] as num?)?.toDouble() ?? 0.15,
        loss: (j['loss'] as num?)?.toDouble() ?? 0.15,
      );
}

/// Smart Score: 0..100, higher is better; dead servers get -1 (sorted last).
///
/// Decision: each metric is mapped to 0..1 with a *fixed* curve, not min-max
/// over the current list. That makes scores comparable between runs/history
/// and stops one outlier from distorting everyone else.
///   ping:   1 at <=30 ms, 0 at >=1000 ms, log scale between
///   speed:  0 at 0, 1 at >=100 Mbit/s, log scale (10 Mbit/s ~ 0.5)
///   jitter: 1 at 0, 0 at >=100 ms, linear
///   loss:   1 at 0 %, 0 at >=50 %, linear
/// Missing speed (not tested yet) -> weight redistributed to the other metrics.
class SmartScore {
  static double compute(TestResult? r, ScoreWeights w) {
    if (r == null || !r.isAlive) return -1;
    final parts = <(double, double)>[];
    parts.add((w.ping, _pingScore(r.medianMs!.toDouble())));
    if (r.downloadMbps != null) parts.add((w.speed, _speedScore(r.downloadMbps!)));
    if (r.jitterMs != null) parts.add((w.stability, (1 - r.jitterMs! / 100).clamp(0.0, 1.0)));
    parts.add((w.loss, (1 - r.lossPercent / 50).clamp(0.0, 1.0)));
    final wsum = parts.fold<double>(0, (a, p) => a + p.$1);
    if (wsum <= 0) return 0;
    final s = parts.fold<double>(0, (a, p) => a + p.$1 * p.$2) / wsum;
    return double.parse((s * 100).toStringAsFixed(1));
  }

  static double _pingScore(double ms) {
    if (ms <= 30) return 1;
    if (ms >= 1000) return 0;
    return 1 - (log(ms / 30) / log(1000 / 30));
  }

  static double _speedScore(double mbps) {
    if (mbps <= 0) return 0;
    if (mbps >= 100) return 1;
    return (log(1 + mbps) / log(101)).clamp(0.0, 1.0);
  }

  /// "stable" if >=5 runs, loss avg < 5 % and median spread small;
  /// "flaky" if >=3 runs and >=30 % of runs failed.
  static StabilityBadge badge(List<TestResult> history) {
    if (history.length < 3) return StabilityBadge.none;
    final failed = history.where((h) => !h.isAlive).length;
    if (failed / history.length >= 0.3) return StabilityBadge.flaky;
    if (history.length >= 5) {
      final alive = history.where((h) => h.isAlive).toList();
      final avgLoss = alive.fold<double>(0, (a, h) => a + h.lossPercent) / alive.length;
      final medians = alive.map((h) => h.medianMs!.toDouble()).toList()..sort();
      final p10 = medians[(medians.length * 0.1).floor()];
      final p90 = medians[min(medians.length - 1, (medians.length * 0.9).floor())];
      if (avgLoss < 5 && (p90 - p10) < max(50, p10 * 0.5)) return StabilityBadge.stable;
    }
    return StabilityBadge.none;
  }
}
