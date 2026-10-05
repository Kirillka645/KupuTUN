import 'dart:convert';

import '../core/models/server.dart';
import '../core/models/subscription.dart';
import '../core/util/b64.dart';
import '../core/util/country.dart';
import '../core/util/ids.dart';
import 'link_parser.dart';

/// Result of parsing a subscription response.
class ParsedSubscription {
  final List<Server> servers;
  final Map<String, String> meta; // merged headers + body comments, lower-case keys
  final List<String> errors;
  const ParsedSubscription(this.servers, this.meta, this.errors);

  /// Applies Happ-compatible metadata on top of an existing [Subscription].
  Subscription applyTo(Subscription sub, DateTime now) {
    String? m(String k) => meta[k];
    final interval = int.tryParse(m('profile-update-interval') ?? '');
    final known = <String>{
      'profile-title', 'profile-update-interval', 'subscription-userinfo', 'support-url', 'profile-web-page-url',
      'announce', 'routing-enable', 'routing', 'ping-type', 'subscriptions-sort-type', 'fragmentation-enable',
      'fragmentation-packets', 'fragmentation-length', 'fragmentation-interval', 'fragmentation-maxsplit',
      'noises-enable', 'noises-type', 'noises-packet', 'noises-delay',
    };
    FragmentSettings? frag;
    if (m('fragmentation-enable') != null) {
      frag = FragmentSettings(
        enabled: _truthy(m('fragmentation-enable')),
        packets: m('fragmentation-packets') ?? 'tlshello',
        length: m('fragmentation-length') ?? '100-200',
        interval: m('fragmentation-interval') ?? '10-20',
        maxSplit: int.tryParse(m('fragmentation-maxsplit') ?? '') ?? 0,
      );
    }
    NoiseSettings? noises;
    if (m('noises-enable') != null) {
      noises = NoiseSettings(
        enabled: _truthy(m('noises-enable')),
        type: m('noises-type') ?? 'rand',
        packet: m('noises-packet') ?? '10-20',
        delay: m('noises-delay') ?? '10-16',
      );
    }
    final sort = switch ((m('subscriptions-sort-type') ?? '').toLowerCase()) {
      'ping' => ProviderSortType.ping,
      'name' || 'alphabet' => ProviderSortType.name,
      _ => sub.sortType,
    };
    return sub.copyWith(
      title: m('profile-title') != null && m('profile-title')!.isNotEmpty ? m('profile-title') : null,
      updateInterval: interval != null && interval > 0 ? Duration(hours: interval) : null,
      lastUpdated: now,
      userInfo: SubscriptionUserInfo.parse(m('subscription-userinfo')),
      supportUrl: m('support-url'),
      webPageUrl: m('profile-web-page-url'),
      announce: m('announce'),
      routingEnabled: m('routing-enable') == null ? null : _truthy(m('routing-enable')),
      routingDeeplink: m('routing'),
      pingType: m('ping-type'),
      sortType: sort,
      fragment: frag,
      noises: noises,
      extra: {for (final e in meta.entries) if (!known.contains(e.key)) e.key: e.value},
    );
  }

  static bool _truthy(String? v) => const {'1', 'true', 'yes', 'on', 'enable', 'enabled'}.contains(v?.trim().toLowerCase());
}

/// Parses subscription bodies in every format seen in the wild:
/// base64 list, plain list, Xray JSON (object or array), sing-box JSON.
///
/// Decision: metadata from headers wins over `#key: value` body comments,
/// because headers are what Happ treats as authoritative.
class SubscriptionParser {
  static const metaValueBase64Keys = {'profile-title', 'announce'};

