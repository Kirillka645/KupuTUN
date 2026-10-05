import 'dart:convert';

/// Supported outbound protocols.
enum ProxyProtocol {
  vless,
  vmess,
  trojan,
  shadowsocks,
  socks,
  hysteria2,
  tuic,
  wireguard;

  static ProxyProtocol? fromScheme(String scheme) {
    switch (scheme.toLowerCase()) {
      case 'vless':
        return ProxyProtocol.vless;
      case 'vmess':
        return ProxyProtocol.vmess;
      case 'trojan':
        return ProxyProtocol.trojan;
      case 'ss':
        return ProxyProtocol.shadowsocks;
      case 'socks':
      case 'socks5':
        return ProxyProtocol.socks;
      case 'hy2':
      case 'hysteria2':
        return ProxyProtocol.hysteria2;
      case 'tuic':
        return ProxyProtocol.tuic;
      case 'wg':
      case 'wireguard':
        return ProxyProtocol.wireguard;
    }
    return null;
  }

  String get label => switch (this) {
        ProxyProtocol.vless => 'VLESS',
        ProxyProtocol.vmess => 'VMess',
        ProxyProtocol.trojan => 'Trojan',
        ProxyProtocol.shadowsocks => 'Shadowsocks',
        ProxyProtocol.socks => 'SOCKS5',
        ProxyProtocol.hysteria2 => 'Hysteria2',
        ProxyProtocol.tuic => 'TUIC',
        ProxyProtocol.wireguard => 'WireGuard',
      };
}

/// Which core should run a server. `auto` picks the best supported core:
/// Hysteria2/TUIC -> sing-box, everything else -> Xray.
enum CoreType { auto, xray, singbox }

/// One proxy endpoint.
///
/// Decision: transport/security options are kept in a flat string map
/// ([params]) with the same keys used by share links (type, security, sni,
/// fp, pbk, sid, spx, flow, path, host, serviceName, mode, alpn, ...). This
/// keeps parse -> store -> export lossless, even for keys we don't know yet.
class Server {
  final String id;
  final String? subscriptionId;
  final String name;
  final ProxyProtocol protocol;
  final String address;
  final int port;

  /// UUID (vless/vmess/tuic), password (trojan/ss/hy2), username (socks),
  /// private key (wireguard).
  final String credential;

  /// Secondary secret: socks password, tuic password, ss method.
  final String? secret;
  final Map<String, String> params;
  final String? rawLink;
  final String? countryCode;
  final int sortIndex;
  final CoreType core;
  final bool favorite;

  const Server({
    required this.id,
    required this.name,
    required this.protocol,
    required this.address,
    required this.port,
    required this.credential,
    this.subscriptionId,
    this.secret,
    this.params = const {},
    this.rawLink,
    this.countryCode,
    this.sortIndex = 0,
    this.core = CoreType.auto,
    this.favorite = false,
  });

  String param(String key, [String fallback = '']) => params[key] ?? fallback;

  String get transport => param('type', 'tcp');
  String get security => param('security', 'none');

  CoreType get effectiveCore {
    if (core != CoreType.auto) return core;
    return switch (protocol) {
      ProxyProtocol.hysteria2 || ProxyProtocol.tuic => CoreType.singbox,
      _ => CoreType.xray,
    };
  }

  /// Stable key used to de-duplicate servers on subscription refresh so test
  /// history survives updates.
  String get fingerprint =>
      '${protocol.name}|$address|$port|$credential|${param('type')}|${param('path')}|${param('serviceName')}';

  Server copyWith({
    String? id,
    String? subscriptionId,
    String? name,
    String? address,
    int? port,
    String? credential,
    String? secret,
    Map<String, String>? params,
    String? rawLink,
    String? countryCode,
    int? sortIndex,
    CoreType? core,
    bool? favorite,
  }) =>
      Server(
        id: id ?? this.id,
        subscriptionId: subscriptionId ?? this.subscriptionId,
        name: name ?? this.name,
        protocol: protocol,
        address: address ?? this.address,
        port: port ?? this.port,
        credential: credential ?? this.credential,
        secret: secret ?? this.secret,
        params: params ?? this.params,
        rawLink: rawLink ?? this.rawLink,
        countryCode: countryCode ?? this.countryCode,
        sortIndex: sortIndex ?? this.sortIndex,
        core: core ?? this.core,
        favorite: favorite ?? this.favorite,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'subscriptionId': subscriptionId,
        'name': name,
        'protocol': protocol.name,
        'address': address,
        'port': port,
        'credential': credential,
        'secret': secret,
        'params': params,
        'rawLink': rawLink,
        'countryCode': countryCode,
        'sortIndex': sortIndex,
        'core': core.name,
        'favorite': favorite,
      };

  factory Server.fromJson(Map<String, dynamic> j) => Server(
        id: j['id'] as String,
        subscriptionId: j['subscriptionId'] as String?,
        name: j['name'] as String,
        protocol: ProxyProtocol.values.byName(j['protocol'] as String),
        address: j['address'] as String,
        port: (j['port'] as num).toInt(),
        credential: j['credential'] as String,
        secret: j['secret'] as String?,
        params: Map<String, String>.from(j['params'] as Map? ?? const {}),
        rawLink: j['rawLink'] as String?,
        countryCode: j['countryCode'] as String?,
        sortIndex: (j['sortIndex'] as num?)?.toInt() ?? 0,
        core: CoreType.values.byName(j['core'] as String? ?? 'auto'),
        favorite: j['favorite'] as bool? ?? false,
      );

  String encode() => jsonEncode(toJson());
  static Server decode(String s) => Server.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) => other is Server && other.id == id;
  @override
  int get hashCode => id.hashCode;
}
