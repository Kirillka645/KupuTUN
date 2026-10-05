import 'dart:convert';

import '../core/models/server.dart';
import '../core/util/b64.dart';
import '../core/util/country.dart';
import '../core/util/ids.dart';

class LinkParseException implements Exception {
  final String message;
  final String link;
  LinkParseException(this.message, this.link);
  @override
  String toString() => 'LinkParseException: $message';
}

/// Parses share links into [Server]s and back.
///
/// Decision: every scheme is parsed with `Uri` after a small normalisation,
/// so IPv6 literals, percent-encoding and query params are handled once.
class LinkParser {
  static const supportedSchemes = ['vless', 'vmess', 'trojan', 'ss', 'socks', 'socks5', 'hy2', 'hysteria2', 'tuic', 'wireguard', 'wg'];

  static bool looksLikeLink(String s) {
    final i = s.indexOf('://');
    if (i <= 0) return false;
    return supportedSchemes.contains(s.substring(0, i).toLowerCase());
  }

  /// Parses many links separated by newlines; invalid lines are collected in [errors].
  static List<Server> parseMany(String text, {String? subscriptionId, List<String>? errors}) {
    final out = <Server>[];
    var idx = 0;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
      if (!looksLikeLink(line)) continue;
      try {
        out.add(parse(line, subscriptionId: subscriptionId, sortIndex: idx++));
      } on Object catch (e) {
        errors?.add('$line -> $e');
      }
    }
    return out;
  }

  static Server parse(String link, {String? subscriptionId, int sortIndex = 0}) {
    final l = link.trim();
    final sep = l.indexOf('://');
    if (sep <= 0) throw LinkParseException('missing scheme', l);
    final scheme = l.substring(0, sep).toLowerCase();
    final proto = ProxyProtocol.fromScheme(scheme);
    if (proto == null) throw LinkParseException('unsupported scheme $scheme', l);
    final s = switch (proto) {
      ProxyProtocol.vmess => _vmess(l),
      ProxyProtocol.shadowsocks => _ss(l),
      ProxyProtocol.socks => _socks(l),
      ProxyProtocol.vless || ProxyProtocol.trojan || ProxyProtocol.hysteria2 => _userAtHost(l, proto),
      ProxyProtocol.tuic => _tuic(l),
      ProxyProtocol.wireguard => _wireguard(l),
    };
    if (s.address.isEmpty || s.port <= 0 || s.port > 65535) {
      throw LinkParseException('invalid address/port', l);
    }
    return s.copyWith(
      subscriptionId: subscriptionId,
      sortIndex: sortIndex,
      rawLink: l,
      countryCode: CountryDetector.detect(s.name),
    );
  }

  // ---------------------------------------------------------------- helpers

  static String _name(Uri u, String fallback) {
    final f = u.fragment;
    if (f.isEmpty) return fallback;
    return safeDecodeComponent(f).trim();
  }

  static Map<String, String> _query(Uri u) {
    // Uri.queryParameters throws on malformed %, so decode manually.
    final out = <String, String>{};
    if (u.query.isEmpty) return out;
    for (final part in u.query.split('&')) {
      if (part.isEmpty) continue;
      final i = part.indexOf('=');
      final k = safeDecodeComponent(i < 0 ? part : part.substring(0, i));
      final v = i < 0 ? '' : safeDecodeComponent(part.substring(i + 1).replaceAll('+', '%20'));
      out[k] = v;
    }
    return out;
  }

  static String _host(Uri u) {
    var h = u.host;
    if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
    return h;
  }

  static Server _userAtHost(String l, ProxyProtocol p) {
    // hysteria2:// and hy2:// are normalised to a parsable scheme.
    final u = Uri.parse(l);
    final q = _query(u);
    if (p == ProxyProtocol.trojan) {
      q.putIfAbsent('security', () => 'tls');
    }
    if (p == ProxyProtocol.vless) {
      q.putIfAbsent('encryption', () => 'none');
    }
    if (p == ProxyProtocol.hysteria2 && q.containsKey('insecure')) {
      q['allowInsecure'] = q['insecure']!;
    }
    final port = u.hasPort ? u.port : (p == ProxyProtocol.hysteria2 ? 443 : 0);
    return Server(
      id: uuidV4(),
      name: _name(u, '${_host(u)}:$port'),
      protocol: p,
      address: _host(u),
      port: port,
      credential: safeDecodeComponent(u.userInfo),
      params: q,
    );
  }

  static Server _vmess(String l) {
    final body = l.substring(8);
    final decoded = tryDecodeBase64(body.split('#').first);
    if (decoded != null && decoded.trimLeft().startsWith('{')) {
      final j = jsonDecode(decoded) as Map<String, dynamic>;
      String g(String k) => (j[k] ?? '').toString();
      final params = <String, String>{
        'type': g('net').isEmpty ? 'tcp' : g('net'),
        'security': g('tls').isEmpty ? 'none' : g('tls'),
        if (g('scy').isNotEmpty) 'scy': g('scy'),
        if (g('aid').isNotEmpty) 'aid': g('aid'),
        if (g('host').isNotEmpty) 'host': g('host'),
        if (g('path').isNotEmpty) 'path': g('path'),
        if (g('sni').isNotEmpty) 'sni': g('sni'),
        if (g('alpn').isNotEmpty) 'alpn': g('alpn'),
        if (g('fp').isNotEmpty) 'fp': g('fp'),
        if (g('type').isNotEmpty && g('type') != 'none') 'headerType': g('type'),
      };
      if (params['type'] == 'grpc' && params.containsKey('path')) {
        params['serviceName'] = params.remove('path')!;
      }
      if (params['type'] == 'grpc' && g('type') == 'multi') params['mode'] = 'multi';
      return Server(
        id: uuidV4(),
        name: g('ps').isEmpty ? '${g('add')}:${g('port')}' : g('ps'),
        protocol: ProxyProtocol.vmess,
        address: g('add'),
        port: int.tryParse(g('port')) ?? 0,
        credential: g('id'),
        params: params,
      );
    }
    // Some panels emit vmess in the vless-like URI form.
    return _userAtHost(l, ProxyProtocol.vmess);
  }

  static Server _ss(String l) {
    // Forms: ss://BASE64(method:pass)@host:port?plugin=..#name   (SIP002)
    //        ss://BASE64(method:pass@host:port)#name             (legacy)
    //        ss://method:pass@host:port#name                     (plain, 2022 keys)
    var rest = l.substring(5);
    var name = '';
    final hash = rest.indexOf('#');
    if (hash >= 0) {
      name = safeDecodeComponent(rest.substring(hash + 1));
      rest = rest.substring(0, hash);
    }
    if (!rest.contains('@')) {
      final dec = tryDecodeBase64(rest.split('?').first);
      if (dec == null) throw LinkParseException('bad ss payload', l);
      final q = rest.contains('?') ? '?${rest.split('?').last}' : '';
      rest = '$dec$q';
    }
    final at = rest.lastIndexOf('@');
    if (at < 0) throw LinkParseException('bad ss payload', l);
    final userPart = rest.substring(0, at);
    final u = Uri.parse('ss://placeholder@${rest.substring(at + 1)}');
    String method, password;
    final plain = safeDecodeComponent(userPart);
    if (plain.contains(':')) {
      method = plain.substring(0, plain.indexOf(':'));
      password = plain.substring(plain.indexOf(':') + 1);
    } else {
      final dec = tryDecodeBase64(userPart);
      if (dec == null || !dec.contains(':')) throw LinkParseException('bad ss userinfo', l);
      method = dec.substring(0, dec.indexOf(':'));
      password = dec.substring(dec.indexOf(':') + 1);
    }
    final q = _query(u);
    return Server(
      id: uuidV4(),
      name: name.isEmpty ? '${_host(u)}:${u.port}' : name,
      protocol: ProxyProtocol.shadowsocks,
      address: _host(u),
      port: u.port,
      credential: password,
      secret: method,
      params: q,
    );
  }

  static Server _socks(String l) {
    final normalized = l.replaceFirst(RegExp(r'^socks5?://', caseSensitive: false), 'socks://');
    final u = Uri.parse(normalized);
    var user = '', pass = '';
    if (u.userInfo.isNotEmpty) {
      final raw = safeDecodeComponent(u.userInfo);
      final dec = raw.contains(':') ? raw : (tryDecodeBase64(u.userInfo) ?? raw);
      final i = dec.indexOf(':');
      user = i < 0 ? dec : dec.substring(0, i);
      pass = i < 0 ? '' : dec.substring(i + 1);
    }
    return Server(
      id: uuidV4(),
      name: _name(u, '${_host(u)}:${u.port}'),
      protocol: ProxyProtocol.socks,
      address: _host(u),
      port: u.port,
      credential: user,
      secret: pass.isEmpty ? null : pass,
      params: _query(u),
    );
  }

  static Server _tuic(String l) {
    final u = Uri.parse(l);
    final ui = safeDecodeComponent(u.userInfo);
    final i = ui.indexOf(':');
    return Server(
      id: uuidV4(),
      name: _name(u, '${_host(u)}:${u.port}'),
      protocol: ProxyProtocol.tuic,
      address: _host(u),
      port: u.port,
      credential: i < 0 ? ui : ui.substring(0, i),
      secret: i < 0 ? null : ui.substring(i + 1),
      params: _query(u),
    );
  }

  static Server _wireguard(String l) {
    final u = Uri.parse(l.replaceFirst(RegExp(r'^wg://', caseSensitive: false), 'wireguard://'));
    final q = _query(u);
    return Server(
      id: uuidV4(),
      name: _name(u, '${_host(u)}:${u.port}'),
      protocol: ProxyProtocol.wireguard,
      address: _host(u),
      port: u.hasPort ? u.port : 51820,
      credential: safeDecodeComponent(u.userInfo).isNotEmpty ? safeDecodeComponent(u.userInfo) : (q['privatekey'] ?? q['secretKey'] ?? ''),
      params: q,
    );
  }
}