  static ParsedSubscription parse(String body, {Map<String, String> headers = const {}, String? subscriptionId}) {
    final errors = <String>[];
    var text = body.trim();
    final decoded = tryDecodeBase64(text);
    if (decoded != null && (decoded.contains('://') || decoded.trimLeft().startsWith('{') || decoded.trimLeft().startsWith('['))) {
      text = decoded.trim();
    }

    final meta = <String, String>{};
    // 1. body comments: "#profile-title: base64:..."
    for (final line in const LineSplitter().convert(text)) {
      final m = RegExp(r'^\s*(?:#|//)\s*([A-Za-z0-9_-]+)\s*:\s*(.*)$').firstMatch(line);
      if (m != null) meta[m.group(1)!.toLowerCase()] = m.group(2)!.trim();
    }
    // 2. headers override comments
    headers.forEach((k, v) => meta[k.toLowerCase()] = v);
    for (final k in metaValueBase64Keys) {
      if (meta[k] != null) meta[k] = decodeMaybeBase64Value(meta[k]!);
    }

    List<Server> servers;
    final t = text.trimLeft();
    if (t.startsWith('{') || t.startsWith('[')) {
      servers = JsonConfigImporter.import(text, subscriptionId: subscriptionId, errors: errors);
    } else {
      servers = LinkParser.parseMany(text, subscriptionId: subscriptionId, errors: errors);
    }
    return ParsedSubscription(servers, meta, errors);
  }
}

/// Imports full Xray / sing-box JSON configs.
///
/// Decision: instead of lossy outbound->link conversion, the original JSON is
/// stored in `params['json']`; the config builder re-uses its outbounds and
/// only replaces inbounds, so every exotic option keeps working.
class JsonConfigImporter {
  static List<Server> import(String text, {String? subscriptionId, List<String>? errors}) {
    final dynamic root;
    try {
      root = jsonDecode(text);
    } on FormatException catch (e) {
      errors?.add('json: $e');
      return const [];
    }
    final configs = root is List ? root : [root];
    final out = <Server>[];
    for (var i = 0; i < configs.length; i++) {
      final c = configs[i];
      if (c is! Map) continue;
      final cfg = Map<String, dynamic>.from(c);
      final outbounds = cfg['outbounds'] is List
          ? (cfg['outbounds'] as List).whereType<Map<dynamic, dynamic>>().toList()
          : const <Map<dynamic, dynamic>>[];
      if (outbounds.isEmpty) {
        errors?.add('config #$i has no outbounds');
        continue;
      }
      // sing-box uses "type", Xray uses "protocol"
      final isSingbox = outbounds.first.containsKey('type') && !outbounds.first.containsKey('protocol');
      final first = outbounds.firstWhere(
        (o) => !const {'freedom', 'blackhole', 'dns', 'direct', 'block', 'selector', 'urltest'}
            .contains((o['protocol'] ?? o['type']).toString()),
        orElse: () => outbounds.first,
      );
      final protoName = (first['protocol'] ?? first['type']).toString();
      final proto = ProxyProtocol.fromScheme(protoName == 'shadowsocks' ? 'ss' : protoName) ?? ProxyProtocol.vless;
      final addr = _extractAddress(first, isSingbox);
      final name = (cfg['remarks'] ?? first['tag'] ?? '${protoName.toUpperCase()} ${addr.$1}').toString();
      out.add(Server(
        id: uuidV4(),
        subscriptionId: subscriptionId,
        name: name,
        protocol: proto,
        address: addr.$1,
        port: addr.$2,
        credential: '',
        params: {'json': jsonEncode(cfg), 'jsonCore': isSingbox ? 'singbox' : 'xray'},
        core: isSingbox ? CoreType.singbox : CoreType.xray,
        sortIndex: i,
        countryCode: CountryDetector.detect(name),
      ));
    }
    return out;
  }

  /// Ports arrive as numbers or strings depending on the exporter; a wrong type
  /// used to abort the whole subscription import with a raw TypeError.
  static int _port(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static (String, int) _extractAddress(Map<dynamic, dynamic> o, bool singbox) {
    if (singbox) {
      return ((o['server'] ?? '').toString(), _port(o['server_port']));
    }
    final s = o['settings'];
    if (s is Map) {
      final vnext = s['vnext'] ?? s['servers'];
      if (vnext is List && vnext.isNotEmpty && vnext.first is Map) {
        final v = vnext.first as Map;
        return ((v['address'] ?? '').toString(), _port(v['port']));
      }
      if (s['peers'] is List && (s['peers'] as List).isNotEmpty) {
        final ep = ((s['peers'] as List).first as Map)['endpoint']?.toString() ?? '';
        final i = ep.lastIndexOf(':');
        if (i > 0) return (ep.substring(0, i).replaceAll(RegExp(r'[\[\]]'), ''), int.tryParse(ep.substring(i + 1)) ?? 0);
      }
      if (s['address'] != null) return (s['address'].toString(), _port(s['port']));
    }
    return ('', 0);
  }
}
