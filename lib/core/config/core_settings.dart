import '../models/subscription.dart';

enum TunEngine { tun2socks, singboxTun, xrayTun }

enum ConnectionMode { tun, systemProxy, proxyOnly }

/// Global core settings (Settings screen). Persisted as JSON.
class CoreSettings {
  final int socksPort;
  final int httpPort;
  final bool allowLan;
  final bool mux;
  final int muxConcurrency;
  final FragmentSettings fragment;
  final NoiseSettings noises;
  final bool blockIpv6;
  final bool sniffing;
  final String logLevel; // debug | info | warning | error | none
  final String testUrl;
  final ConnectionMode connectionMode;
  final TunEngine tunEngine;
  final int tunMtu;
  final bool killSwitch;
  final bool autoSwitch;
  final Duration healthCheckInterval;
  final String? fingerprintOverride; // uTLS: chrome, firefox, safari, ios, android, edge, random, randomized

  /// Runtime-only: where cores write their log (Logs screen). Not persisted.
  final String? logPath;

  const CoreSettings({
    this.socksPort = 10808,
    this.httpPort = 10809,
    this.allowLan = false,
    this.mux = false,
    this.muxConcurrency = 8,
    this.fragment = const FragmentSettings(),
    this.noises = const NoiseSettings(),
    this.blockIpv6 = true,
    this.sniffing = true,
    this.logLevel = 'warning',
    this.testUrl = 'https://cp.cloudflare.com/generate_204',
    this.connectionMode = ConnectionMode.tun,
    this.tunEngine = TunEngine.tun2socks,
    this.tunMtu = 1500,
    this.killSwitch = true,
    this.autoSwitch = false,
    this.healthCheckInterval = const Duration(minutes: 3),
    this.fingerprintOverride,
    this.logPath,
  });

  String get listen => allowLan ? '0.0.0.0' : '127.0.0.1';

  CoreSettings copyWith({
    int? socksPort,
    int? httpPort,
    bool? allowLan,
    bool? mux,
    int? muxConcurrency,
    bool? sniffing,
    int? tunMtu,
    FragmentSettings? fragment,
    NoiseSettings? noises,
    bool? blockIpv6,
    String? logLevel,
    String? testUrl,
    ConnectionMode? connectionMode,
    TunEngine? tunEngine,
    bool? killSwitch,
    bool? autoSwitch,
    Duration? healthCheckInterval,
    String? fingerprintOverride,
    String? logPath,
  }) =>
      CoreSettings(
        socksPort: socksPort ?? this.socksPort,
        httpPort: httpPort ?? this.httpPort,
        allowLan: allowLan ?? this.allowLan,
        mux: mux ?? this.mux,
        muxConcurrency: muxConcurrency ?? this.muxConcurrency,
        fragment: fragment ?? this.fragment,
        noises: noises ?? this.noises,
        blockIpv6: blockIpv6 ?? this.blockIpv6,
        sniffing: sniffing ?? this.sniffing,
        logLevel: logLevel ?? this.logLevel,
        testUrl: testUrl ?? this.testUrl,
        connectionMode: connectionMode ?? this.connectionMode,
        tunEngine: tunEngine ?? this.tunEngine,
        tunMtu: tunMtu ?? this.tunMtu,
        killSwitch: killSwitch ?? this.killSwitch,
        autoSwitch: autoSwitch ?? this.autoSwitch,
        healthCheckInterval: healthCheckInterval ?? this.healthCheckInterval,
        fingerprintOverride: fingerprintOverride ?? this.fingerprintOverride,
        logPath: logPath ?? this.logPath,
      );

  Map<String, dynamic> toJson() => {
        'socksPort': socksPort,
        'httpPort': httpPort,
        'allowLan': allowLan,
        'mux': mux,
        'muxConcurrency': muxConcurrency,
        'fragment': fragment.toJson(),
        'noises': noises.toJson(),
        'blockIpv6': blockIpv6,
        'sniffing': sniffing,
        'logLevel': logLevel,
        'testUrl': testUrl,
        'connectionMode': connectionMode.name,
        'tunEngine': tunEngine.name,
        'tunMtu': tunMtu,
        'killSwitch': killSwitch,
        'autoSwitch': autoSwitch,
        'healthCheckMin': healthCheckInterval.inMinutes,
        'fingerprintOverride': fingerprintOverride,
      };

  factory CoreSettings.fromJson(Map<String, dynamic> j) => CoreSettings(
        socksPort: (j['socksPort'] as num?)?.toInt() ?? 10808,
        httpPort: (j['httpPort'] as num?)?.toInt() ?? 10809,
        allowLan: j['allowLan'] as bool? ?? false,
        mux: j['mux'] as bool? ?? false,
        muxConcurrency: (j['muxConcurrency'] as num?)?.toInt() ?? 8,
        fragment: j['fragment'] == null ? const FragmentSettings() : FragmentSettings.fromJson(Map<String, dynamic>.from(j['fragment'] as Map)),
        noises: j['noises'] == null ? const NoiseSettings() : NoiseSettings.fromJson(Map<String, dynamic>.from(j['noises'] as Map)),
        blockIpv6: j['blockIpv6'] as bool? ?? true,
        sniffing: j['sniffing'] as bool? ?? true,
        logLevel: j['logLevel'] as String? ?? 'warning',
        testUrl: j['testUrl'] as String? ?? 'https://cp.cloudflare.com/generate_204',
        connectionMode: ConnectionMode.values.byName(j['connectionMode'] as String? ?? 'tun'),
        tunEngine: TunEngine.values.byName(j['tunEngine'] as String? ?? 'tun2socks'),
        tunMtu: (j['tunMtu'] as num?)?.toInt() ?? 1500,
        killSwitch: j['killSwitch'] as bool? ?? true,
        autoSwitch: j['autoSwitch'] as bool? ?? false,
        healthCheckInterval: Duration(minutes: (j['healthCheckMin'] as num?)?.toInt() ?? 3),
        fingerprintOverride: j['fingerprintOverride'] as String?,
      );
}