/// What to hide when sharing a config.
class ShareMask {
  final bool hideAddress;
  final bool hideCredential;
  final bool hideRealityKeys;
  final bool hideName;
  const ShareMask({this.hideAddress = false, this.hideCredential = false, this.hideRealityKeys = false, this.hideName = false});
  static const none = ShareMask();
  static const all = ShareMask(hideAddress: true, hideCredential: true, hideRealityKeys: true);
}

/// Serialises a [Server] back to a share link (used for export / QR).
class LinkExporter {
  static const _mask = '***';

  static String toLink(Server s, {ShareMask mask = ShareMask.none}) {
    final addr = mask.hideAddress ? 'hidden.invalid' : s.address;
    final host = addr.contains(':') ? '[$addr]' : addr;
    final cred = mask.hideCredential ? _mask : s.credential;
    final name = Uri.encodeComponent(mask.hideName ? s.protocol.label : s.name);
    final params = Map<String, String>.from(s.params)..remove('json')..remove('jsonCore');
    if (mask.hideRealityKeys) {
      for (final k in ['pbk', 'sid', 'spx', 'publickey', 'presharedkey', 'obfs-password']) {
        if (params.containsKey(k)) params[k] = _mask;
      }
    }
    if (mask.hideAddress) {
      for (final k in ['sni', 'host', 'peer']) {
        if (params.containsKey(k)) params[k] = 'hidden.invalid';
      }
    }
    String q() => params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';

    switch (s.protocol) {
      case ProxyProtocol.vless:
        return 'vless://${Uri.encodeComponent(cred)}@$host:${s.port}${q()}#$name';
      case ProxyProtocol.trojan:
        return 'trojan://${Uri.encodeComponent(cred)}@$host:${s.port}${q()}#$name';
      case ProxyProtocol.hysteria2:
        return 'hy2://${Uri.encodeComponent(cred)}@$host:${s.port}${q()}#$name';
      case ProxyProtocol.vmess:
        final net = params['type'] ?? 'tcp';
        final j = {
          'v': '2',
          'ps': mask.hideName ? s.protocol.label : s.name,
          'add': addr,
          'port': '${s.port}',
          'id': cred,
          'aid': params['aid'] ?? '0',
          'scy': params['scy'] ?? 'auto',
          'net': net,
          'type': params['headerType'] ?? (net == 'grpc' && params['mode'] == 'multi' ? 'multi' : 'none'),
          'host': params['host'] ?? '',
          'path': net == 'grpc' ? (params['serviceName'] ?? '') : (params['path'] ?? ''),
          'tls': (params['security'] ?? 'none') == 'none' ? '' : params['security'],
          'sni': params['sni'] ?? '',
          'alpn': params['alpn'] ?? '',
          'fp': params['fp'] ?? '',
        };
        return 'vmess://${encodeBase64(jsonEncode(j))}';
      case ProxyProtocol.shadowsocks:
        final ui = encodeBase64('${s.secret}:$cred', urlSafe: true, padding: false);
        return 'ss://$ui@$host:${s.port}${q()}#$name';
      case ProxyProtocol.socks:
        final ui = s.credential.isEmpty
            ? ''
            : '${encodeBase64('${mask.hideCredential ? _mask : s.credential}:${mask.hideCredential ? _mask : (s.secret ?? '')}', urlSafe: true, padding: false)}@';
        return 'socks://$ui$host:${s.port}${q()}#$name';
      case ProxyProtocol.tuic:
        final sec = mask.hideCredential ? _mask : (s.secret ?? '');
        return 'tuic://${Uri.encodeComponent(cred)}:${Uri.encodeComponent(sec)}@$host:${s.port}${q()}#$name';
      case ProxyProtocol.wireguard:
        return 'wireguard://${Uri.encodeComponent(cred)}@$host:${s.port}${q()}#$name';
    }
  }
}
