import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../tester/bypass_finder.dart';
import '../../tester/ping_tester.dart';
import '../config/core_settings.dart';
import '../config/singbox_config_builder.dart';
import '../config/xray_config_builder.dart';
import '../models/routing_profile.dart';
import '../models/server.dart';
import '../models/subscription.dart';
import 'core_bridge.dart';
import 'system_proxy.dart';
import 'vpn_platform.dart';

enum VpnState { disconnected, connecting, connected, disconnecting, error }

/// Human-readable error instead of raw core logs.
class FriendlyError {
  static String of(Object e) {
    final s = e.toString();
    final l = s.toLowerCase();
    if (l.contains('address already in use') || l.contains('bind')) {
      return 'Порт занят другим приложением. Измените порты SOCKS/HTTP в настройках.';
    }
    if (l.contains('permission') || l.contains('operation not permitted') || l.contains('access is denied')) {
      return 'Нет прав на создание TUN. Запустите от администратора или выберите режим «Системный прокси».';
    }
    if (l.contains('wintun')) return 'Не найден wintun.dll рядом с приложением.';
    if (l.contains('reality') && l.contains('public')) return 'Неверный публичный ключ Reality (pbk) в конфиге.';
    if (l.contains('invalid uuid') || l.contains('failed to parse uuid')) return 'Неверный UUID в конфиге сервера.';
    if (l.contains('geosite') || l.contains('geoip')) return 'Не загружены geo-файлы. Обновите их в «Маршрутизация».';
    if (l.contains('only supported by') || l.contains('served by')) return s;
    if (l.contains('not compiled')) return 'Это ядро не включено в сборку.';
    if (l.contains('vpn permission')) return 'Разрешите создание VPN-подключения.';
    return s.length > 300 ? '${s.substring(0, 300)}…' : s;
  }
}

/// Owns the user connection: core instance(s), TUN / system proxy, traffic
/// counters, session timer and health-check based failover.
class CoreManager extends ChangeNotifier {
  final CoreBridge bridge;
  final VpnPlatform vpn;
  CoreSettings settings;

  /// Called by the health checker when the current server degrades;
  /// should return the next candidate (e.g. best Smart Score) or null.
  Future<Server?> Function(Server current)? onNeedFailover;

  /// Maps a server id (from the platform side) back to a [Server].
  Server? Function(String id)? resolveServer;

  /// Platform-originated actions (e.g. the Quick Settings tile asks the app
  /// to "connect_best").
  void Function(String action)? onPlatformAction;

  CoreManager(this.bridge, this.vpn, this.settings) {
    if (VpnPlatform.supported) {
      _vpnSub = vpn.events.listen(_onVpnEvent);
    }
  }

  void _onVpnEvent(Map<String, Object?> e) {
    final st = e['state'];
    final msg = e['message']?.toString();
    switch (st) {
      case 'connected':
        // Started outside of Flutter (tile / widget / boot / always-on).
        _adoptExternal(e['serverId']?.toString(), (e['since'] as num?)?.toInt());
      case 'disconnected':
        if (state == VpnState.connected) _setDisconnected();
      case 'error':
        if (state == VpnState.connecting) return; // connect() reports its own error
        _trafficTimer?.cancel();
        _healthTimer?.cancel();
        _fail(msg ?? 'VPN error');
      case 'action':
        if (msg != null) onPlatformAction?.call(msg);
    }
  }

  /// Syncs with a VPN that may already be running (app was killed while
  /// connected, or the tile connected before the UI started).
  Future<void> syncWithPlatform() async {
    if (!VpnPlatform.supported) return;
    try {
      final st = await vpn.status();
      if (st.running) {
        _adoptExternal(st.serverId, st.since);
      } else if (state == VpnState.connected && settings.connectionMode == ConnectionMode.tun) {
        _setDisconnected();
      }
      final a = await vpn.takePendingAction();
      if (a != null) onPlatformAction?.call(a);
    } on Object catch (e) {
      debugPrint('vpn status: $e');
    }
  }

  void _adoptExternal(String? serverId, int? sinceMs) {
    if (state == VpnState.connected || state == VpnState.connecting || state == VpnState.disconnecting) return;
    _tunWrapper = false;
    _balanced = false;
    current = serverId == null ? null : resolveServer?.call(serverId);
    connectedAt = sinceMs != null && sinceMs > 0 ? DateTime.fromMillisecondsSinceEpoch(sinceMs) : DateTime.now();
    error = null;
    upBytes = downBytes = 0;
    upRate = downRate = 0;
    state = VpnState.connected;
    notifyListeners();
    unawaited(_rebaseTraffic().then((_) => _startTimers()));
  }

  static const mainId = 'main';
  static const tunId = 'tun';

  VpnState state = VpnState.disconnected;
  String? error;
  Server? current;
  DateTime? connectedAt;
  int upBytes = 0, downBytes = 0;
  double upRate = 0, downRate = 0; // bytes/s
  int? livePingMs;
  bool _balanced = false;
  bool _tunWrapper = false;
  bool _systemProxy = false;
  Timer? _trafficTimer, _healthTimer;
  StreamSubscription<Map<String, Object?>>? _vpnSub;
  int _healthFails = 0;
  (int, int) _baseTraffic = (0, 0);

