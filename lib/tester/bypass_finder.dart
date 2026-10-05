import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/config/core_settings.dart';
import '../core/config/xray_config_builder.dart';
import '../core/engine/core_bridge.dart';
import '../core/models/server.dart';
import '../core/models/subscription.dart';
import 'ping_tester.dart';

/// "Автоподбор обхода": tries fragmentation presets against one server and
/// returns the first preset that makes real delay work (fastest wins on tie).
class BypassFinder {
  final CoreBridge bridge;
  final CoreSettings settings;
  BypassFinder(this.bridge, this.settings);

  /// Ordered from least to most aggressive: aggressive fragmentation costs
  /// latency, so we prefer the mildest preset that works.
  static const presets = <FragmentSettings>[
    FragmentSettings(enabled: false),
    FragmentSettings(enabled: true, packets: 'tlshello', length: '100-200', interval: '10-20'),
    FragmentSettings(enabled: true, packets: 'tlshello', length: '10-20', interval: '10-20'),
    FragmentSettings(enabled: true, packets: 'tlshello', length: '1-3', interval: '1-3'),
    FragmentSettings(enabled: true, packets: '1-3', length: '50-100', interval: '5-10'),
    FragmentSettings(enabled: true, packets: '1-1', length: '1-5', interval: '1-2', maxSplit: 200),
    FragmentSettings(enabled: true, packets: 'tlshello', length: '517', interval: '0'),
  ];

  Stream<(FragmentSettings, int?)> tryAll(Server s, {Uri? url, Duration timeout = const Duration(seconds: 6)}) async* {
    if (s.effectiveCore != CoreType.xray || s.params.containsKey('json')) {
      // Fragmentation is an Xray freedom feature; QUIC protocols (hy2/tuic) don't use TLS-over-TCP.
      return;
    }
    final target = url ?? Uri.parse(settings.testUrl);
    for (final p in presets) {
      final port = (await bridge.freePorts(1)).first;
      final id = 'bypass-${p.hashCode}';
      int? ms;
      try {
        // Built inside the try: ConfigBuildException (e.g. an SS server with a
        // plugin, which Xray's freedom outbound cannot express) must end as a
        // "preset did not work" result, not as an error escaping the stream.
        final cfg = XrayConfigBuilder(settings.copyWith(fragment: p)).buildBatchTest([s], [port], fragment: p);
        await bridge.startInstance(id, 'xray', jsonEncode(cfg));
        final a = await PingProbes.realDelay(port, target, timeout);
        final b = a == null ? null : await PingProbes.realDelay(port, target, timeout);
        ms = (a != null && b != null) ? ((a + b) / 2).round() : null;
      } on Object {
        ms = null;
      } finally {
        try {
          await bridge.stopInstance(id);
        } on Object {
          // Nothing was started, or it is already gone.
        }
      }
      yield (p, ms);
    }
  }

  /// Returns the first working preset, or null if nothing works.
  Future<FragmentSettings?> findWorking(Server s) async {
    await for (final (p, ms) in tryAll(s)) {
      if (ms != null) return p;
    }
    return null;
  }
}

/// Resolves a server hostname and picks the IP with the lowest TCP connect
/// time. The SNI/Host stay unchanged, so TLS/Reality keep working.
class ServerAddressResolver {
  static Future<Server> pickFastestIp(Server s, {Duration timeout = const Duration(seconds: 3)}) async {
    if (InternetAddress.tryParse(s.address) != null || s.params.containsKey('json')) return s;
    final List<InternetAddress> addrs;
    try {
      addrs = await InternetAddress.lookup(s.address).timeout(timeout);
    } on Object {
      return s;
    }
    if (addrs.length <= 1) return addrs.isEmpty ? s : _withIp(s, addrs.first.address);
    final results = await Future.wait(addrs.map((a) async => (a.address, await PingProbes.tcpConnect(a.address, s.port, timeout))));
    final alive = results.where((r) => r.$2 != null).toList()..sort((a, b) => a.$2!.compareTo(b.$2!));
    return alive.isEmpty ? s : _withIp(s, alive.first.$1);
  }

  static Server _withIp(Server s, String ip) {
    final p = Map<String, String>.from(s.params);
    // keep the original hostname for SNI / Host if they were implicit
    if (s.security == 'tls' || s.security == 'reality') p.putIfAbsent('sni', () => s.address);
    if (s.transport == 'ws' || s.transport == 'httpupgrade' || s.transport == 'xhttp') p.putIfAbsent('host', () => s.address);
    return s.copyWith(address: ip, params: p);
  }
}
