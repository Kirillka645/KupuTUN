import '../core/models/test_result.dart';
import 'smart_score.dart';
import 'speed_tester.dart';

class TesterSettings {
  final PingMode pingMode;
  final int concurrency; // parallel probes
  final Duration timeout; // per probe, 3..15 s
  final int samples; // probes per server
  final String url;
  final bool useHead;
  final bool measureTls;
  final SpeedMode speedMode;
  final bool speedUpload;
  final String? customSpeedUrl;
  final bool autoTestOnLaunch;
  final bool autoTestAfterUpdate;
  final ScoreWeights weights;

  const TesterSettings({
    this.pingMode = PingMode.realDelay,
    this.concurrency = 16,
    this.timeout = const Duration(seconds: 5),
    this.samples = 3,
    this.url = 'https://cp.cloudflare.com/generate_204',
    this.useHead = false,
    this.measureTls = true,
    this.speedMode = SpeedMode.quick,
    this.speedUpload = true,
    this.customSpeedUrl,
    this.autoTestOnLaunch = false,
    this.autoTestAfterUpdate = true,
    this.weights = const ScoreWeights(),
  });

  TesterSettings copyWith({
    PingMode? pingMode,
    int? concurrency,
    Duration? timeout,
    int? samples,
    String? url,
    bool? useHead,
    bool? measureTls,
    SpeedMode? speedMode,
    bool? speedUpload,
    bool? autoTestOnLaunch,
    bool? autoTestAfterUpdate,
    ScoreWeights? weights,
  }) =>
      TesterSettings(
        pingMode: pingMode ?? this.pingMode,
        concurrency: (concurrency ?? this.concurrency).clamp(1, 64),
        timeout: Duration(seconds: (timeout ?? this.timeout).inSeconds.clamp(3, 15)),
        samples: (samples ?? this.samples).clamp(1, 10),
        url: url ?? this.url,
        useHead: useHead ?? this.useHead,
        measureTls: measureTls ?? this.measureTls,
        speedMode: speedMode ?? this.speedMode,
        speedUpload: speedUpload ?? this.speedUpload,
        customSpeedUrl: customSpeedUrl,
        autoTestOnLaunch: autoTestOnLaunch ?? this.autoTestOnLaunch,
        autoTestAfterUpdate: autoTestAfterUpdate ?? this.autoTestAfterUpdate,
        weights: weights ?? this.weights,
      );

  Map<String, dynamic> toJson() => {
        'pingMode': pingMode.name,
        'concurrency': concurrency,
        'timeoutSec': timeout.inSeconds,
        'samples': samples,
        'url': url,
        'useHead': useHead,
        'measureTls': measureTls,
        'speedMode': speedMode.name,
        'speedUpload': speedUpload,
        'customSpeedUrl': customSpeedUrl,
        'autoTestOnLaunch': autoTestOnLaunch,
        'autoTestAfterUpdate': autoTestAfterUpdate,
        'weights': weights.toJson(),
      };

  factory TesterSettings.fromJson(Map<String, dynamic> j) => TesterSettings(
        pingMode: PingMode.values.byName(j['pingMode'] as String? ?? 'realDelay'),
        concurrency: (j['concurrency'] as num?)?.toInt() ?? 16,
        timeout: Duration(seconds: (j['timeoutSec'] as num?)?.toInt() ?? 5),
        samples: (j['samples'] as num?)?.toInt() ?? 3,
        url: j['url'] as String? ?? 'https://cp.cloudflare.com/generate_204',
        useHead: j['useHead'] as bool? ?? false,
        measureTls: j['measureTls'] as bool? ?? true,
        speedMode: SpeedMode.values.byName(j['speedMode'] as String? ?? 'quick'),
        speedUpload: j['speedUpload'] as bool? ?? true,
        customSpeedUrl: j['customSpeedUrl'] as String?,
        autoTestOnLaunch: j['autoTestOnLaunch'] as bool? ?? false,
        autoTestAfterUpdate: j['autoTestAfterUpdate'] as bool? ?? true,
        weights: j['weights'] == null ? const ScoreWeights() : ScoreWeights.fromJson(Map<String, dynamic>.from(j['weights'] as Map)),
      );

  /// Ping mode requested by a provider header `ping-type` (Happ names).
  static PingMode? fromProviderPingType(String? v) => switch (v?.toLowerCase()) {
        'tcp' => PingMode.tcp,
        'icmp' => PingMode.icmp,
        'proxy' || 'proxy-head' || 'real' => PingMode.realDelay,
        _ => null,
      };
}
