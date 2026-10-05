import 'dart:convert';

import '../models/routing_profile.dart';
import '../models/server.dart';
import '../models/subscription.dart';
import 'core_settings.dart';

class ConfigBuildException implements Exception {
  final String message;
  ConfigBuildException(this.message);
  @override
  String toString() => message;
}

/// Builds Xray-core JSON configs.
///
/// Three shapes:
///  * [buildMain]   – user connection (socks/http inbounds, optional TUN, routing, DNS)
///  * [buildBalanced] – auto-switch: N proxies behind observatory + leastPing balancer
///  * [buildBatchTest] – one instance, N HTTP inbounds each pinned to one outbound;
///    this is why mass tests are fast: one core process instead of N.
class XrayConfigBuilder {
  final CoreSettings settings;
  XrayConfigBuilder(this.settings);

  static const proxyTag = 'proxy';
  static const directTag = 'direct';
  static const blockTag = 'block';
  static const dnsTag = 'dns-out';
  static const fragmentTag = 'fragment';
  static const balancerTag = 'auto';

  // ------------------------------------------------------------------ public

  Map<String, dynamic> buildMain(Server s, RoutingProfile routing, {FragmentSettings? subFragment, NoiseSettings? subNoises}) {
    final frag = _effectiveFragment(subFragment);
    final noises = subNoises?.enabled == true ? subNoises! : settings.noises;
    if (s.params.containsKey('json')) {
      return _wrapRawJson(s, routing);
    }
    final outbounds = <Map<String, dynamic>>[
      outbound(s, proxyTag, fragment: frag.enabled),
      ..._utilityOutbounds(frag, noises),
    ];
    return {
      'log': _log(),
      'inbounds': _mainInbounds(),
      'outbounds': outbounds,
      'dns': _dns(routing),
      if (routing.dns.fakeIp) 'fakedns': [
        {'ipPool': '198.18.0.0/15', 'poolSize': 65535}
      ],
      'routing': _routing(routing, proxyTarget: {'outboundTag': proxyTag}),
      'policy': _policy(),
      'stats': {},
    };
  }

  Map<String, dynamic> buildBalanced(List<Server> servers, RoutingProfile routing, {FragmentSettings? subFragment}) {
    final usable = servers.where((s) => !s.params.containsKey('json') && s.effectiveCore == CoreType.xray).toList();
    if (usable.isEmpty) throw ConfigBuildException('no Xray-compatible servers for auto-switch');
    final frag = _effectiveFragment(subFragment);
    final outbounds = <Map<String, dynamic>>[
      for (var i = 0; i < usable.length; i++) outbound(usable[i], '$proxyTag-$i', fragment: frag.enabled),
      ..._utilityOutbounds(frag, settings.noises),
    ];
    return {
      'log': _log(),
      'inbounds': _mainInbounds(),
      'outbounds': outbounds,
      'dns': _dns(routing),
      'routing': {
        ..._routing(routing, proxyTarget: {'balancerTag': balancerTag}),
        'balancers': [
          {
            'tag': balancerTag,
            'selector': ['$proxyTag-'],
            'strategy': {
              'type': 'leastPing',
            },
            'fallbackTag': '$proxyTag-0',
          }
        ],
      },
      'observatory': {
        'subjectSelector': ['$proxyTag-'],
        'probeURL': settings.testUrl,
        'probeInterval': '${settings.healthCheckInterval.inSeconds.clamp(30, 3600)}s',
        'enableConcurrency': true,
      },
      'policy': _policy(),
      'stats': {},
    };
  }

