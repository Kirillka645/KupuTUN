import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config/core_settings.dart';
import '../core/config/xray_config_builder.dart';
import '../core/engine/core_bridge.dart';
import '../core/engine/core_manager.dart';
import '../core/engine/vpn_platform.dart';
import '../core/models/routing_profile.dart';
import '../core/models/server.dart';
import '../core/models/subscription.dart';
import '../core/models/test_result.dart';
import '../core/util/ids.dart';
import '../data/history_db.dart';
import '../data/vault.dart';
import '../routing/geo_updater.dart';
import '../routing/routing_presets.dart';
import '../subscriptions/deeplink.dart';
import '../subscriptions/link_parser.dart';
import '../subscriptions/subscription_fetcher.dart';
import '../subscriptions/stock_subscriptions.dart';
import '../subscriptions/subscription_parser.dart';
import '../tester/server_sorter.dart';
import '../tester/smart_score.dart';
import '../tester/speed_tester.dart';
import '../tester/tester_service.dart';
import '../tester/tester_settings.dart';

/// UI-level settings.
/// How the power button chooses a server.
enum ServerPick { manual, smart, ping }

/// What the Android Quick Settings tile does on tap.
enum TileAction { toggleLast, connectBest, openApp }

class UiSettings {
  final ThemeMode themeMode;
  final int accent; // ARGB seed colour
  final bool dynamicColor; // Material You (Android 12+, Windows/macOS accent)
  final bool amoled; // pure black surfaces in dark mode
  final bool gradientBackground; // Happ-like soft gradient behind the home screen
  final bool compactList;
  final String? locale; // ru | en | fa | zh | null=system
  final bool connectOnLaunch;
  final bool connectOnUntrustedWifi;
  final List<String> trustedSsids;
  final SplitMode splitMode;
  final List<String> splitPackages;
  final ServerPick serverPick;
  final bool pickInSubscription; // auto-pick only inside the selected server's subscription
  final TileAction tileAction;
  final bool pinPowerButton; // power button stays on top while the list scrolls
  final bool showTraffic; // live ↑/↓ speed on Home
  final bool hideDead; // hide servers that failed the last test
  final bool showFlags; // country flag avatars in the list
  final bool confirmDisconnect; // ask before disconnecting
  final bool haptics; // vibration on power button
  final bool notifSpeed; // live speed in the Android VPN notification
  const UiSettings({
    this.themeMode = ThemeMode.system,
    this.accent = 0xFF5B5BD6,
    this.dynamicColor = false,
    this.amoled = false,
    this.gradientBackground = true,
    this.compactList = false,
    this.locale,
    this.connectOnLaunch = false,
    this.connectOnUntrustedWifi = false,
    this.trustedSsids = const [],
    this.splitMode = SplitMode.off,
    this.splitPackages = const [],
    this.serverPick = ServerPick.smart,
    this.pickInSubscription = false,
    this.tileAction = TileAction.toggleLast,
    this.pinPowerButton = true,
    this.showTraffic = true,
    this.hideDead = false,
    this.showFlags = true,
    this.confirmDisconnect = false,
    this.haptics = true,
    this.notifSpeed = true,
  });

  UiSettings copyWith({
    ThemeMode? themeMode,
    int? accent,
    bool? dynamicColor,
    bool? amoled,
    bool? gradientBackground,
    bool? compactList,
    bool? connectOnLaunch,
    bool? connectOnUntrustedWifi,
    List<String>? trustedSsids,
    SplitMode? splitMode,
    List<String>? splitPackages,
    ServerPick? serverPick,
    bool? pickInSubscription,
    TileAction? tileAction,
    bool? pinPowerButton,
    bool? showTraffic,
    bool? hideDead,
    bool? showFlags,
    bool? confirmDisconnect,
    bool? haptics,
    bool? notifSpeed,
  }) =>
      UiSettings(
        themeMode: themeMode ?? this.themeMode,
        accent: accent ?? this.accent,
        dynamicColor: dynamicColor ?? this.dynamicColor,
        amoled: amoled ?? this.amoled,
        gradientBackground: gradientBackground ?? this.gradientBackground,
        compactList: compactList ?? this.compactList,
        locale: locale,
        connectOnLaunch: connectOnLaunch ?? this.connectOnLaunch,
        connectOnUntrustedWifi: connectOnUntrustedWifi ?? this.connectOnUntrustedWifi,
        trustedSsids: trustedSsids ?? this.trustedSsids,
        splitMode: splitMode ?? this.splitMode,
        splitPackages: splitPackages ?? this.splitPackages,
        serverPick: serverPick ?? this.serverPick,
        pickInSubscription: pickInSubscription ?? this.pickInSubscription,
        tileAction: tileAction ?? this.tileAction,
        pinPowerButton: pinPowerButton ?? this.pinPowerButton,
        showTraffic: showTraffic ?? this.showTraffic,
        hideDead: hideDead ?? this.hideDead,
        showFlags: showFlags ?? this.showFlags,
        confirmDisconnect: confirmDisconnect ?? this.confirmDisconnect,
        haptics: haptics ?? this.haptics,
        notifSpeed: notifSpeed ?? this.notifSpeed,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'accent': accent,
        'dynamicColor': dynamicColor,
        'amoled': amoled,
        'gradientBackground': gradientBackground,
        'compactList': compactList,
        'locale': locale,
        'connectOnLaunch': connectOnLaunch,
        'connectOnUntrustedWifi': connectOnUntrustedWifi,
        'trustedSsids': trustedSsids,
        'splitMode': splitMode.name,
        'splitPackages': splitPackages,
        'serverPick': serverPick.name,
        'pickInSubscription': pickInSubscription,
        'tileAction': tileAction.name,
        'pinPowerButton': pinPowerButton,
        'showTraffic': showTraffic,
        'hideDead': hideDead,
        'showFlags': showFlags,
        'confirmDisconnect': confirmDisconnect,
        'haptics': haptics,
        'notifSpeed': notifSpeed,
      };

