import 'dart:convert';

import '../models/routing_profile.dart';
import '../models/server.dart';
import 'core_settings.dart';
import 'xray_config_builder.dart' show ConfigBuildException;

/// Builds sing-box (>= 1.12) JSON configs.
///
/// Decision: geosite/geoip are expressed as remote binary rule-sets (.srs),
/// because sing-box 1.12 removed the legacy geo databases. The runetfreedom
/// build is used since it ships the same lists as the Xray .dat files
/// (including ru-blocked), so both cores route identically. Rule-sets are cached
/// by sing-box itself (`experimental.cache_file`).
class SingboxConfigBuilder {
  final CoreSettings settings;
  SingboxConfigBuilder(this.settings);

  static const proxyTag = 'proxy';
  static const directTag = 'direct';

  Map<String, dynamic> buildMain(Server s, RoutingProfile routing, {bool tun = false}) {
    if (s.params.containsKey('json') && s.param('jsonCore') == 'singbox') {
      final cfg = Map<String, dynamic>.from(jsonDecode(s.param('json')) as Map);
      cfg['inbounds'] = _inbounds(tun);
      return cfg;
    }
    final ob = outbound(s, proxyTag);
    final isEndpoint = ob.remove('_endpoint') == true;
    final ruleSets = <String, Map<String, dynamic>>{};
    return {
      'log': {'level': _logLevel(), 'timestamp': true, if (settings.logPath != null) 'output': settings.logPath},
      'dns': _dns(routing, ruleSets),
      'inbounds': _inbounds(tun),
      if (isEndpoint) 'endpoints': [ob],
      'outbounds': [
        if (!isEndpoint) ob,
        {'type': 'direct', 'tag': directTag},
      ],
      'route': _route(routing, ruleSets),
      'experimental': {
        'cache_file': {'enabled': true, 'store_fakeip': routing.dns.fakeIp},
      },
    };
  }

  Map<String, dynamic> buildBatchTest(List<Server> servers, List<int> ports) {
    final outbounds = <Map<String, dynamic>>[];
    final endpoints = <Map<String, dynamic>>[];
    for (var i = 0; i < servers.length; i++) {
      final o = outbound(servers[i], 'out-$i');
      (o.remove('_endpoint') == true ? endpoints : outbounds).add(o);
    }
    return {
      'log': {'disabled': true},
      'dns': {
        'servers': [
          {'type': 'https', 'tag': 'cf', 'server': '1.1.1.1'}
        ],
        'strategy': 'ipv4_only',
      },
      'inbounds': [
        for (var i = 0; i < servers.length; i++)
          {'type': 'http', 'tag': 'in-$i', 'listen': '127.0.0.1', 'listen_port': ports[i]}
      ],
      if (endpoints.isNotEmpty) 'endpoints': endpoints,
      'outbounds': [...outbounds, {'type': 'direct', 'tag': directTag}],
      'route': {
        'rules': [
          for (var i = 0; i < servers.length; i++) {'inbound': ['in-$i'], 'action': 'route', 'outbound': 'out-$i'}
        ],
        'default_domain_resolver': 'cf',
      },
    };
  }

