/// Kind of latency measurement.
enum PingMode { tcp, icmp, realDelay }

/// One completed test run for one server. Stored in SQLite (table test_results).
class TestResult {
  final int? id;
  final String serverId;
  final DateTime timestamp;
  final PingMode mode;

  /// Individual samples in ms; null entries are timeouts / failures.
  final List<int?> samples;
  final int? medianMs;
  final double? jitterMs;
  final double lossPercent;
  final int? tlsHandshakeMs;
  final double? downloadMbps;
  final double? uploadMbps;
  final int bytesUsed;
  final String? exitIp;
  final String? exitCountry;
  final Map<String, bool> services;
  final String? error;

  const TestResult({
    this.id,
    required this.serverId,
    required this.timestamp,
    required this.mode,
    this.samples = const [],
    this.medianMs,
    this.jitterMs,
    this.lossPercent = 0,
    this.tlsHandshakeMs,
    this.downloadMbps,
    this.uploadMbps,
    this.bytesUsed = 0,
    this.exitIp,
    this.exitCountry,
    this.services = const {},
    this.error,
  });

  bool get isAlive => medianMs != null && lossPercent < 100;

  TestResult merge(TestResult o) => TestResult(
        id: id,
        serverId: serverId,
        timestamp: o.timestamp.isAfter(timestamp) ? o.timestamp : timestamp,
        mode: o.medianMs != null ? o.mode : mode,
        samples: o.samples.isNotEmpty ? o.samples : samples,
        medianMs: o.medianMs ?? medianMs,
        jitterMs: o.jitterMs ?? jitterMs,
        lossPercent: o.samples.isNotEmpty ? o.lossPercent : lossPercent,
        tlsHandshakeMs: o.tlsHandshakeMs ?? tlsHandshakeMs,
        downloadMbps: o.downloadMbps ?? downloadMbps,
        uploadMbps: o.uploadMbps ?? uploadMbps,
        bytesUsed: bytesUsed + o.bytesUsed,
        exitIp: o.exitIp ?? exitIp,
        exitCountry: o.exitCountry ?? exitCountry,
        services: {...services, ...o.services},
        error: o.error,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'server_id': serverId,
        'ts': timestamp.millisecondsSinceEpoch,
        'mode': mode.name,
        'samples': samples.map((e) => e ?? -1).join(','),
        'median_ms': medianMs,
        'jitter_ms': jitterMs,
        'loss': lossPercent,
        'tls_ms': tlsHandshakeMs,
        'down_mbps': downloadMbps,
        'up_mbps': uploadMbps,
        'bytes': bytesUsed,
        'exit_ip': exitIp,
        'exit_country': exitCountry,
        'services': services.entries.map((e) => '${e.key}=${e.value ? 1 : 0}').join(','),
        'error': error,
      };

  factory TestResult.fromRow(Map<String, Object?> r) {
    final s = (r['samples'] as String?) ?? '';
    final svc = (r['services'] as String?) ?? '';
    return TestResult(
      id: r['id'] as int?,
      serverId: r['server_id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(r['ts'] as int),
      mode: PingMode.values.byName(r['mode'] as String),
      samples: s.isEmpty
          ? const []
          : s.split(',').map((e) {
              final v = int.parse(e);
              return v < 0 ? null : v;
            }).toList(),
      medianMs: r['median_ms'] as int?,
      jitterMs: (r['jitter_ms'] as num?)?.toDouble(),
      lossPercent: (r['loss'] as num?)?.toDouble() ?? 0,
      tlsHandshakeMs: r['tls_ms'] as int?,
      downloadMbps: (r['down_mbps'] as num?)?.toDouble(),
      uploadMbps: (r['up_mbps'] as num?)?.toDouble(),
      bytesUsed: (r['bytes'] as int?) ?? 0,
      exitIp: r['exit_ip'] as String?,
      exitCountry: r['exit_country'] as String?,
      services: {
        for (final p in svc.split(',').where((e) => e.contains('=')))
          p.split('=')[0]: p.split('=')[1] == '1',
      },
      error: r['error'] as String?,
    );
  }
}

/// Aggregated history badge for a server.
enum StabilityBadge { none, stable, flaky }
