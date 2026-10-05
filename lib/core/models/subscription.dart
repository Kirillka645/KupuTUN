/// Traffic / expiry info from the `subscription-userinfo` header.
class SubscriptionUserInfo {
  final int upload;
  final int download;
  final int total;
  final DateTime? expire;

  const SubscriptionUserInfo({this.upload = 0, this.download = 0, this.total = 0, this.expire});

  int get used => upload + download;
  int? get remaining => total > 0 ? (total - used).clamp(0, total) : null;
  double? get usedFraction => total > 0 ? (used / total).clamp(0.0, 1.0) : null;

  bool expiresWithin(Duration d, DateTime now) =>
      expire != null && expire!.isAfter(now) && expire!.difference(now) <= d;
  bool isExpired(DateTime now) => expire != null && !expire!.isAfter(now);

  /// Parses `upload=1; download=2; total=3; expire=1700000000`.
  static SubscriptionUserInfo? parse(String? header) {
    if (header == null || header.trim().isEmpty) return null;
    final m = <String, int>{};
    for (final part in header.split(';')) {
      final kv = part.split('=');
      if (kv.length != 2) continue;
      final v = int.tryParse(kv[1].trim().split('.').first);
      if (v != null) m[kv[0].trim().toLowerCase()] = v;
    }
    if (m.isEmpty) return null;
    final exp = m['expire'];
    return SubscriptionUserInfo(
      upload: m['upload'] ?? 0,
      download: m['download'] ?? 0,
      total: m['total'] ?? 0,
      expire: exp != null && exp > 0 ? DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'upload': upload,
        'download': download,
        'total': total,
        'expire': expire?.millisecondsSinceEpoch,
      };

  factory SubscriptionUserInfo.fromJson(Map<String, dynamic> j) => SubscriptionUserInfo(
        upload: (j['upload'] as num?)?.toInt() ?? 0,
        download: (j['download'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        expire: j['expire'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['expire'] as num).toInt(), isUtc: true),
      );
}

/// Server ordering requested by the provider (`subscriptions-sort-type`).
enum ProviderSortType { none, ping, name }

/// Fragmentation settings delivered by a provider or chosen by the user.
class FragmentSettings {
  final bool enabled;
  final String packets; // "tlshello" | "1-3"
  final String length; // "100-200"
  final String interval; // "10-20" ms
  final int maxSplit; // 0 = core default

  const FragmentSettings({
    this.enabled = false,
    this.packets = 'tlshello',
    this.length = '100-200',
    this.interval = '10-20',
    this.maxSplit = 0,
  });

  FragmentSettings copyWith({bool? enabled, String? packets, String? length, String? interval, int? maxSplit}) =>
      FragmentSettings(
        enabled: enabled ?? this.enabled,
        packets: packets ?? this.packets,
        length: length ?? this.length,
        interval: interval ?? this.interval,
        maxSplit: maxSplit ?? this.maxSplit,
      );

  Map<String, dynamic> toJson() =>
      {'enabled': enabled, 'packets': packets, 'length': length, 'interval': interval, 'maxSplit': maxSplit};
  factory FragmentSettings.fromJson(Map<String, dynamic> j) => FragmentSettings(
        enabled: j['enabled'] as bool? ?? false,
        packets: j['packets'] as String? ?? 'tlshello',
        length: j['length'] as String? ?? '100-200',
        interval: j['interval'] as String? ?? '10-20',
        maxSplit: (j['maxSplit'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() => '$packets/$length/$interval';
}

/// Xray "noises" (UDP noise packets before handshake).
class NoiseSettings {
  final bool enabled;
  final String type; // rand | str | base64
  final String packet; // "10-20" for rand, payload otherwise
  final String delay; // "10-16"

  const NoiseSettings({this.enabled = false, this.type = 'rand', this.packet = '10-20', this.delay = '10-16'});

  Map<String, dynamic> toJson() => {'enabled': enabled, 'type': type, 'packet': packet, 'delay': delay};
  factory NoiseSettings.fromJson(Map<String, dynamic> j) => NoiseSettings(
        enabled: j['enabled'] as bool? ?? false,
        type: j['type'] as String? ?? 'rand',
        packet: j['packet'] as String? ?? '10-20',
        delay: j['delay'] as String? ?? '10-16',
      );
}

class Subscription {
  final String id;
  final String url;
  final String title;
  final Duration updateInterval;
  final DateTime? lastUpdated;
  final SubscriptionUserInfo? userInfo;
  final String? supportUrl;
  final String? webPageUrl;
  final String? announce;
  final bool? routingEnabled;
  final String? routingDeeplink;
  final String? pingType;
  final ProviderSortType sortType;
  final FragmentSettings? fragment;
  final NoiseSettings? noises;
  final bool autoUpdate;
  final bool collapsed;
  final int order;

  /// `url` may contain mirrors separated by `|` (tried in parallel).
  List<String> get mirrors => url.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  /// Host of the first mirror, for titles / display.
  String get displayHost => Uri.tryParse(mirrors.isEmpty ? '' : mirrors.first)?.host ?? url;

  /// Unknown provider headers/comments are kept so newer Happ-only keys are
  /// not lost and can be shown in "Subscription info".
  final Map<String, String> extra;

  const Subscription({
    required this.id,
    required this.url,
    required this.title,
    this.updateInterval = const Duration(hours: 12),
    this.lastUpdated,
    this.userInfo,
    this.supportUrl,
    this.webPageUrl,
    this.announce,
    this.routingEnabled,
    this.routingDeeplink,
    this.pingType,
    this.sortType = ProviderSortType.none,
    this.fragment,
    this.noises,
    this.autoUpdate = true,
    this.collapsed = false,
    this.order = 0,
    this.extra = const {},
  });

  bool needsUpdate(DateTime now) =>
      autoUpdate && (lastUpdated == null || now.difference(lastUpdated!) >= updateInterval);

  Subscription copyWith({
    String? url,
    String? title,
    Duration? updateInterval,
    DateTime? lastUpdated,
    SubscriptionUserInfo? userInfo,
    String? supportUrl,
    String? webPageUrl,
    String? announce,
    bool? routingEnabled,
    String? routingDeeplink,
    String? pingType,
    ProviderSortType? sortType,
    FragmentSettings? fragment,
    NoiseSettings? noises,
    bool? autoUpdate,
    bool? collapsed,
    int? order,
    Map<String, String>? extra,
  }) =>
      Subscription(
        id: id,
        url: url ?? this.url,
        title: title ?? this.title,
        updateInterval: updateInterval ?? this.updateInterval,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        userInfo: userInfo ?? this.userInfo,
        supportUrl: supportUrl ?? this.supportUrl,
        webPageUrl: webPageUrl ?? this.webPageUrl,
        announce: announce ?? this.announce,
        routingEnabled: routingEnabled ?? this.routingEnabled,
        routingDeeplink: routingDeeplink ?? this.routingDeeplink,
        pingType: pingType ?? this.pingType,
        sortType: sortType ?? this.sortType,
        fragment: fragment ?? this.fragment,
        noises: noises ?? this.noises,
        autoUpdate: autoUpdate ?? this.autoUpdate,
        collapsed: collapsed ?? this.collapsed,
        order: order ?? this.order,
        extra: extra ?? this.extra,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'updateIntervalMin': updateInterval.inMinutes,
        'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
        'userInfo': userInfo?.toJson(),
        'supportUrl': supportUrl,
        'webPageUrl': webPageUrl,
        'announce': announce,
        'routingEnabled': routingEnabled,
        'routingDeeplink': routingDeeplink,
        'pingType': pingType,
        'sortType': sortType.name,
        'fragment': fragment?.toJson(),
        'noises': noises?.toJson(),
        'autoUpdate': autoUpdate,
        'collapsed': collapsed,
        'order': order,
        'extra': extra,
      };

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'] as String,
        url: j['url'] as String,
        title: j['title'] as String,
        updateInterval: Duration(minutes: (j['updateIntervalMin'] as num?)?.toInt() ?? 720),
        lastUpdated: j['lastUpdated'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['lastUpdated'] as num).toInt()),
        userInfo: j['userInfo'] == null
            ? null
            : SubscriptionUserInfo.fromJson(Map<String, dynamic>.from(j['userInfo'] as Map)),
        supportUrl: j['supportUrl'] as String?,
        webPageUrl: j['webPageUrl'] as String?,
        announce: j['announce'] as String?,
        routingEnabled: j['routingEnabled'] as bool?,
        routingDeeplink: j['routingDeeplink'] as String?,
        pingType: j['pingType'] as String?,
        sortType: ProviderSortType.values.byName(j['sortType'] as String? ?? 'none'),
        fragment: j['fragment'] == null
            ? null
            : FragmentSettings.fromJson(Map<String, dynamic>.from(j['fragment'] as Map)),
        noises:
            j['noises'] == null ? null : NoiseSettings.fromJson(Map<String, dynamic>.from(j['noises'] as Map)),
        autoUpdate: j['autoUpdate'] as bool? ?? true,
        collapsed: j['collapsed'] as bool? ?? false,
        order: (j['order'] as num?)?.toInt() ?? 0,
        extra: Map<String, String>.from(j['extra'] as Map? ?? const {}),
      );
}