  Map<String, dynamic> outbound(Server s, String tag) {
    final tls = _tls(s);
    final transport = _transport(s);
    switch (s.protocol) {
      case ProxyProtocol.vless:
        return {
          'type': 'vless',
          'tag': tag,
          'server': s.address,
          'server_port': s.port,
          'uuid': s.credential,
          if (s.param('flow').isNotEmpty) 'flow': s.param('flow'),
          if (tls != null) 'tls': tls,
          if (transport != null) 'transport': transport,
          'packet_encoding': 'xudp',
          ..._mux(s),
        };
      case ProxyProtocol.vmess:
        return {
          'type': 'vmess',
          'tag': tag,
          'server': s.address,
          'server_port': s.port,
          'uuid': s.credential,
          'alter_id': int.tryParse(s.param('aid', '0')) ?? 0,
          'security': s.param('scy', 'auto'),
          if (tls != null) 'tls': tls,
          if (transport != null) 'transport': transport,
          ..._mux(s),
        };
      case ProxyProtocol.trojan:
        return {
          'type': 'trojan',
          'tag': tag,
          'server': s.address,
          'server_port': s.port,
          'password': s.credential,
          'tls': tls ?? {'enabled': true, 'server_name': s.param('sni', s.address)},
          if (transport != null) 'transport': transport,
          ..._mux(s),
        };
      case ProxyProtocol.shadowsocks:
        final plugin = s.param('plugin');
        String? pluginName, pluginOpts;
        if (plugin.isNotEmpty) {
          final i = plugin.indexOf(';');
          pluginName = i < 0 ? plugin : plugin.substring(0, i);
          pluginOpts = i < 0 ? '' : plugin.substring(i + 1);
          if (pluginName == 'simple-obfs') pluginName = 'obfs-local';
        }
        return {
          'type': 'shadowsocks',
          'tag': tag,
          'server': s.address,
          'server_port': s.port,
          'method': s.secret ?? 'chacha20-ietf-poly1305',
          'password': s.credential,
          if (pluginName != null) 'plugin': pluginName,
          if (pluginOpts != null) 'plugin_opts': pluginOpts,
          'udp_over_tcp': false,
          ..._mux(s),
        };
      case ProxyProtocol.socks:
        return {
          'type': 'socks',
          'tag': tag,
          'server': s.address,
          'server_port': s.port,
          'version': '5',
          if (s.credential.isNotEmpty) 'username': s.credential,
          if (s.secret != null) 'password': s.secret,
        };
      case ProxyProtocol.hysteria2:
        final ports = s.param('mport');
        return {
          'type': 'hysteria2',
          'tag': tag,
          'server': s.address,
          'server_port': s.port,
          if (ports.isNotEmpty) 'server_ports': ports.split(',').map((p) => p.replaceAll('-', ':')).toList(),
          'password': s.credential,
          if (s.param('obfs').isNotEmpty)
            'obfs': {'type': s.param('obfs'), 'password': s.param('obfs-password')},
          if (s.param('upmbps').isNotEmpty) 'up_mbps': int.tryParse(s.param('upmbps')) ?? 0,
          if (s.param('downmbps').isNotEmpty) 'down_mbps': int.tryParse(s.param('downmbps')) ?? 0,
          'tls': {
            'enabled': true,
            'server_name': s.param('sni', s.address),
            'insecure': _truthy(s.param('insecure', s.param('allowInsecure'))),
            'alpn': s.param('alpn', 'h3').split(','),
          },
        };
      case ProxyProtocol.tuic:
        return {
          'type': 'tuic',
          'tag': tag,
          'server': s.address,
          'server_port': s.port,
          'uuid': s.credential,
          'password': s.secret ?? '',
          'congestion_control': s.param('congestion_control', 'bbr'),
          'udp_relay_mode': s.param('udp_relay_mode', 'native'),
          'zero_rtt_handshake': false,
          'heartbeat': '10s',
          'tls': {
            'enabled': true,
            'server_name': s.param('sni', s.address),
            'insecure': _truthy(s.param('allow_insecure', s.param('insecure'))),
            'alpn': s.param('alpn', 'h3').split(','),
            if (s.param('disable_sni') == '1') 'disable_sni': true,
          },
        };
      case ProxyProtocol.wireguard:
        // sing-box >= 1.11: WireGuard is an endpoint, not an outbound.
        return {
          '_endpoint': true,
          'type': 'wireguard',
          'tag': tag,
          'address': s.param('address', '10.0.0.2/32').split(',').map((e) => e.trim()).toList(),
          'private_key': s.credential,
          'mtu': int.tryParse(s.param('mtu', '1420')) ?? 1420,
          'peers': [
            {
              'address': s.address,
              'port': s.port,
              'public_key': s.param('publickey', s.param('publicKey')),
              if (s.param('presharedkey').isNotEmpty) 'pre_shared_key': s.param('presharedkey'),
              'allowed_ips': ['0.0.0.0/0', '::/0'],
              if (s.param('reserved').isNotEmpty)
                'reserved': s.param('reserved').split(',').map((e) => int.tryParse(e.trim()) ?? 0).toList(),
            }
          ],
        };
    }
  }

  Map<String, dynamic>? _tls(Server s) {
    final sec = s.security;
    if (sec != 'tls' && sec != 'reality' && sec != 'xtls') return null;
    final host = s.param('host');
    final fp = settings.fingerprintOverride ?? s.param('fp', 'chrome');
    return {
      'enabled': true,
      'server_name': s.param('sni', s.param('peer', host.isNotEmpty ? host.split(',').first : s.address)),
      'insecure': _truthy(s.param('allowInsecure', s.param('insecure'))),
      if (s.param('alpn').isNotEmpty) 'alpn': s.param('alpn').split(','),
      'utls': {'enabled': true, 'fingerprint': fp == 'randomized' ? 'randomized' : fp},
      if (sec == 'reality') 'reality': {'enabled': true, 'public_key': s.param('pbk'), 'short_id': s.param('sid')},
      if (s.param('ech').isNotEmpty) 'ech': {'enabled': true, 'config': [s.param('ech')]},
      if (settings.fragment.enabled && sec == 'tls') 'fragment': true,
    };
  }