  factory UiSettings.fromJson(Map<String, dynamic> j) => UiSettings(
        themeMode: ThemeMode.values.asNameMap()[j['themeMode']] ?? ThemeMode.system,
        accent: (j['accent'] as num?)?.toInt() ?? 0xFF5B5BD6,
        dynamicColor: j['dynamicColor'] as bool? ?? false,
        amoled: j['amoled'] as bool? ?? false,
        gradientBackground: j['gradientBackground'] as bool? ?? true,
        compactList: j['compactList'] as bool? ?? false,
        locale: j['locale'] as String?,
        connectOnLaunch: j['connectOnLaunch'] as bool? ?? false,
        connectOnUntrustedWifi: j['connectOnUntrustedWifi'] as bool? ?? false,
        trustedSsids: j['trustedSsids'] is List ? List<String>.from((j['trustedSsids'] as List).map((e) => '$e')) : const [],
        splitMode: SplitMode.values.asNameMap()[j['splitMode']] ?? SplitMode.off,
        splitPackages: j['splitPackages'] is List ? List<String>.from((j['splitPackages'] as List).map((e) => '$e')) : const [],
        serverPick: ServerPick.values.asNameMap()[j['serverPick']] ?? ServerPick.smart,
        pickInSubscription: j['pickInSubscription'] as bool? ?? false,
        tileAction: TileAction.values.asNameMap()[j['tileAction']] ?? TileAction.toggleLast,
        pinPowerButton: j['pinPowerButton'] as bool? ?? true,
        showTraffic: j['showTraffic'] as bool? ?? true,
        hideDead: j['hideDead'] as bool? ?? false,
        showFlags: j['showFlags'] as bool? ?? true,
        confirmDisconnect: j['confirmDisconnect'] as bool? ?? false,
        haptics: j['haptics'] as bool? ?? true,
        notifSpeed: j['notifSpeed'] as bool? ?? true,
      );
}

/// Application state / use-case layer. The UI only talks to this class.
class AppState extends ChangeNotifier {
  final Vault vault;
  final HistoryDb history;
  final CoreBridge bridge;
  final CoreManager core;
  final TesterService tester;
  final SubscriptionFetcher fetcher;
  final String assetDir;
  final _notifications = FlutterLocalNotificationsPlugin();

  List<Server> servers = [];
  List<Subscription> subscriptions = [];
  Map<String, TestResult> results = {};
  Map<String, StabilityBadge> badges = {};
  List<RoutingProfile> routings = RoutingPresets.all();
  String activeRoutingId = 'builtin-ru';
  CoreSettings coreSettings;
  TesterSettings testerSettings = const TesterSettings();
  UiSettings ui = const UiSettings();
  SortBy sortBy = SortBy.smart;
  ServerFilter filter = const ServerFilter();
  String? selectedServerId;
  bool testing = false;

  /// One-shot guard for the "cannot read the Wi-Fi name" hint.
  bool _warnedWifiSsid = false;

  /// Servers queued in the running ping test (rows show a spinner).
  Set<String> pendingPing = {};

  /// Subscriptions currently being refreshed (the ⟳ icon spins).
  Set<String> updatingSubs = {};

  /// Subscription whose group ping (⏲ icon) is running, or '*' for all.
  String? pingingGroup;

  /// Power button is choosing the best server (quick test may run first).
  bool picking = false;

  /// Built-in public subscriptions were added once (deleting them sticks).
  bool stockSeeded = false;

  /// The user tapped a server in auto-pick mode: honour it for the next
  /// connection instead of auto-picking. Cleared on disconnect.
  bool _manualOverride = false;
  TestProgress? progress;
  String? lastMessage;
  StreamSubscription<Server>? _failoverSub;
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  AppState._({
    required this.vault,
    required this.history,
    required this.bridge,
    required this.core,
    required this.tester,
    required this.fetcher,
    required this.assetDir,
    required this.coreSettings,
  }) {
    core.addListener(notifyListeners);
    core.onNeedFailover = (cur) async => ServerSorter.best(servers.where((s) => s.id != cur.id).toList(), results, testerSettings.weights);
    _failoverSub = core.failoverRequests.listen((s) {
      selectedServerId = s.id;
      core.switchServer(s, activeRouting, sub: _subOf(s));
    });
    core.resolveServer = (id) {
      for (final s in servers) {
        if (s.id == id) {
          selectedServerId = id;
          return s;
        }
      }
      return null;
    };
    core.onPlatformAction = _onPlatformAction;
  }

