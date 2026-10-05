import '../core/models/routing_profile.dart';

/// Built-in routing profiles.
class RoutingPresets {
  static RoutingProfile global() => const RoutingProfile(id: 'builtin-global', name: 'Global', mode: RoutingMode.global, builtIn: true);

  static RoutingProfile direct() => const RoutingProfile(id: 'builtin-direct', name: 'Direct', mode: RoutingMode.direct, builtIn: true);

  /// "Россия direct, остальное через прокси".
  /// Decision: geosite:category-ru + geoip:ru cover Russian services and
  /// hosting; explicit TLD suffixes catch domains missing from lists; ads and
  /// trackers are blocked; well-known blocked services are forced to proxy
  /// even if they resolve to a Russian IP (CDN edge nodes).
  static RoutingProfile russiaDirect() => const RoutingProfile(
        id: 'builtin-ru',
        name: 'Россия direct',
        mode: RoutingMode.rule,
        builtIn: true,
        defaultAction: RuleAction.proxy,
        rules: [
          RoutingRule(type: RuleMatchType.geosite, values: ['category-ads-all'], action: RuleAction.block),
          RoutingRule(
            type: RuleMatchType.geosite,
            values: ['youtube', 'telegram', 'instagram', 'facebook', 'twitter', 'openai', 'discord', 'netflix', 'ru-blocked'],
            action: RuleAction.proxy,
          ),
          RoutingRule(type: RuleMatchType.domainSuffix, values: ['ru', 'su', 'xn--p1ai', 'xn--d1acj3b', 'moscow', 'by', 'kz'], action: RuleAction.direct),
          RoutingRule(type: RuleMatchType.geosite, values: ['category-ru', 'yandex', 'vk', 'mailru', 'private'], action: RuleAction.direct),
          RoutingRule(type: RuleMatchType.geoip, values: ['ru', 'private'], action: RuleAction.direct),
        ],
        dns: DnsSettings(
          remote: DnsServer(DnsProtocol.doh, 'https://1.1.1.1/dns-query'),
          direct: DnsServer(DnsProtocol.doh, 'https://77.88.8.8/dns-query'),
          blockLeaks: true,
        ),
      );

  static List<RoutingProfile> all() => [russiaDirect(), global(), direct()];
}

/// Validates user-written rules before saving (editor shows the messages).
class RuleValidator {
  static final _domain = RegExp(r'^(?=.{1,253}$)(?!-)[A-Za-z0-9\-_\.\*]+(?<!-)$');
  static final _cidr4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?:/(\d{1,2}))?$');
  static final _cidr6 = RegExp(r'^[0-9a-fA-F:]+(?:/(\d{1,3}))?$');
  static final _geo = RegExp(r'^[a-z0-9\-!@_]+$');

  /// Returns a list of human-readable errors (empty = valid).
  static List<String> validate(RoutingRule r) {
    final errs = <String>[];
    if (r.values.isEmpty) errs.add('Правило пустое');
    for (final v in r.values) {
      final ok = switch (r.type) {
        RuleMatchType.domain || RuleMatchType.domainSuffix => _domain.hasMatch(v.startsWith('.') ? v.substring(1) : v),
        RuleMatchType.domainKeyword => v.isNotEmpty && !v.contains(' '),
        RuleMatchType.regex => _isRegex(v),
        RuleMatchType.geosite || RuleMatchType.geoip => _geo.hasMatch(v),
        RuleMatchType.ip => _isIp(v),
        RuleMatchType.port => RegExp(r'^\d{1,5}(-\d{1,5})?$').hasMatch(v) && v.split('-').every((p) => int.parse(p) <= 65535),
        RuleMatchType.protocol => const {'http', 'tls', 'quic', 'bittorrent', 'dns', 'stun'}.contains(v),
        RuleMatchType.process || RuleMatchType.package => v.isNotEmpty,
      };
      if (!ok) errs.add('Неверное значение "$v" для ${r.type.name}');
    }
    return errs;
  }

  static bool _isRegex(String v) {
    try {
      RegExp(v);
      return true;
    } on FormatException {
      return false;
    }
  }

  static bool _isIp(String v) {
    final m4 = _cidr4.firstMatch(v);
    if (m4 != null) {
      for (var i = 1; i <= 4; i++) {
        if (int.parse(m4.group(i)!) > 255) return false;
      }
      final p = m4.group(5);
      return p == null || int.parse(p) <= 32;
    }
    final m6 = _cidr6.firstMatch(v);
    if (m6 != null && v.contains(':')) {
      final p = m6.group(1);
      return p == null || int.parse(p) <= 128;
    }
    return false;
  }
}