  Map<String, dynamic>? _transport(Server s) {
    final host = s.param('host');
    switch (s.transport) {
      case 'ws':
        final path = s.param('path', '/');
        final ed = RegExp(r'[?&]ed=(\d+)').firstMatch(path);
        return {
          'type': 'ws',
          'path': path.split('?').first,
          if (host.isNotEmpty) 'headers': {'Host': host},
          if (ed != null) 'max_early_data': int.parse(ed.group(1)!),
          if (ed != null) 'early_data_header_name': 'Sec-WebSocket-Protocol',
        };
      case 'grpc':
        return {'type': 'grpc', 'service_name': s.param('serviceName', s.param('path'))};
      case 'httpupgrade':
        return {'type': 'httpupgrade', 'path': s.param('path', '/'), if (host.isNotEmpty) 'host': host};
      case 'h2':
      case 'http':
        return {'type': 'http', 'path': s.param('path', '/'), if (host.isNotEmpty) 'host': host.split(',')};
      case 'xhttp':
      case 'splithttp':
        throw ConfigBuildException('XHTTP is only supported by the Xray core');
      case 'tcp':
      case 'raw':
        if (s.param('headerType') == 'http') {
          return {'type': 'http', 'method': 'GET', 'path': s.param('path', '/'), if (host.isNotEmpty) 'host': host.split(',')};
        }
        return null;
      case 'kcp':
        throw ConfigBuildException('mKCP is only supported by the Xray core');
    }
    return null;
  }

  Map<String, dynamic> _mux(Server s) =>
      settings.mux && s.param('flow').isEmpty && s.security != 'reality'
          ? {'multiplex': {'enabled': true, 'protocol': 'h2mux', 'max_connections': 4, 'padding': true}}
          : const {};

  List<Map<String, dynamic>> _inbounds(bool tun) => [
        {'type': 'mixed', 'tag': 'mixed-in', 'listen': settings.listen, 'listen_port': settings.socksPort},
        {'type': 'http', 'tag': 'http-in', 'listen': settings.listen, 'listen_port': settings.httpPort},
        if (tun) _tunInbound(const []),
      ];

  /// strict_route = kill switch: traffic can't bypass the TUN while it exists.
  /// IPv6 still gets an address so v6 packets are captured (and rejected by
  /// the route) instead of leaking past the tunnel.
  Map<String, dynamic> _tunInbound(List<String> excludeIps) => {
        'type': 'tun',
        'tag': 'tun-in',
        'interface_name': 'kuputun0',
        'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
        'mtu': settings.tunMtu,
        'auto_route': true,
        'strict_route': settings.killSwitch,
        'stack': 'mixed',
        if (excludeIps.isNotEmpty)
          'route_exclude_address': excludeIps.map((ip) => ip.contains('/') ? ip : (ip.contains(':') ? '$ip/128' : '$ip/32')).toList(),
      };

  /// Desktop hybrid mode: Xray is the proxy core (socks on [socksPort]) and
  /// sing-box owns the TUN + split routing. Server IPs are excluded from the
  /// TUN routes so Xray's own outbound connections don't loop back.
  Map<String, dynamic> buildTunWrapper(int socksPort, RoutingProfile routing, List<String> excludeIps) {
    final ruleSets = <String, Map<String, dynamic>>{};
    return {
      'log': {'level': _logLevel(), 'timestamp': true, if (settings.logPath != null) 'output': settings.logPath},
      'dns': _dns(routing, ruleSets),
      'inbounds': [_tunInbound(excludeIps)],
      'outbounds': [
        {'type': 'socks', 'tag': proxyTag, 'server': '127.0.0.1', 'server_port': socksPort, 'version': '5', 'udp_over_tcp': false},
        {'type': 'direct', 'tag': directTag},
      ],
      'route': _route(routing, ruleSets),
      'experimental': {
        'cache_file': {'enabled': true, 'store_fakeip': routing.dns.fakeIp},
      },
    };
  }

  Map<String, dynamic> _dnsServer(DnsServer d, String tag, {String? detour}) {
    final base = <String, dynamic>{'tag': tag, if (detour != null) 'detour': detour};
    switch (d.protocol) {
      case DnsProtocol.udp:
        return {...base, 'type': 'udp', 'server': d.address};
      case DnsProtocol.doh:
        final u = Uri.parse(d.url);
        return {...base, 'type': 'https', 'server': u.host, if (u.path.isNotEmpty && u.path != '/dns-query') 'path': u.path};
      case DnsProtocol.dot:
        return {...base, 'type': 'tls', 'server': d.address};
      case DnsProtocol.doq:
        return {...base, 'type': 'quic', 'server': d.address};
    }
  }

