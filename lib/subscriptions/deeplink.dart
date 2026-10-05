import 'dart:convert';

import '../core/models/routing_profile.dart';
import '../core/util/b64.dart';
import '../core/util/ids.dart';
import 'link_parser.dart';

sealed class DeepLinkAction {
  const DeepLinkAction();
}

class AddSubscriptionAction extends DeepLinkAction {
  final String url;
  final String? name;
  const AddSubscriptionAction(this.url, {this.name});
}

class ImportLinksAction extends DeepLinkAction {
  final String text; // one or more share links
  const ImportLinksAction(this.text);
}

class AddRoutingAction extends DeepLinkAction {
  final RoutingProfile profile;
  final bool activate;
  const AddRoutingAction(this.profile, {this.activate = false});
}

/// Supported forms:
///   `kuputun://add/<url-encoded subscription url>[#name]`
///   `kuputun://import/<share link | base64 list>`
///   `kuputun://routing/add/<base64 json>` | `kuputun://routing/onadd/<base64 json>` (activate)
///   `happ://add/<url>`, `happ://routing/add|onadd/<base64>` (Happ compatibility)
///   plain `vless://...` links are treated as [ImportLinksAction].
class DeepLinkParser {
  /// Never throws: deeplinks arrive from the OS, other apps, QR codes and the
  /// clipboard, and a bad one must not break the import that triggered it.
  static DeepLinkAction? parse(String input) {
    try {
      return _parse(input);
    } on Object {
      return null;
    }
  }

  static DeepLinkAction? _parse(String input) {
    final s = input.trim();
    if (LinkParser.looksLikeLink(s)) return ImportLinksAction(s);
    final m = RegExp(r'^(kuputun|happ)://([a-z]+)/(.*)$', caseSensitive: false, dotAll: true).firstMatch(s);
    if (m == null) {
      if (s.startsWith('http://') || s.startsWith('https://')) return AddSubscriptionAction(s);
      return null;
    }
    final cmd = m.group(2)!.toLowerCase();
    final rest = m.group(3)!;
    switch (cmd) {
      case 'add':
        var url = rest;
        String? name;
        final h = url.indexOf('#');
        if (h >= 0) {
          name = safeDecodeComponent(url.substring(h + 1));
          url = url.substring(0, h);
        }
        url = safeDecodeComponent(url);
        if (!url.startsWith('http')) {
          final dec = tryDecodeBase64(url);
          if (dec != null && dec.startsWith('http')) url = dec;
        }
        return AddSubscriptionAction(url, name: name);
      case 'import':
        final raw = safeDecodeComponent(rest);
        final text = LinkParser.looksLikeLink(raw) ? raw : (tryDecodeBase64(raw) ?? raw);
        return ImportLinksAction(text);
      case 'routing':
        final i = rest.indexOf('/');
        if (i < 0) return null;
        final action = rest.substring(0, i).toLowerCase();
        final payload = tryDecodeBase64(safeDecodeComponent(rest.substring(i + 1)));
        if (payload == null) return null;
        final profile = RoutingImport.fromJson(payload);
        if (profile == null) return null;
        return AddRoutingAction(profile, activate: action == 'onadd');
    }
    return null;
  }

  static String buildAddSubscription(String url, {String? name}) =>
      'kuputun://add/${Uri.encodeComponent(url)}${name == null ? '' : '#${Uri.encodeComponent(name)}'}';

  static String buildRouting(RoutingProfile p) =>
      'kuputun://routing/add/${encodeBase64(p.encode(), urlSafe: true, padding: false)}';
}

/// Accepts our own RoutingProfile JSON and Happ routing JSON
/// (keys: Name, GlobalProxy, DirectSites, DirectIp, ProxySites, ProxyIp,
/// BlockSites, BlockIp, RemoteDNSType/Domain/IP, DomesticDNS..., Geoipurl, Geositeurl).
class RoutingImport {
  /// Never throws: a malformed payload (from a deeplink, a QR code or a
  /// provider's `routing` subscription header) must degrade to `null` instead
  /// of killing the import/subscription refresh that called us.
  static RoutingProfile? fromJson(String payload) {
    try {
      return _fromJson(payload);
    } on Object {
      return null;
    }
  }

  static RoutingProfile? _fromJson(String payload) {
    final dynamic j;
    try {
      j = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    if (j is! Map) return null;
    final map = Map<String, dynamic>.from(j);
    if (map.containsKey('rules') && map.containsKey('mode')) {
      final p = RoutingProfile.fromJson({...map, 'id': uuidV4(), 'builtIn': false});
      return p;
    }
    if (!map.containsKey('Name') && !map.containsKey('DirectSites') && !map.containsKey('ProxySites')) return null;

    // Happ sends these as arrays, but a string value must not throw.
    List<String> l(String k) {
      final v = map[k];
      if (v is List) return v.map((e) => '$e').toList();
      return v == null ? const [] : ['$v'];
    }
    final rules = <RoutingRule>[];
    void add(List<String> vals, RuleAction a, bool ip) {
      if (vals.isEmpty) return;
      final geo = vals.where((v) => v.startsWith(ip ? 'geoip:' : 'geosite:')).map((v) => v.split(':').last).toList();
      final plain = vals.where((v) => !v.startsWith('geoip:') && !v.startsWith('geosite:')).toList();
      if (geo.isNotEmpty) rules.add(RoutingRule(type: ip ? RuleMatchType.geoip : RuleMatchType.geosite, values: geo, action: a));
      if (plain.isNotEmpty) rules.add(RoutingRule(type: ip ? RuleMatchType.ip : RuleMatchType.domain, values: plain, action: a));
    }

    add(l('BlockSites'), RuleAction.block, false);
    add(l('BlockIp'), RuleAction.block, true);
    add(l('DirectSites'), RuleAction.direct, false);
    add(l('DirectIp'), RuleAction.direct, true);
    add(l('ProxySites'), RuleAction.proxy, false);
    add(l('ProxyIp'), RuleAction.proxy, true);

    DnsServer dns(String type, String? domain, String? ip) {
      final t = (type).toLowerCase();
      if (t == 'doh') return DnsServer(DnsProtocol.doh, domain ?? 'https://${ip ?? '1.1.1.1'}/dns-query');
      if (t == 'dot') return DnsServer(DnsProtocol.dot, domain ?? ip ?? '1.1.1.1');
      return DnsServer(DnsProtocol.udp, ip ?? '1.1.1.1');
    }

    final globalProxy = map['GlobalProxy'].toString().toLowerCase() == 'true';
    final base = const RoutingProfile(id: '', name: '');
    return RoutingProfile(
      id: uuidV4(),
      name: (map['Name'] ?? 'Imported').toString(),
      mode: RoutingMode.rule,
      rules: rules,
      defaultAction: globalProxy ? RuleAction.proxy : RuleAction.direct,
      dns: DnsSettings(
        remote: dns(map['RemoteDNSType']?.toString() ?? 'DoH', map['RemoteDNSDomain']?.toString(), map['RemoteDNSIP']?.toString()),
        direct: dns(map['DomesticDNSType']?.toString() ?? 'DoH', map['DomesticDNSDomain']?.toString(), map['DomesticDNSIP']?.toString()),
        fakeIp: map['FakeDNS'].toString().toLowerCase() == 'true',
      ),
      geoipUrl: map['Geoipurl']?.toString() ?? base.geoipUrl,
      geositeUrl: map['Geositeurl']?.toString() ?? base.geositeUrl,
    );
  }
}