  SplitMode splitMode = SplitMode.off;
  bool autoConnectOnBoot = false;
  List<String> splitPackages = const [];

  bool get isConnected => state == VpnState.connected;
  bool get isBusy => state == VpnState.connecting || state == VpnState.disconnecting;
  Duration get sessionDuration => connectedAt == null ? Duration.zero : DateTime.now().difference(connectedAt!);
  bool get isBalanced => _balanced;

  String _coreName(Server s) {
    if (s.params.containsKey('json')) return s.param('jsonCore', 'xray');
    return s.effectiveCore == CoreType.singbox ? 'singbox' : 'xray';
  }

  /// Connects to [server]. If auto-switch is on and [pool] has >1 Xray
  /// servers, a leastPing balancer is used (switches inside the core, no
  /// reconnect at all).
  Future<void> connect(Server server, RoutingProfile routing, {Subscription? sub, List<Server> pool = const []}) async {
    if (isBusy) return;
    state = VpnState.connecting;
    error = null;
    notifyListeners();
    try {
      if (VpnPlatform.supported && settings.connectionMode == ConnectionMode.tun) {
        if (!await vpn.prepare()) throw CoreException('VPN permission denied');
      }
      final resolved = await ServerAddressResolver.pickFastestIp(server);
      final core = _coreName(resolved);
      final xrayPool = pool.where((s) => !s.params.containsKey('json') && s.effectiveCore == CoreType.xray).toList();
      _balanced = settings.autoSwitch && core == 'xray' && xrayPool.length > 1;

      final desktopTun = !VpnPlatform.supported && settings.connectionMode == ConnectionMode.tun;
      final useXrayTun = desktopTun && core == 'xray' && settings.tunEngine == TunEngine.xrayTun;
      final singboxNativeTun = desktopTun && core == 'singbox';
      _tunWrapper = desktopTun && !useXrayTun && !singboxNativeTun;

      // Route profile seen by the proxy core: in wrapper mode sing-box does
      // the split, so the proxy core forwards everything.
      final coreRouting = _tunWrapper ? routing.copyWith(mode: RoutingMode.global) : routing;
      final Map<String, dynamic> cfg;
      if (core == 'xray') {
        final b = XrayConfigBuilder(settings.copyWith(
          connectionMode: useXrayTun ? ConnectionMode.tun : ConnectionMode.proxyOnly,
        ));
        cfg = _balanced
            ? b.buildBalanced([resolved, ...xrayPool.where((s) => s.id != server.id)], coreRouting, subFragment: sub?.fragment)
            : b.buildMain(resolved, coreRouting, subFragment: sub?.fragment, subNoises: sub?.noises);
      } else {
        cfg = SingboxConfigBuilder(settings).buildMain(resolved, coreRouting, tun: singboxNativeTun);
      }
      final cfgJson = jsonEncode(cfg);
      await bridge.startInstance(mainId, core, cfgJson);

      if (_tunWrapper) {
        // The wrapper must exclude the server's IPs from the TUN, otherwise the
        // proxy core's own outbound socket is captured by the TUN and loops back
        // into the proxy. Hostnames have to be resolved here: pickFastestIp
        // returns the address unchanged when its DNS lookup failed, which is
        // exactly the situation the tunnel is for.
        final ips = <String>{
          ...await _resolveAll([resolved]),
          if (_balanced) ...await _resolveAll(xrayPool),
        }.toList();
        final wrapper = SingboxConfigBuilder(settings).buildTunWrapper(settings.socksPort, routing, ips);
        await bridge.startInstance(tunId, 'singbox', jsonEncode(wrapper));
      }

      if (VpnPlatform.supported && settings.connectionMode == ConnectionMode.tun) {
        final args = VpnStartArgs(
          socksPort: settings.socksPort,
          mtu: settings.tunMtu,
          ipv6: true,
          sessionName: server.name,
          serverId: server.id,
          splitMode: splitMode,
          packages: splitPackages,
        );
        await vpn.saveLastConfig(core, cfgJson, args, autoConnect: autoConnectOnBoot);
        await vpn.start(args);
      }
      if (settings.connectionMode == ConnectionMode.systemProxy && !VpnPlatform.supported) {
        await SystemProxy.enable(settings.httpPort, settings.socksPort);
        _systemProxy = true;
      }

      current = server;
      connectedAt = DateTime.now();
      await _rebaseTraffic();
      state = VpnState.connected;
      _startTimers();
      notifyListeners();
    } on Object catch (e) {
      await _teardown();
      _fail(FriendlyError.of(e));
    }
  }