  Map<String, dynamic> _dns(RoutingProfile r, Map<String, Map<String, dynamic>> ruleSets) {
    final directMatchers = <Map<String, dynamic>>[];
    for (final rule in r.rules.where((e) => e.enabled && e.action == RuleAction.direct)) {
      final m = _matcher(rule, ruleSets, dnsOnly: true);
      if (m != null) directMatchers.add(m);
    }
    return {
      'servers': [
        _dnsServer(r.dns.remote, 'remote-dns', detour: proxyTag),
        _dnsServer(r.dns.direct, 'direct-dns'),
        if (r.dns.fakeIp) {'type': 'fakeip', 'tag': 'fakeip', 'inet4_range': '198.18.0.0/15'},
      ],
      'rules': [
        for (final m in directMatchers) {...m, 'action': 'route', 'server': 'direct-dns'},
        if (r.dns.fakeIp) {'query_type': ['A', 'AAAA'], 'action': 'route', 'server': 'fakeip'},
      ],
      'final': r.mode == RoutingMode.direct ? 'direct-dns' : 'remote-dns',
      'strategy': settings.blockIpv6 ? 'ipv4_only' : 'prefer_ipv4',
      'independent_cache': true,
    };
  }

  Map<String, dynamic>? _matcher(RoutingRule rule, Map<String, Map<String, dynamic>> ruleSets, {bool dnsOnly = false}) {
    String rs(String kind, String name) {
      final tag = '$kind-$name';
      ruleSets[tag] = {
        'type': 'remote',
        'tag': tag,
        'format': 'binary',
        'url': kind == 'geosite'
            ? 'https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-$name.srs'
            : 'https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geoip/geoip-$name.srs',
        'download_detour': directTag,
        'update_interval': '72h',
      };
      return tag;
    }

    switch (rule.type) {
      case RuleMatchType.domain:
        return {'domain': rule.values};
      case RuleMatchType.domainSuffix:
        return {'domain_suffix': rule.values};
      case RuleMatchType.domainKeyword:
        return {'domain_keyword': rule.values};
      case RuleMatchType.regex:
        return {'domain_regex': rule.values};
      case RuleMatchType.geosite:
        return {'rule_set': rule.values.map((v) => rs('geosite', v)).toList()};
      case RuleMatchType.geoip:
        if (dnsOnly) return null;
        return {'rule_set': rule.values.map((v) => rs('geoip', v)).toList()};
      case RuleMatchType.ip:
        if (dnsOnly) return null;
        return {'ip_cidr': rule.values};
      case RuleMatchType.process:
        if (dnsOnly) return null;
        return {'process_name': rule.values};
      case RuleMatchType.package:
        if (dnsOnly) return null;
        return {'package_name': rule.values};
      case RuleMatchType.port:
        if (dnsOnly) return null;
        return {'port': rule.values.map((e) => int.tryParse(e)).whereType<int>().toList()};
      case RuleMatchType.protocol:
        if (dnsOnly) return null;
        return {'protocol': rule.values};
    }
  }

  Map<String, dynamic> _route(RoutingProfile r, Map<String, Map<String, dynamic>> ruleSets) {
    Map<String, dynamic> act(RuleAction a) => switch (a) {
          RuleAction.proxy => {'action': 'route', 'outbound': proxyTag},
          RuleAction.direct => {'action': 'route', 'outbound': directTag},
          RuleAction.block => {'action': 'reject'},
        };
    final rules = <Map<String, dynamic>>[
      {'action': 'sniff'},
      if (r.dns.blockLeaks) {'protocol': 'dns', 'action': 'hijack-dns'} else {'port': [53], 'action': 'hijack-dns'},
      {'ip_is_private': true, 'action': 'route', 'outbound': directTag},
      if (settings.blockIpv6) {'ip_version': 6, 'action': 'reject'},
    ];
    String finalTag;
    switch (r.mode) {
      case RoutingMode.global:
        finalTag = proxyTag;
      case RoutingMode.direct:
        finalTag = directTag;
      case RoutingMode.rule:
        for (final rule in r.rules.where((e) => e.enabled)) {
          final m = _matcher(rule, ruleSets);
          if (m != null) rules.add({...m, ...act(rule.action)});
        }
        if (r.defaultAction == RuleAction.block) {
          rules.add({'action': 'reject'});
          finalTag = directTag;
        } else {
          finalTag = r.defaultAction == RuleAction.proxy ? proxyTag : directTag;
        }
    }
    return {
      'rules': rules,
      if (ruleSets.isNotEmpty) 'rule_set': ruleSets.values.toList(),
      'final': finalTag,
      'auto_detect_interface': true,
      'default_domain_resolver': 'direct-dns',
    };
  }

  String _logLevel() => switch (settings.logLevel) {
        'warning' => 'warn',
        'none' => 'panic',
        final l => l,
      };

  static bool _truthy(String v) => v == '1' || v.toLowerCase() == 'true';
}
