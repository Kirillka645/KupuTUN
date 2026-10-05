import 'dart:math';

/// Pure statistics helpers (unit-tested).
class LatencyStats {
  final int? median;
  final double? jitter;
  final double lossPercent;
  const LatencyStats(this.median, this.jitter, this.lossPercent);

  /// [samples]: null = lost/timeout.
  /// Jitter = mean absolute difference between consecutive successful samples
  /// (RFC 3550-style, without smoothing) – intuitive for users and stable for 3 samples.
  factory LatencyStats.from(List<int?> samples) {
    if (samples.isEmpty) return const LatencyStats(null, null, 100);
    final ok = samples.whereType<int>().toList();
    final loss = (samples.length - ok.length) * 100.0 / samples.length;
    if (ok.isEmpty) return LatencyStats(null, null, loss);
    final sorted = [...ok]..sort();
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2).round();
    double? jitter;
    if (ok.length >= 2) {
      var sum = 0;
      for (var i = 1; i < ok.length; i++) {
        sum += (ok[i] - ok[i - 1]).abs();
      }
      jitter = sum / (ok.length - 1);
    } else {
      jitter = 0;
    }
    return LatencyStats(median, jitter, loss);
  }
}

double mbps(int bytes, Duration elapsed) {
  if (elapsed.inMicroseconds <= 0) return 0;
  return bytes * 8 / elapsed.inMicroseconds; // bits per microsecond == Mbit/s
}

double stddev(List<num> xs) {
  if (xs.length < 2) return 0;
  final mean = xs.reduce((a, b) => a + b) / xs.length;
  final v = xs.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / (xs.length - 1);
  return sqrt(v);
}