  /// [ports] must have the same length as [servers].
  Map<String, dynamic> buildBatchTest(List<Server> servers, List<int> ports, {FragmentSettings? fragment}) {
    if (servers.length != ports.length) throw ArgumentError('ports/servers length mismatch');
    final frag = fragment ?? settings.fragment;
    return {
      'log': {'loglevel': 'none'},
      'inbounds': [
        for (var i = 0; i < servers.length; i++)
          {
            'tag': 'in-$i',
            'listen': '127.0.0.1',
            'port': ports[i],
            'protocol': 'http',
            'settings': {'allowTransparent': false},
          }
      ],
      'outbounds': [
        for (var i = 0; i < servers.length; i++) outbound(servers[i], 'out-$i', fragment: frag.enabled),
        if (frag.enabled) _fragmentOutbound(frag, settings.noises),
        {'tag': blockTag, 'protocol': 'blackhole'},
      ],
      'dns': {
        'servers': ['https://1.1.1.1/dns-query', '8.8.8.8'],
        'queryStrategy': 'UseIPv4',
      },
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          for (var i = 0; i < servers.length; i++)
            {
              'type': 'field',
              'inboundTag': ['in-$i'],
              'outboundTag': 'out-$i',
            }
        ],
      },
    };
  }

  /// A one-off config used to download subscriptions through a fragmented
  /// direct connection (bypass SNI-based blocking of the panel domain).
  Map<String, dynamic> buildFragmentedDirect(int httpPort, FragmentSettings frag) => {
        'log': {'loglevel': 'none'},
        'inbounds': [
          {'tag': 'in', 'listen': '127.0.0.1', 'port': httpPort, 'protocol': 'http', 'settings': {}}
        ],
        'outbounds': [_fragmentOutbound(frag.enabled ? frag : frag.copyWith(enabled: true), settings.noises)],
      };

  // --------------------------------------------------------------- outbounds

  Map<String, dynamic> outbound(Server s, String tag, {bool fragment = false}) {
    final o = <String, dynamic>{'tag': tag};
    switch (s.protocol) {
      case ProxyProtocol.vless:
        o['protocol'] = 'vless';
        o['settings'] = {
          'vnext': [
            {
              'address': s.address,
              'port': s.port,
              'users': [
                {
                  'id': s.credential,
                  'encryption': s.param('encryption', 'none'),
                  if (s.param('flow').isNotEmpty) 'flow': s.param('flow'),
                }
              ],
            }
          ],
        };
      case ProxyProtocol.vmess:
        o['protocol'] = 'vmess';
        o['settings'] = {
          'vnext': [
            {
              'address': s.address,
              'port': s.port,
              'users': [
                {
                  'id': s.credential,
                  'alterId': int.tryParse(s.param('aid', '0')) ?? 0,
                  'security': s.param('scy', 'auto'),
                }
              ],
            }
          ],
        };
      case ProxyProtocol.trojan:
        o['protocol'] = 'trojan';
        o['settings'] = {
          'servers': [
            {'address': s.address, 'port': s.port, 'password': s.credential}
          ],
        };
      case ProxyProtocol.shadowsocks:
        if (s.param('plugin').isNotEmpty) {
          throw ConfigBuildException('Shadowsocks plugins require the sing-box core');
        }
        o['protocol'] = 'shadowsocks';
        o['settings'] = {
          'servers': [
            {
              'address': s.address,
              'port': s.port,
              'method': s.secret ?? 'chacha20-ietf-poly1305',
              'password': s.credential,
              'uot': true,
            }
          ],
        };
      case ProxyProtocol.socks:
        o['protocol'] = 'socks';
        o['settings'] = {
          'servers': [
            {
              'address': s.address,
              'port': s.port,
              if (s.credential.isNotEmpty)
                'users': [
                  {'user': s.credential, 'pass': s.secret ?? ''}
                ],
            }
          ],
        };
      case ProxyProtocol.wireguard:
        o['protocol'] = 'wireguard';
        o['settings'] = {
          'secretKey': s.credential,
          'address': s.param('address', '10.0.0.2/32').split(',').map((e) => e.trim()).toList(),
          'peers': [
            {
              'publicKey': s.param('publickey', s.param('publicKey')),
              if (s.param('presharedkey').isNotEmpty) 'preSharedKey': s.param('presharedkey'),
              'endpoint': '${s.address.contains(':') ? '[${s.address}]' : s.address}:${s.port}',
              'allowedIPs': ['0.0.0.0/0', '::/0'],
            }
          ],
          'mtu': int.tryParse(s.param('mtu', '1420')) ?? 1420,
          if (s.param('reserved').isNotEmpty)
            'reserved': s.param('reserved').split(',').map((e) => int.tryParse(e.trim()) ?? 0).toList(),
          'domainStrategy': settings.blockIpv6 ? 'ForceIPv4' : 'ForceIP',
        };
        return o; // WireGuard has no streamSettings
      case ProxyProtocol.hysteria2:
      case ProxyProtocol.tuic:
        throw ConfigBuildException('${s.protocol.label} is served by the sing-box core');
    }
    o['streamSettings'] = _stream(s, fragment: fragment);
    if (settings.mux && s.param('flow').isEmpty && s.security != 'reality' && s.transport != 'xhttp') {
      o['mux'] = {'enabled': true, 'concurrency': settings.muxConcurrency, 'xudpConcurrency': 16, 'xudpProxyUDP443': 'reject'};
    }
    return o;
  }

  Map<String, dynamic> _stream(Server s, {required bool fragment}) {
    var net = s.transport;
    if (net == 'h2' || net == 'http' || net == 'splithttp') net = 'xhttp';
    if (net == 'raw') net = 'tcp';
    final security = s.security;
    final host = s.param('host');
    final path = s.param('path', '/');
    final st = <String, dynamic>{'network': net, 'security': security == 'xtls' ? 'tls' : security};

    switch (net) {
      case 'ws':
        st['wsSettings'] = {
          'path': path,
          if (host.isNotEmpty) 'host': host,
        };
      case 'grpc':
        st['grpcSettings'] = {
          'serviceName': s.param('serviceName', s.param('path')),
          'multiMode': s.param('mode') == 'multi',
          if (s.param('authority').isNotEmpty) 'authority': s.param('authority'),
        };
      case 'xhttp':
        st['xhttpSettings'] = {
          'path': path,
          if (host.isNotEmpty) 'host': host,
          'mode': s.param('mode', 'auto'),
          if (s.param('extra').isNotEmpty) 'extra': _tryJson(s.param('extra')),
        };
      case 'httpupgrade':
        st['httpupgradeSettings'] = {'path': path, if (host.isNotEmpty) 'host': host};
      case 'kcp':
        st['kcpSettings'] = {
          'header': {'type': s.param('headerType', 'none')},
          if (s.param('seed').isNotEmpty) 'seed': s.param('seed'),
        };
      case 'tcp':
        if (s.param('headerType') == 'http') {
          st['tcpSettings'] = {
            'header': {
              'type': 'http',
              'request': {
                'path': path.split(','),
                'headers': {'Host': host.isEmpty ? <String>[] : host.split(',')},
              },
            },
          };
        }
    }

    final sni = s.param('sni', s.param('peer', host.isNotEmpty ? host.split(',').first : s.address));
    final fp = settings.fingerprintOverride ?? s.param('fp', 'chrome');
    final alpn = s.param('alpn').isEmpty ? null : s.param('alpn').split(',');
    if (security == 'tls' || security == 'xtls') {
      st['tlsSettings'] = {
        'serverName': sni,
        'fingerprint': fp,
        if (alpn != null) 'alpn': alpn,
        'allowInsecure': _truthy(s.param('allowInsecure', s.param('insecure'))),
        if (s.param('ech').isNotEmpty) 'echConfigList': s.param('ech'),
      };
    } else if (security == 'reality') {
      st['realitySettings'] = {
        'serverName': sni,
        'fingerprint': fp,
        'publicKey': s.param('pbk'),
        'shortId': s.param('sid'),
        'spiderX': s.param('spx', '/'),
        if (s.param('pqv').isNotEmpty) 'mldsa65Verify': s.param('pqv'),
      };
    }

    final sockopt = <String, dynamic>{'tcpFastOpen': true};
    // Fragmentation only makes sense where a TLS ClientHello leaves the device.
    if (fragment && (security == 'tls' || security == 'reality') && net != 'kcp') {
      sockopt['dialerProxy'] = fragmentTag;
    }
    st['sockopt'] = sockopt;
    return st;
  }

  // ---------------------------------------------------------------- pieces

  FragmentSettings _effectiveFragment(FragmentSettings? sub) =>
      settings.fragment.enabled ? settings.fragment : (sub?.enabled == true ? sub! : settings.fragment);

  List<Map<String, dynamic>> _utilityOutbounds(FragmentSettings frag, NoiseSettings noises) => [
        {
          'tag': directTag,
          'protocol': 'freedom',
          'settings': {'domainStrategy': settings.blockIpv6 ? 'UseIPv4' : 'AsIs'},
        },
        {'tag': blockTag, 'protocol': 'blackhole', 'settings': {'response': {'type': 'http'}}},
        {'tag': dnsTag, 'protocol': 'dns', 'settings': {'nonIPQuery': 'skip'}},
        if (frag.enabled || noises.enabled) _fragmentOutbound(frag, noises),
      ];

  Map<String, dynamic> _fragmentOutbound(FragmentSettings f, NoiseSettings n) => {
        'tag': fragmentTag,
        'protocol': 'freedom',
        'settings': {
          'domainStrategy': settings.blockIpv6 ? 'UseIPv4' : 'AsIs',
          if (f.enabled)
            'fragment': {
              'packets': f.packets,
              'length': f.length,
              'interval': f.interval,
              if (f.maxSplit > 0) 'maxSplit': '${f.maxSplit}',
            },
          if (n.enabled)
            'noises': [
              {'type': n.type, 'packet': n.packet, 'delay': n.delay}
            ],
        },
        'streamSettings': {
          'sockopt': {'tcpNoDelay': true, 'tcpKeepAliveIdle': 100},
        },
      };

  List<Map<String, dynamic>> _mainInbounds() {
    final sniff = {
      'enabled': settings.sniffing,
      'destOverride': ['http', 'tls', 'quic', 'fakedns'],
      'routeOnly': true,
    };
    return [
      {
        'tag': 'socks-in',
        'listen': settings.listen,
        'port': settings.socksPort,
        'protocol': 'socks',
        'settings': {'auth': 'noauth', 'udp': true},
        'sniffing': sniff,
      },
      {
        'tag': 'http-in',
        'listen': settings.listen,
        'port': settings.httpPort,
        'protocol': 'http',
        'settings': {},
        'sniffing': sniff,
      },
      if (settings.connectionMode == ConnectionMode.tun && settings.tunEngine == TunEngine.xrayTun)
        {
          'tag': 'tun-in',
          'protocol': 'tun',
          'settings': {'name': 'kuputun0', 'MTU': settings.tunMtu},
          'sniffing': sniff,
        },
    ];
  }

  Map<String, dynamic> _dns(RoutingProfile r) {
    final directDomains = <String>[];
    final proxyDomains = <String>[];
    for (final rule in r.rules.where((e) => e.enabled)) {
      final vals = _domainValues(rule);
      if (vals.isEmpty) continue;
      if (rule.action == RuleAction.direct) directDomains.addAll(vals);
      if (rule.action == RuleAction.proxy) proxyDomains.addAll(vals);
    }
    final hosts = <String, String>{
      for (final h in r.dns.hosts.where((e) => e.contains('=')))
        h.split('=').first.trim(): h.split('=').last.trim(),
    };
    return {
      if (hosts.isNotEmpty) 'hosts': hosts,
      'servers': [
        if (r.dns.fakeIp) {'address': 'fakedns', 'domains': proxyDomains.isEmpty ? ['geosite:geolocation-!cn'] : proxyDomains},
        {
          'address': _xrayDns(r.dns.remote, local: false),
          if (proxyDomains.isNotEmpty) 'domains': proxyDomains,
        },
        if (directDomains.isNotEmpty)
          {'address': _xrayDns(r.dns.direct, local: true), 'domains': directDomains, 'skipFallback': true},
      ],
      'queryStrategy': settings.blockIpv6 ? 'UseIPv4' : 'UseIP',
      'tag': 'dns-internal',
    };
  }

  /// Xray has no DoT client; DoT servers are queried via DoH on the same host.
  /// `+local` variants bypass routing so "direct" DNS never enters the tunnel.
  static String _xrayDns(DnsServer d, {required bool local}) {
    final suffix = local ? '+local' : '';
    return switch (d.protocol) {
      DnsProtocol.udp => d.address,
      DnsProtocol.doh => d.url.replaceFirst('https://', 'https$suffix://'),
      DnsProtocol.dot => 'https$suffix://${d.address}/dns-query',
      DnsProtocol.doq => 'quic+local://${d.address}',
    };
  }

  Map<String, dynamic> _routing(RoutingProfile r, {required Map<String, String> proxyTarget}) {
    Map<String, String> target(RuleAction a) => switch (a) {
          RuleAction.proxy => proxyTarget,
          RuleAction.direct => {'outboundTag': directTag},
          RuleAction.block => {'outboundTag': blockTag},
        };
    final rules = <Map<String, dynamic>>[
      // Port 53 must *always* reach Xray's DNS module: on Android the VpnService
      // hands the OS an in-tunnel address (172.19.0.2) that only the core can
      // answer, and sing-box hijacks port 53 in both of its branches for the same
      // reason. Gating this on `blockLeaks` made every lookup time out with
      // "connected, nothing loads" as soon as DNS-leak protection was turned off.
      {'type': 'field', 'port': '53', 'outboundTag': dnsTag},
      {'type': 'field', 'inboundTag': ['dns-internal'], ...proxyTarget},
      if (settings.blockIpv6) {'type': 'field', 'ip': ['::/0'], 'outboundTag': blockTag},
      {'type': 'field', 'protocol': ['bittorrent'], 'outboundTag': directTag},
    ];
    switch (r.mode) {
      case RoutingMode.global:
        rules.add({'type': 'field', 'ip': ['geoip:private'], 'outboundTag': directTag});
        rules.add({'type': 'field', 'network': 'tcp,udp', ...proxyTarget});
      case RoutingMode.direct:
        rules.add({'type': 'field', 'network': 'tcp,udp', 'outboundTag': directTag});
      case RoutingMode.rule:
        rules.add({'type': 'field', 'ip': ['geoip:private'], 'outboundTag': directTag});
        for (final rule in r.rules.where((e) => e.enabled)) {
          final f = _ruleFields(rule);
          if (f != null) rules.add({'type': 'field', ...f, ...target(rule.action)});
        }
        rules.add({'type': 'field', 'network': 'tcp,udp', ...target(r.defaultAction)});
    }
    return {'domainStrategy': 'IPIfNonMatch', 'rules': rules};
  }

  List<String> _domainValues(RoutingRule rule) => switch (rule.type) {
        RuleMatchType.domain => rule.values.map((v) => 'full:$v').toList(),
        RuleMatchType.domainSuffix => rule.values.map((v) => 'domain:${v.startsWith('.') ? v.substring(1) : v}').toList(),
        RuleMatchType.domainKeyword => rule.values.map((v) => 'keyword:$v').toList(),
        RuleMatchType.regex => rule.values.map((v) => 'regexp:$v').toList(),
        RuleMatchType.geosite => rule.values.map((v) => 'geosite:$v').toList(),
        _ => const [],
      };

  Map<String, dynamic>? _ruleFields(RoutingRule rule) {
    final d = _domainValues(rule);
    if (d.isNotEmpty) return {'domain': d};
    return switch (rule.type) {
      RuleMatchType.ip => {'ip': rule.values},
      RuleMatchType.geoip => {'ip': rule.values.map((v) => 'geoip:$v').toList()},
      RuleMatchType.port => {'port': rule.values.join(',')},
      RuleMatchType.protocol => {'protocol': rule.values},
      RuleMatchType.process => {'process': rule.values}, // Xray >= 25.x desktop
      // Android package split-tunnelling is enforced by VpnService, not the core.
      RuleMatchType.package => null,
      _ => null,
    };
  }

  Map<String, dynamic> _policy() => {
        'levels': {
          '0': {'handshake': 4, 'connIdle': 300, 'uplinkOnly': 1, 'downlinkOnly': 1, 'statsUserUplink': false, 'statsUserDownlink': false}
        },
        'system': {'statsOutboundUplink': true, 'statsOutboundDownlink': true},
      };

  Map<String, dynamic> _wrapRawJson(Server s, RoutingProfile routing) {
    final cfg = Map<String, dynamic>.from(jsonDecode(s.param('json')) as Map);
    cfg['inbounds'] = _mainInbounds();
    cfg['log'] = _log();
    return cfg;
  }

  Map<String, dynamic> _log() => {
        'loglevel': settings.logLevel,
        if (settings.logPath != null) 'error': settings.logPath,
        'dnsLog': settings.logLevel == 'debug',
      };

  /// Raw JSON server pinned to one HTTP inbound (tester path for imported configs).
  Map<String, dynamic> buildRawJsonTest(Server s, int port) {
    final cfg = Map<String, dynamic>.from(jsonDecode(s.param('json')) as Map);
    cfg['inbounds'] = [
      {'tag': 'in-0', 'listen': '127.0.0.1', 'port': port, 'protocol': 'http', 'settings': {}}
    ];
    cfg['log'] = {'loglevel': 'none'};
    return cfg;
  }

  static dynamic _tryJson(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return s;
    }
  }

  static bool _truthy(String v) => v == '1' || v.toLowerCase() == 'true';
}