  /// Hot switch: only the proxy core is restarted; TUN / VpnService / system
  /// proxy stay up, so apps see at most a single reconnect of open sockets.
  Future<void> switchServer(Server server, RoutingProfile routing, {Subscription? sub}) async {
    if (!isConnected) return connect(server, routing, sub: sub);
    if (_tunWrapper || _balanced) {
      // wrapper excludes server IPs from TUN -> needs a full rebuild
      await disconnect();
      return connect(server, routing, sub: sub);
    }
    try {
      final resolved = await ServerAddressResolver.pickFastestIp(server);
      final core = _coreName(resolved);
      final cfg = core == 'xray'
          ? XrayConfigBuilder(settings.copyWith(connectionMode: ConnectionMode.proxyOnly))
              .buildMain(resolved, routing, subFragment: sub?.fragment, subNoises: sub?.noises)
          : SingboxConfigBuilder(settings).buildMain(resolved, routing);
      await bridge.startInstance(mainId, core, jsonEncode(cfg));
      current = server;
      _healthFails = 0;
      // The replacement core starts its counters from zero again.
      await _rebaseTraffic();
      notifyListeners();
    } on Object catch (e) {
      error = FriendlyError.of(e);
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (state == VpnState.disconnected) return;
    state = VpnState.disconnecting;
    notifyListeners();
    await _teardown();
    _setDisconnected();
  }

  Future<void> _teardown() async {
    _trafficTimer?.cancel();
    _healthTimer?.cancel();
    try {
      if (VpnPlatform.supported) await vpn.stop();
      if (_systemProxy) {
        await SystemProxy.disable();
        _systemProxy = false;
      }
      await bridge.stopInstance(tunId);
      await bridge.stopInstance(mainId);
    } on Object catch (e) {
      debugPrint('teardown: $e');
    }
  }

  void _setDisconnected() {
    _trafficTimer?.cancel();
    _healthTimer?.cancel();
    state = VpnState.disconnected;
    connectedAt = null;
    upRate = downRate = 0;
    livePingMs = null;
    notifyListeners();
  }

  void _fail(String msg) {
    state = VpnState.error;
    error = msg;
    connectedAt = null;
    notifyListeners();
  }

  /// Traffic counters always come from the Go bridge: Xray reports its own
  /// counters and sing-box falls back to the tun2socks totals inside the bridge.
  /// They are never mixed with Android's per-UID TrafficStats — the two are
  /// different scales, and subtracting one from the other clamped every delta to
  /// zero, so the live speed stayed at 0 for the whole session.
  Future<(int, int)> _readTraffic() async {
    try {
      return await bridge.traffic(mainId);
    } on Object {
      return (0, 0);
    }
  }

  /// Re-bases the counters. A new core instance (connect or hot switch) restarts
  /// its counters at zero, so the old baseline must not be subtracted any more.
  Future<void> _rebaseTraffic() async {
    _baseTraffic = await _readTraffic();
    upBytes = downBytes = 0;
    upRate = downRate = 0;
  }

  void _startTimers() {
    _trafficTimer?.cancel();
    _trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!isConnected) return;
      final t = await _readTraffic();
      final up = (t.$1 - _baseTraffic.$1).clamp(0, 1 << 62);
      final down = (t.$2 - _baseTraffic.$2).clamp(0, 1 << 62);
      upRate = (up - upBytes).clamp(0, 1 << 62).toDouble();
      downRate = (down - downBytes).clamp(0, 1 << 62).toDouble();
      upBytes = up;
      downBytes = down;
      notifyListeners();
    });
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(settings.autoSwitch ? settings.healthCheckInterval : const Duration(minutes: 1), (_) => _healthCheck());
    unawaited(_healthCheck());
  }

  /// Measures live ping through the *running* connection. With auto-switch
  /// and no balancer, two consecutive failures (or >3x degradation) trigger
  /// failover to the next best server.
  Future<void> _healthCheck() async {
    if (!isConnected) return;
    final ms = await PingProbes.realDelay(settings.httpPort, Uri.parse(settings.testUrl), const Duration(seconds: 8));
    final prev = livePingMs;
    livePingMs = ms;
    notifyListeners();
    if (!settings.autoSwitch || _balanced || onNeedFailover == null || current == null) return;
    final degraded = ms == null || (prev != null && ms > prev * 3 && ms > 800);
    _healthFails = degraded ? _healthFails + 1 : 0;
    if (_healthFails >= 2) {
      _healthFails = 0;
      final next = await onNeedFailover!(current!);
      if (next != null && next.id != current!.id) {
        _pendingFailover.add(next);
      }
    }
  }

  /// AppState listens and calls [switchServer] with the active routing profile.
  final _pendingFailover = StreamController<Server>.broadcast();
  Stream<Server> get failoverRequests => _pendingFailover.stream;

  Future<List<String>> _resolveAll(List<Server> servers) async {
    final out = <String>[];
    for (final s in servers) {
      if (InternetAddress.tryParse(s.address) != null) {
        out.add(s.address);
        continue;
      }
      try {
        out.addAll((await InternetAddress.lookup(s.address)).map((a) => a.address));
      } on Object {
        continue;
      }
    }
    return out;
  }

  @override
  void dispose() {
    _trafficTimer?.cancel();
    _healthTimer?.cancel();
    _vpnSub?.cancel();
    _pendingFailover.close();
    super.dispose();
  }
}
