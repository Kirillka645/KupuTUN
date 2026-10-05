import 'dart:convert';

enum RoutingMode { global, rule, direct }

enum RuleAction { proxy, direct, block }

enum RuleMatchType { domain, domainSuffix, domainKeyword, regex, geosite, ip, geoip, process, package, port, protocol }

/// Note: every `fromJson` below is deliberately tolerant. Routing profiles also
/// arrive from deeplinks (`kuputun://routing/add/…`) and from a provider's
/// `routing` subscription header, and one unknown enum name or wrongly typed
/// field used to abort the whole import with a raw TypeError/ArgumentError.
class RoutingRule {
  final RuleMatchType type;
  final List<String> values;
  final RuleAction action;
  final bool enabled;

  const RoutingRule({required this.type, required this.values, required this.action, this.enabled = true});

  Map<String, dynamic> toJson() => {'type': type.name, 'values': values, 'action': action.name, 'enabled': enabled};
  factory RoutingRule.fromJson(Map<String, dynamic> j) => RoutingRule(
        type: RuleMatchType.values.asNameMap()[j['type']] ?? RuleMatchType.domain,
        values: j['values'] is List ? (j['values'] as List).map((e) => '$e').toList() : const [],
        action: RuleAction.values.asNameMap()[j['action']] ?? RuleAction.proxy,
        enabled: j['enabled'] as bool? ?? true,
      );
}

enum DnsProtocol { udp, doh, dot, doq }

class DnsServer {
  static const _defaultRemote = DnsServer(DnsProtocol.doh, 'https://1.1.1.1/dns-query');

  final DnsProtocol protocol;
  final String address; // "1.1.1.1", "https://1.1.1.1/dns-query", "dns.google"
  const DnsServer(this.protocol, this.address);

  /// Xray/sing-box URL form.
  String get url => switch (protocol) {
        DnsProtocol.udp => address,
        DnsProtocol.doh => address.startsWith('https://') ? address : 'https://$address/dns-query',
        DnsProtocol.dot => 'tls://$address',
        DnsProtocol.doq => 'quic://$address',
      };

  Map<String, dynamic> toJson() => {'protocol': protocol.name, 'address': address};
  factory DnsServer.fromJson(Map<String, dynamic> j) {
    final address = j['address'];
    return DnsServer(
      DnsProtocol.values.asNameMap()[j['protocol']] ?? DnsProtocol.doh,
      address is String && address.isNotEmpty ? address : _defaultRemote.address,
    );
  }
}

class DnsSettings {
  final DnsServer remote; // used for proxied domains (resolved through tunnel)
  final DnsServer direct; // used for direct domains
  final bool fakeIp;
  final bool blockLeaks; // force all port-53 traffic into the DNS module
  final List<String> hosts; // "domain=ip"

  const DnsSettings({
    this.remote = const DnsServer(DnsProtocol.doh, 'https://1.1.1.1/dns-query'),
    this.direct = const DnsServer(DnsProtocol.doh, 'https://77.88.8.8/dns-query'),
    this.fakeIp = false,
    this.blockLeaks = true,
    this.hosts = const [],
  });

  Map<String, dynamic> toJson() => {
        'remote': remote.toJson(),
        'direct': direct.toJson(),
        'fakeIp': fakeIp,
        'blockLeaks': blockLeaks,
        'hosts': hosts,
      };
  factory DnsSettings.fromJson(Map<String, dynamic> j) => DnsSettings(
        remote: _server(j['remote'], const DnsSettings().remote),
        direct: _server(j['direct'], const DnsSettings().direct),
        fakeIp: j['fakeIp'] as bool? ?? false,
        blockLeaks: j['blockLeaks'] as bool? ?? true,
        hosts: j['hosts'] is List ? (j['hosts'] as List).map((e) => '$e').toList() : const [],
      );

  static DnsServer _server(Object? v, DnsServer fallback) =>
      v is Map ? DnsServer.fromJson(Map<String, dynamic>.from(v)) : fallback;
}

class RoutingProfile {
  final String id;
  final String name;
  final RoutingMode mode;
  final List<RoutingRule> rules;
  final RuleAction defaultAction;
  final DnsSettings dns;
  final String geoipUrl;
  final String geositeUrl;
  final bool builtIn;

  const RoutingProfile({
    required this.id,
    required this.name,
    this.mode = RoutingMode.rule,
    this.rules = const [],
    this.defaultAction = RuleAction.proxy,
    this.dns = const DnsSettings(),
    this.geoipUrl = 'https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat',
    this.geositeUrl = 'https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat',
    this.builtIn = false,
  });

  RoutingProfile copyWith({String? name, RoutingMode? mode, List<RoutingRule>? rules, RuleAction? defaultAction, DnsSettings? dns}) =>
      RoutingProfile(
        id: id,
        name: name ?? this.name,
        mode: mode ?? this.mode,
        rules: rules ?? this.rules,
        defaultAction: defaultAction ?? this.defaultAction,
        dns: dns ?? this.dns,
        geoipUrl: geoipUrl,
        geositeUrl: geositeUrl,
        builtIn: builtIn,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mode': mode.name,
        'rules': rules.map((e) => e.toJson()).toList(),
        'defaultAction': defaultAction.name,
        'dns': dns.toJson(),
        'geoipUrl': geoipUrl,
        'geositeUrl': geositeUrl,
        'builtIn': builtIn,
      };

  factory RoutingProfile.fromJson(Map<String, dynamic> j) {
    const defaults = RoutingProfile(id: '', name: '');
    return RoutingProfile(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      mode: RoutingMode.values.asNameMap()[j['mode']] ?? RoutingMode.rule,
      rules: j['rules'] is List
          ? (j['rules'] as List)
              .whereType<Map<String, dynamic>>()
              .map(RoutingRule.fromJson)
              .toList()
          : const [],
      defaultAction: RuleAction.values.asNameMap()[j['defaultAction']] ?? RuleAction.proxy,
      dns: j['dns'] is Map ? DnsSettings.fromJson(Map<String, dynamic>.from(j['dns'] as Map)) : const DnsSettings(),
      geoipUrl: j['geoipUrl'] as String? ?? defaults.geoipUrl,
      geositeUrl: j['geositeUrl'] as String? ?? defaults.geositeUrl,
      builtIn: j['builtIn'] as bool? ?? false,
    );
  }

  String encode() => jsonEncode(toJson());
}
