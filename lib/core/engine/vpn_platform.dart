import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

enum SplitMode { off, onlySelected, exceptSelected }

class VpnStartArgs {
  final int socksPort;
  final int mtu;
  final String dns; // in-tunnel DNS address handed to the OS (hijacked by core)
  final bool ipv6; // route ::/0 into the tunnel (blocked there) to stop v6 leaks
  final SplitMode splitMode;
  final List<String> packages;
  final String sessionName;
  final String serverId;
  const VpnStartArgs({
    required this.socksPort,
    this.mtu = 1500,
    this.dns = '172.19.0.2',
    this.ipv6 = true,
    this.splitMode = SplitMode.off,
    this.packages = const [],
    this.sessionName = 'KupuTUN',
    this.serverId = '',
  });

  Map<String, Object> toMap() => {
        'socksPort': socksPort,
        'mtu': mtu,
        'dns': dns,
        'ipv6': ipv6,
        'splitMode': splitMode.name,
        'packages': packages,
        'session': sessionName,
        'serverId': serverId,
      };
}

class InstalledApp {
  final String package;
  final String label;
  final bool system;
  const InstalledApp(this.package, this.label, this.system);
}

/// Android VpnService bridge (method channel `kuputun/vpn`).
class VpnPlatform {
  static const _ch = MethodChannel('kuputun/vpn');
  static const _eventsChannel = EventChannel('kuputun/vpn_events');
  static Stream<Map<String, Object?>>? _eventStream;

  static bool get supported => Platform.isAndroid;

  /// Cached on purpose: `receiveBroadcastStream()` returns a new stream on every
  /// call while the native side owns a single EventSink, so a second access would
  /// silently take the events away from the first subscriber.
  Stream<Map<String, Object?>> get events => _eventStream ??= _eventsChannel
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => Map<String, Object?>.from(e as Map));

  /// Shows the system consent dialog if needed. Returns false if user declined.
  Future<bool> prepare() async => await _ch.invokeMethod<bool>('prepare') ?? false;

  Future<void> start(VpnStartArgs args) => _ch.invokeMethod('start', args.toMap());
  Future<void> stop() => _ch.invokeMethod('stop');

  /// Persists the last config in Android-Keystore-encrypted storage, so the
  /// Quick Settings tile / boot receiver / Always-on can connect without UI.
  Future<void> saveLastConfig(String core, String config, VpnStartArgs args, {bool autoConnect = false}) =>
      _ch.invokeMethod('saveLastConfig', {'core': core, 'config': config, 'autoConnect': autoConnect, ...args.toMap()});

  Future<void> openAlwaysOnSettings() => _ch.invokeMethod('openVpnSettings');

  Future<List<InstalledApp>> installedApps() async {
    final list = await _ch.invokeListMethod<Map<dynamic, dynamic>>('installedApps') ?? const [];
    return list
        .map((m) => InstalledApp(m['package'] as String, m['label'] as String, m['system'] as bool? ?? false))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  /// Whether the VpnService is up (it may have been started by the tile,
  /// widget, boot receiver or Always-on while the UI was not running).
  Future<({bool running, String? serverId, int? since})> status() async {
    final m = await _ch.invokeMapMethod<String, Object?>('status') ?? const {};
    return (
      running: m['running'] as bool? ?? false,
      serverId: m['serverId'] as String?,
      since: (m['since'] as num?)?.toInt(),
    );
  }

  /// Native-side prefs: QS tile behaviour (toggleLast | connectBest | openApp)
  /// and whether the VPN notification shows live speed.
  Future<void> setNativePrefs({required String tileAction, required bool notifSpeed}) =>
      _ch.invokeMethod('setNativePrefs', {'tileAction': tileAction, 'notifSpeed': notifSpeed});

  /// Action requested by the tile while the UI was starting (e.g. connect_best).
  Future<String?> takePendingAction() => _ch.invokeMethod<String>('takePendingAction');

  /// Platform traffic counters (TrafficStats for our UID), bytes.
  Future<(int, int)> traffic() async {
    final m = await _ch.invokeMapMethod<String, int>('traffic') ?? const {};
    return (m['up'] ?? 0, m['down'] ?? 0);
  }
}