  /// Quick Settings tile asked for "connect to the best server" (opens the app).
  Future<void> _onPlatformAction(String action) async {
    if (action != 'connect_best' || core.isConnected || core.isBusy) return;
    for (var i = 0; i < 40 && !_ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (servers.isEmpty) return;
    _manualOverride = false;
    final best = await _pickBest();
    if (best != null) selectedServerId = best.id;
    await saveSettings();
    if (!core.isConnected && !core.isBusy) await toggleConnection(skipPick: true);
  }

  /// For widget tests / UI previews: inject fakes, skip disk restore and startup tasks.
  @visibleForTesting
  AppState.test({
    required Vault vault,
    required HistoryDb history,
    required CoreBridge bridge,
    required CoreManager core,
    required TesterService tester,
    required SubscriptionFetcher fetcher,
    CoreSettings coreSettings = const CoreSettings(),
  }) : this._(
          vault: vault,
          history: history,
          bridge: bridge,
          core: core,
          tester: tester,
          fetcher: fetcher,
          assetDir: '',
          coreSettings: coreSettings,
        );

  /// Reads a vault entry, treating an unreadable one as absent. A lost keystore
  /// key or a corrupt file must never stop the app from starting.
  static Future<Map<String, dynamic>?> _readJsonSafe(Vault vault, String name) async {
    try {
      return await vault.readJson(name);
    } on Object {
      return null;
    }
  }

  /// Builds a list from persisted JSON, skipping individual malformed entries
  /// instead of losing the whole collection.
  static List<T> _mapList<T>(Object? raw, T Function(Map<String, dynamic>) build) {
    if (raw is! List) return [];
    final out = <T>[];
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        out.add(build(Map<String, dynamic>.from(e)));
      } on Object {
        continue;
      }
    }
    return out;
  }

  static Future<AppState> load() async {
    final support = await getApplicationSupportDirectory();
    final vault = Vault(Directory('${support.path}/vault'));
    final history = await HistoryDb.open('${support.path}/history.db');
    final bridge = CoreBridge.create();
    final assetDir = '${support.path}/assets';
    Object? bridgeError;
    try {
      await bridge.setAssetDir(assetDir);
    } on Object catch (e) {
      // Desktop: libkuputun.dll/.so/.dylib missing next to the executable.
      // Keep going so the window still opens and the user gets a real message.
      bridgeError = e;
    }

    final settingsJson = await _readJsonSafe(vault, 'settings') ?? const {};
    var coreSettings = const CoreSettings();
    final rawCore = settingsJson['core'];
    if (rawCore is Map) {
      try {
        coreSettings = CoreSettings.fromJson(Map<String, dynamic>.from(rawCore));
      } on Object {
        coreSettings = const CoreSettings();
      }
    }
    coreSettings = coreSettings.copyWith(logPath: '${support.path}/core.log');

    final identity = await _identity(vault);
    final state = AppState._(
      vault: vault,
      history: history,
      bridge: bridge,
      core: CoreManager(bridge, VpnPlatform(), coreSettings),
      tester: TesterService(bridge, coreSettings),
      fetcher: SubscriptionFetcher(identity),
      assetDir: assetDir,
      coreSettings: coreSettings,
    );
    await state._restore(settingsJson);
    if (bridgeError != null) {
      state._message('Ядро недоступно (${Platform.operatingSystem}): $bridgeError');
    }
    await state._initNotifications();
    await state.core.syncWithPlatform();
    unawaited(state._syncTileAction());
    state._ready = true;
    unawaited(state._startupTasks());
    return state;
  }

  static Future<DeviceIdentity> _identity(Vault vault) async {
    final dev = await vault.readJson('device') ?? {};
    var hwid = dev['hwid'] as String?;
    if (hwid == null) {
      hwid = uuidV4().replaceAll('-', '');
      await vault.writeJson('device', {'hwid': hwid});
    }
    final info = DeviceInfoPlugin();
    final pkg = await PackageInfo.fromPlatform();
    String os = Platform.operatingSystem, ver = Platform.operatingSystemVersion, model = 'PC';
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      os = 'Android';
      ver = a.version.release;
      model = '${a.manufacturer} ${a.model}';
    } else if (Platform.isIOS) {
      final i = await info.iosInfo;
      os = 'iOS';
      ver = i.systemVersion;
      model = i.utsname.machine;
    } else if (Platform.isWindows) {
      final w = await info.windowsInfo;
      os = 'Windows';
      ver = '${w.majorVersion}.${w.minorVersion}.${w.buildNumber}';
      model = 'Windows PC';
    } else if (Platform.isMacOS) {
      final m = await info.macOsInfo;
      os = 'macOS';
      ver = m.osRelease;
      model = m.model;
    } else if (Platform.isLinux) {
      final l = await info.linuxInfo;
      os = 'Linux';
      ver = l.versionId ?? l.version ?? '';
      model = l.prettyName;
    }
    return DeviceIdentity(hwid: hwid, os: os, osVersion: ver, model: model, appVersion: pkg.version);
  }

  Future<void> _restore(Map<String, dynamic> settingsJson) async {
    final data = await _readJsonSafe(vault, 'data') ?? const {};
    servers = _mapList(data['servers'], Server.fromJson);
    subscriptions = _mapList(data['subscriptions'], Subscription.fromJson)
      ..sort((a, b) => a.order.compareTo(b.order));
    final custom = _mapList(data['routings'], RoutingProfile.fromJson);
    routings = [...RoutingPresets.all(), ...custom];
    activeRoutingId = settingsJson['routing'] as String? ?? 'builtin-ru';
    selectedServerId = settingsJson['selected'] as String?;
    final rawTester = settingsJson['tester'];
    if (rawTester is Map) {
      try {
        testerSettings = TesterSettings.fromJson(Map<String, dynamic>.from(rawTester));
      } on Object {
        testerSettings = const TesterSettings();
      }
    }
    final rawUi = settingsJson['ui'];
    if (rawUi is Map) {
      try {
        ui = UiSettings.fromJson(Map<String, dynamic>.from(rawUi));
      } on Object {
        ui = const UiSettings();
      }
    }
    sortBy = SortBy.values.asNameMap()[settingsJson['sortBy']] ?? SortBy.smart;
    stockSeeded = settingsJson['stockSeeded'] as bool? ?? false;
    try {
      results = await history.latestAll();
    } on Object {
      results = {};
    }
    await _refreshBadges(results.keys);
  }

  Future<void> _refreshBadges(Iterable<String> ids) async {
    for (final id in ids.toList()) {
      badges[id] = SmartScore.badge(await history.history(id, limit: 20));
    }
  }

  Future<void> _startupTasks() async {
    final geo = GeoUpdater(assetDir);
    if (await geo.needsUpdate()) {
      try {
        await geo.update(activeRouting);
      } on Object catch (e) {
        _message('Geo-файлы не обновлены: $e');
      }
    }
    if (!stockSeeded) {
      _addStock();
      stockSeeded = true;
      await _saveData();
      await saveSettings();
    }
    await updateAllSubscriptions(onlyDue: true);
    if (testerSettings.autoTestOnLaunch && servers.isNotEmpty) unawaited(testAll());
    if (ui.connectOnLaunch && selected != null && !core.isConnected && !core.isBusy) unawaited(toggleConnection());
    unawaited(_checkExpiry());
    _netSub = Connectivity().onConnectivityChanged.listen(_onNetworkChanged);
  }

  /// Auto-connect on untrusted Wi-Fi (SSID not in [UiSettings.trustedSsids]).
  ///
  /// Android needs location permission (<= API 12) or NEARBY_WIFI_DEVICES (13+)
  /// to read the SSID, and this build deliberately ships neither (Google Play
  /// policy). When the name cannot be read, "unknown" is indistinguishable from
  /// "untrusted", so the connection is skipped instead of firing on the user's
  /// own trusted network.
  Future<void> _onNetworkChanged(List<ConnectivityResult> r) async {
    if (!ui.connectOnUntrustedWifi || core.isConnected || core.isBusy || selected == null) return;
    if (!r.contains(ConnectivityResult.wifi)) return;
    String? ssid;
    try {
      ssid = (await NetworkInfo().getWifiName())?.replaceAll('"', '');
    } on Object {
      ssid = null;
    }
    if (ssid == null || ssid.isEmpty) {
      if (!_warnedWifiSsid) {
        _warnedWifiSsid = true;
        _message('Система не отдаёт имя Wi-Fi, поэтому автоподключение по '
            '«недоверенным» сетям пропущено: иначе оно срабатывало бы и на доверенных');
      }
      return;
    }
    if (ui.trustedSsids.contains(ssid)) return;
    await toggleConnection();
  }

  // ------------------------------------------------------------ persistence

  Future<void> _saveData() => vault.writeJson('data', {
        'servers': servers.map((e) => e.toJson()).toList(),
        'subscriptions': subscriptions.map((e) => e.toJson()).toList(),
        'routings': routings.where((r) => !r.builtIn).map((e) => e.toJson()).toList(),
      });

  Future<void> saveSettings() async {
    core.settings = coreSettings;
    tester.coreSettings = coreSettings;
    await vault.writeJson('settings', {
      'core': coreSettings.toJson(),
      'tester': testerSettings.toJson(),
      'ui': ui.toJson(),
      'routing': activeRoutingId,
      'selected': selectedServerId,
      'sortBy': sortBy.name,
      'stockSeeded': stockSeeded,
    });
    notifyListeners();
  }

  void _message(String m) {
    lastMessage = m;
    notifyListeners();
  }

  String? takeMessage() {
    final m = lastMessage;
    lastMessage = null;
    return m;
  }

  // ------------------------------------------------------------ getters

  RoutingProfile get activeRouting => routings.firstWhere((r) => r.id == activeRoutingId, orElse: () => routings.first);

  Server? get selected {
    for (final s in servers) {
      if (s.id == selectedServerId) return s;
    }
    return servers.isEmpty ? null : servers.first;
  }

  Subscription? _subOf(Server s) {
    for (final sub in subscriptions) {
      if (sub.id == s.subscriptionId) return sub;
    }
    return null;
  }

  Subscription? subscriptionOf(Server s) => _subOf(s);

  List<Server> visibleServers({String? subscriptionId}) => ServerSorter.apply(
        servers
            .where((s) => s.subscriptionId == subscriptionId)
            .where((s) => !ui.hideDead || s.id == selectedServerId || !(results[s.id] != null && !results[s.id]!.isAlive))
            .toList(),
        results,
        sortBy: sortBy,
        filter: filter,
        weights: testerSettings.weights,
      );

  double score(Server s) => SmartScore.compute(results[s.id], testerSettings.weights);

  Future<List<TestResult>> historyOf(Server s) => history.history(s.id);

  Set<String> get knownCountries => {
        for (final s in servers)
          if ((results[s.id]?.exitCountry ?? s.countryCode) != null) (results[s.id]?.exitCountry ?? s.countryCode)!,
      };

  // ------------------------------------------------------------ import

  /// Imports from clipboard/QR/file text: share links, base64 lists, JSON
  /// configs, subscription URLs or deeplinks. Returns number of added items.
  Future<int> importText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return 0;
    final action = DeepLinkParser.parse(t.split('\n').first.trim());
    if (action is AddSubscriptionAction) {
      await addSubscription(action.url, name: action.name);
      return 1;
    }
    if (action is AddRoutingAction) {
      routings = [...routings.where((r) => r.id != action.profile.id), action.profile];
      if (action.activate) activeRoutingId = action.profile.id;
      await _saveData();
      await saveSettings();
      return 1;
    }
    // multi-line lists are parsed whole; single deeplinks may carry a base64 list
    final source = action is ImportLinksAction && !t.contains('\n') ? action.text : t;
    final parsed = SubscriptionParser.parse(source);
    if (parsed.servers.isEmpty) return 0;
    final base = servers.where((s) => s.subscriptionId == null).length;
    servers = [
      ...servers,
      for (var i = 0; i < parsed.servers.length; i++) parsed.servers[i].copyWith(sortIndex: base + i),
    ];
    await _saveData();
    notifyListeners();
    return parsed.servers.length;
  }

  Future<void> addManualServer(Server s) async {
    servers = [...servers.where((e) => e.id != s.id), s];
    await _saveData();
    notifyListeners();
  }

  String exportLink(Server s, {ShareMask mask = ShareMask.none}) => LinkExporter.toLink(s, mask: mask);

  // ------------------------------------------------------------ subscriptions

  Future<void> addSubscription(String url, {String? name}) async {
    final existing = subscriptions.where((s) => s.url == url);
    final sub = existing.isNotEmpty
        ? existing.first
        : Subscription(id: uuidV4(), url: url, title: name ?? Subscription(id: '', url: url, title: '').displayHost, order: subscriptions.length);
    if (existing.isEmpty) {
      subscriptions = [...subscriptions, sub];
      // Persist before fetching: the fetch path only saves on success, so a
      // first fetch that fails (offline, block page, typo) used to lose the URL
      // the user just pasted.
      await _saveData();
      notifyListeners();
    }
    await updateSubscription(sub);
  }

  /// Adds missing built-in subscriptions; returns how many were added.
  int _addStock() {
    var n = 0;
    for (final st in StockSubscriptions.all) {
      if (subscriptions.any((s) => s.url == st.url)) continue;
      subscriptions = [
        ...subscriptions,
        Subscription(id: uuidV4(), url: st.url, title: st.title, order: subscriptions.length, updateInterval: const Duration(hours: 1)),
      ];
      n++;
    }
    return n;
  }

  /// Settings → "Вернуть стандартные подписки".
  Future<int> restoreStockSubscriptions() async {
    final n = _addStock();
    await _saveData();
    notifyListeners();
    await updateAllSubscriptions(onlyDue: true);
    return n;
  }

  /// Subscriptions update one after another, but each races its mirrors.
  /// Run them concurrently so three stock lists don't take 3× as long.
  Future<void> updateAllSubscriptions({bool onlyDue = false}) async {
    final now = DateTime.now();
    await Future.wait([
      for (final s in [...subscriptions])
        if (!onlyDue || s.needsUpdate(now)) updateSubscription(s),
    ]);
  }

  /// Fetch strategy (fastest first, stops at first success):
  /// 1. direct  2. through the running VPN  3. fragmented direct (temp core)
  /// 4. domain fronting (if sub.extra['fronting-host'] is set).
  Future<void> updateSubscription(Subscription sub) async {
    if (updatingSubs.contains(sub.id)) return;
    updatingSubs = {...updatingSubs, sub.id};
    notifyListeners();
    try {
      await _updateSubscription(sub);
    } finally {
      updatingSubs = {...updatingSubs}..remove(sub.id);
      notifyListeners();
    }
  }

  Future<void> _updateSubscription(Subscription sub) async {
    ParsedSubscription? parsed;
    Object? lastErr;
    final attempts = <Future<ParsedSubscription> Function()>[
      () => fetcher.fetch(sub),
      if (core.isConnected) () => fetcher.fetch(sub, options: FetchOptions(proxyPort: coreSettings.httpPort)),
      () => _fetchFragmented(sub),
      if ((sub.extra['fronting-host'] ?? '').isNotEmpty) () => fetcher.fetch(sub, options: FetchOptions(frontingHost: sub.extra['fronting-host'])),
    ];
    for (final a in attempts) {
      try {
        parsed = await a();
        break;
      } on Object catch (e) {
        lastErr = e;
      }
    }
    if (parsed == null) {
      _message('Не удалось обновить «${sub.title}»: $lastErr');
      return;
    }
    // The user may have collapsed/renamed/deleted it while we were fetching.
    final idx = subscriptions.indexWhere((s) => s.id == sub.id);
    if (idx < 0) return;
    var updated = parsed.applyTo(subscriptions[idx], DateTime.now());
    final stock = StockSubscriptions.of(updated.url);
    if (stock != null && subscriptions[idx].title == stock.title) updated = updated.copyWith(title: stock.title);
    // keep ids of unchanged servers -> history/badges survive updates.
    // Each old server is consumed at most once: two entries of one subscription
    // can share a fingerprint (same endpoint, different remarks) and giving both
    // the same id made them indistinguishable — deleting one deleted both.
    final old = <String, List<Server>>{};
    for (final s in servers.where((s) => s.subscriptionId == sub.id)) {
      old.putIfAbsent(s.fingerprint, () => []).add(s);
    }
    final fresh = <Server>[];
    for (final s in parsed.servers) {
      final candidates = old[s.fingerprint];
      final match = (candidates != null && candidates.isNotEmpty) ? candidates.removeAt(0) : null;
      fresh.add(match == null ? s : s.copyWith(id: match.id, favorite: match.favorite));
    }
    servers = [...servers.where((s) => s.subscriptionId != sub.id), ...fresh];
    subscriptions = [for (final s in subscriptions) s.id == sub.id ? updated : s];
    final provider = TesterSettings.fromProviderPingType(updated.pingType);
    if (provider != null && provider != testerSettings.pingMode) testerSettings = testerSettings.copyWith(pingMode: provider);
    if (updated.routingDeeplink != null && updated.routingEnabled != false) {
      final a = DeepLinkParser.parse(updated.routingDeeplink!);
      if (a is AddRoutingAction) {
        routings = [...routings.where((r) => r.name != a.profile.name || r.builtIn), a.profile];
        if (a.activate || updated.routingEnabled == true) activeRoutingId = a.profile.id;
      }
    }
    await _saveData();
    await saveSettings();
    notifyListeners();
    unawaited(_checkExpiry());
    if (testerSettings.autoTestAfterUpdate) unawaited(testAll(only: fresh));
  }

  Future<ParsedSubscription> _fetchFragmented(Subscription sub) async {
    final port = (await bridge.freePorts(1)).first;
    final frag = sub.fragment?.enabled == true ? sub.fragment! : const FragmentSettings(enabled: true);
    final cfg = XrayConfigBuilder(coreSettings).buildFragmentedDirect(port, frag);
    await bridge.startInstance('subfetch-${sub.id}', 'xray', jsonEncode(cfg));
    try {
      return await fetcher.fetch(sub, options: FetchOptions(proxyPort: port));
    } finally {
      await bridge.stopInstance('subfetch-${sub.id}');
    }
  }

  Future<void> deleteSubscription(Subscription sub) async {
    for (final s in servers.where((s) => s.subscriptionId == sub.id)) {
      await history.deleteServer(s.id);
    }
    servers = servers.where((s) => s.subscriptionId != sub.id).toList();
    subscriptions = subscriptions.where((s) => s.id != sub.id).toList();
    await _saveData();
    notifyListeners();
  }

  bool get allCollapsed => subscriptions.isNotEmpty && subscriptions.every((s) => s.collapsed);

  /// "Скрыть всё / Показать всё".
  Future<void> setAllCollapsed(bool collapsed) async {
    subscriptions = [for (final s in subscriptions) s.copyWith(collapsed: collapsed)];
    await _saveData();
    notifyListeners();
  }

  /// ⏲ in a group header: ping only that subscription (null = manual servers).
  Future<void> testGroup(String? subscriptionId) async {
    if (testing) return;
    pingingGroup = subscriptionId ?? '';
    try {
      await testAll(only: servers.where((s) => s.subscriptionId == subscriptionId).toList());
    } finally {
      pingingGroup = null;
      notifyListeners();
    }
  }

  Future<void> renameSubscription(Subscription sub, String title) async {
    subscriptions = [for (final s in subscriptions) s.id == sub.id ? s.copyWith(title: title) : s];
    await _saveData();
    notifyListeners();
  }

  Future<void> toggleCollapsed(Subscription sub) async {
    subscriptions = [for (final s in subscriptions) s.id == sub.id ? s.copyWith(collapsed: !s.collapsed) : s];
    await _saveData();
    notifyListeners();
  }

  Future<void> deleteServer(Server s) async {
    servers = servers.where((e) => e.id != s.id).toList();
    results.remove(s.id);
    await history.deleteServer(s.id);
    await _saveData();
    notifyListeners();
  }

  Future<void> toggleFavorite(Server s) async {
    servers = [for (final e in servers) e.id == s.id ? e.copyWith(favorite: !e.favorite) : e];
    await _saveData();
    notifyListeners();
  }

  // ------------------------------------------------------------ testing

  /// Servers requested while another test was running; tested right after it.
  final Set<String> _queuedTest = {};

  Future<void> testAll({List<Server>? only}) async {
    if (testing) {
      if (only != null) _queuedTest.addAll(only.map((s) => s.id));
      return;
    }
    final list = only ?? servers;
    if (list.isEmpty) return;
    testing = true;
    pendingPing = {for (final s in list) s.id};
    progress = TestProgress(0, list.length);
    notifyListeners();
    final batch = <TestResult>[];
    try {
      await for (final p in tester.pingAll(list, testerSettings)) {
        progress = p;
        final r = p.result;
        if (r != null) {
          pendingPing.remove(r.serverId);
          final prev = results[r.serverId];
          // keep last speed/services; replace latency
          results[r.serverId] = prev == null
              ? r
              : TestResult(
                  serverId: r.serverId,
                  timestamp: r.timestamp,
                  mode: r.mode,
                  samples: r.samples,
                  medianMs: r.medianMs,
                  jitterMs: r.jitterMs,
                  lossPercent: r.lossPercent,
                  tlsHandshakeMs: r.tlsHandshakeMs,
                  downloadMbps: prev.downloadMbps,
                  uploadMbps: prev.uploadMbps,
                  exitIp: prev.exitIp,
                  exitCountry: prev.exitCountry,
                  services: prev.services,
                  error: r.error,
                );
          batch.add(r);
        }
        notifyListeners();
      }
      await history.insertAll(batch);
      await _refreshBadges(batch.map((e) => e.serverId));
    } finally {
      testing = false;
      pendingPing = {};
      progress = null;
      notifyListeners();
      if (_queuedTest.isNotEmpty) {
        final next = servers.where((s) => _queuedTest.contains(s.id)).toList();
        _queuedTest.clear();
        if (next.isNotEmpty) unawaited(testAll(only: next));
      }
    }
  }

  void cancelTests() => tester.cancel();

  /// Worst-case traffic for speed-testing [n] servers, shown before start.
  int speedTrafficEstimate(int n) =>
      SpeedConfig.forMode(testerSettings.speedMode, customDownloadUrl: testerSettings.customSpeedUrl, upload: testerSettings.speedUpload).maxTrafficBytes * n;

  Future<TestResult> speedTest(Server s, {void Function(SpeedSample)? onSample}) async {
    final r = await tester.speedTest(s, testerSettings, onSample: onSample);
    results[s.id] = (results[s.id] ?? r).merge(r);
    await history.insert(results[s.id]!);
    notifyListeners();
    return r;
  }

  Future<TestResult> checkServices(Server s) async {
    final r = await tester.serviceCheck(s);
    results[s.id] = (results[s.id] ?? r).merge(r);
    notifyListeners();
    return r;
  }

  // ------------------------------------------------------------ connection

  Future<void> select(Server s) async {
    selectedServerId = s.id;
    if (ui.serverPick != ServerPick.manual) _manualOverride = true;
    await saveSettings();
    if (core.isConnected) await core.switchServer(s, activeRouting, sub: _subOf(s));
  }

  Future<void> toggleConnection({bool skipPick = false}) async {
    if (picking) return;
    if (core.isConnected || core.state == VpnState.connecting) {
      _manualOverride = false;
      await core.disconnect();
      return;
    }
    if (!skipPick && ui.serverPick != ServerPick.manual && !_manualOverride && servers.isNotEmpty) {
      final best = await _pickBest();
      if (best != null) selectedServerId = best.id;
      await saveSettings();
    }
    final s = selected;
    if (s == null) {
      _message('Добавьте сервер или подписку');
      return;
    }
    final pool = coreSettings.autoSwitch
        ? servers.where((e) => e.subscriptionId == s.subscriptionId && (results[e.id]?.isAlive ?? false)).toList()
        : const <Server>[];
    core.autoConnectOnBoot = ui.connectOnLaunch;
    core.splitMode = ui.splitMode;
    core.splitPackages = ui.splitPackages;
    await core.connect(s, activeRouting, sub: _subOf(s), pool: pool);
  }

  /// Candidates for auto-pick: whole list or only the selected server's subscription.
  List<Server> _pickCandidates() {
    final cur = selected;
    if (!ui.pickInSubscription || cur == null) return servers;
    final same = servers.where((s) => s.subscriptionId == cur.subscriptionId).toList();
    return same.isEmpty ? servers : same;
  }

  /// Best server by the configured rule. Re-tests first when results are
  /// missing or older than 10 minutes, so the choice reflects the current network.
  Future<Server?> _pickBest() async {
    final cands = _pickCandidates();
    if (cands.isEmpty) return null;
    picking = true;
    notifyListeners();
    try {
      final now = DateTime.now();
      final fresh = cands.any((s) {
        final r = results[s.id];
        return r != null && r.isAlive && now.difference(r.timestamp) < const Duration(minutes: 10);
      });
      if (!fresh && !testing) await testAll(only: cands);
      return bestOf(cands, ui.serverPick == ServerPick.manual ? ServerPick.smart : ui.serverPick);
    } finally {
      picking = false;
      notifyListeners();
    }
  }

  /// Pure selection used by the power button, the tray and the UI badge.
  Server? bestOf(List<Server> list, ServerPick rule) {
    if (rule == ServerPick.ping) {
      Server? best;
      for (final s in list) {
        final r = results[s.id];
        if (r == null || !r.isAlive) continue;
        if (best == null || r.medianMs! < results[best.id]!.medianMs!) best = s;
      }
      return best;
    }
    return ServerSorter.best(list, results, testerSettings.weights);
  }

  /// Server the power button would pick right now (for the "Авто" hint).
  Server? get autoPickPreview => ui.serverPick == ServerPick.manual ? null : bestOf(_pickCandidates(), ui.serverPick);

  /// Tray "Лучший сервер": always picks by the configured rule (Smart if manual).
  Future<void> connectBest() async {
    final best = await _pickBest();
    if (best == null) {
      _message('Нет доступных серверов');
      return;
    }
    selectedServerId = best.id;
    _manualOverride = true;
    await saveSettings();
    if (core.isConnected) {
      await core.switchServer(best, activeRouting, sub: _subOf(best));
    } else {
      await toggleConnection();
    }
  }

  // ------------------------------------------------------------ notifications

  Future<void> _initNotifications() async {
    if (Platform.isWindows) return; // tray balloon is used instead
    await _notifications.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('ic_tile'),
      macOS: DarwinInitializationSettings(),
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    ));
    // Android 13+: without this the VPN status notification (with the
    // «Отключить» button) is silently hidden.
    if (Platform.isAndroid) {
      unawaited(_notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission()
          .catchError((Object _) => false));
    }
  }

  Future<void> _checkExpiry() async {
    final now = DateTime.now();
    final notified = await vault.readJson('notified') ?? {};
    for (final s in subscriptions) {
      final exp = s.userInfo?.expire;
      if (exp == null || !s.userInfo!.expiresWithin(const Duration(days: 3), now.toUtc())) continue;
      final key = '${s.id}:${exp.millisecondsSinceEpoch}';
      if (notified[key] == true) continue;
      notified[key] = true;
      final days = exp.difference(now.toUtc()).inHours ~/ 24;
      if (!Platform.isWindows) {
        await _notifications.show(
          s.id.hashCode & 0x7fffffff,
          'Подписка «${s.title}» скоро закончится',
          days <= 0 ? 'Осталось меньше суток. Нажмите «Продлить».' : 'Осталось дней: $days. Нажмите «Продлить».',
          const NotificationDetails(
            android: AndroidNotificationDetails('expiry', 'Окончание подписки', importance: Importance.high),
            macOS: DarwinNotificationDetails(),
            linux: LinuxNotificationDetails(),
          ),
        );
      } else {
        _message('Подписка «${s.title}» заканчивается через $days дн.');
      }
    }
    await vault.writeJson('notified', notified);
  }

  // ------------------------------------------------------------ settings helpers

  Future<void> updateCore(CoreSettings s) async {
    coreSettings = s;
    await saveSettings();
  }

  Future<void> updateTester(TesterSettings s) async {
    testerSettings = s;
    await saveSettings();
  }

  bool _ready = false;

  Future<void> _syncTileAction() async {
    if (!VpnPlatform.supported) return;
    try {
      await core.vpn.setNativePrefs(tileAction: ui.tileAction.name, notifSpeed: ui.notifSpeed);
    } on Object catch (e) {
      debugPrint('tile: $e');
    }
  }

  Future<void> updateUi(UiSettings s) async {
    final tileChanged = s.tileAction != ui.tileAction || s.notifSpeed != ui.notifSpeed;
    ui = s;
    if (tileChanged) unawaited(_syncTileAction());
    if (s.serverPick == ServerPick.manual) _manualOverride = false;
    await saveSettings();
  }

  Future<void> setRouting(String id) async {
    activeRoutingId = id;
    await saveSettings();
    if (core.isConnected && selected != null) {
      await core.disconnect();
      await toggleConnection();
    }
  }

  Future<void> setSort(SortBy s) async {
    sortBy = s;
    await saveSettings();
  }

  void setFilter(ServerFilter f) {
    filter = f;
    notifyListeners();
  }

  @override
  void dispose() {
    _failoverSub?.cancel();
    _netSub?.cancel();
    core.removeListener(notifyListeners);
    core.dispose();
    super.dispose();
  }
}
