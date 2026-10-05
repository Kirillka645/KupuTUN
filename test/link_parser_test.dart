import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuputun/core/models/server.dart';
import 'package:kuputun/subscriptions/link_parser.dart';

void main() {
  group('LinkParser', () {
    test('VLESS Reality Vision', () {
      final s = LinkParser.parse(
          'vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.2.3.4:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=abcPBK&sid=6ba85179e30d4fc2&type=tcp#%F0%9F%87%A9%F0%9F%87%AA%20Germany');
      expect(s.protocol, ProxyProtocol.vless);
      expect(s.address, '1.2.3.4');
      expect(s.port, 443);
      expect(s.credential, 'b831381d-6324-4d53-ad4f-8cda48b30811');
      expect(s.param('flow'), 'xtls-rprx-vision');
      expect(s.security, 'reality');
      expect(s.param('pbk'), 'abcPBK');
      expect(s.name, '🇩🇪 Germany');
      expect(s.countryCode, 'DE');
    });

    test('VLESS XHTTP + IPv6 host', () {
      final s = LinkParser.parse('vless://id@[2001:db8::1]:8443?type=xhttp&path=%2Fxh&mode=packet-up&security=tls&sni=a.example#x');
      expect(s.address, '2001:db8::1');
      expect(s.transport, 'xhttp');
      expect(s.param('path'), '/xh');
      expect(s.param('mode'), 'packet-up');
    });

    test('VMess v2rayN JSON with gRPC', () {
      final j = {'v': '2', 'ps': 'NL gRPC', 'add': 'nl.example.com', 'port': '443', 'id': 'uuid-1', 'aid': '0', 'net': 'grpc', 'path': 'svc', 'tls': 'tls', 'sni': 'nl.example.com'};
      final s = LinkParser.parse('vmess://${base64.encode(utf8.encode(jsonEncode(j)))}');
      expect(s.protocol, ProxyProtocol.vmess);
      expect(s.transport, 'grpc');
      expect(s.param('serviceName'), 'svc');
      expect(s.security, 'tls');
      expect(s.countryCode, 'NL');
    });

    test('Trojan defaults to TLS', () {
      final s = LinkParser.parse('trojan://p%40ss@t.example:443?sni=t.example#T');
      expect(s.credential, 'p@ss');
      expect(s.security, 'tls');
    });

    test('Shadowsocks SIP002 and legacy', () {
      final ui = base64Url.encode(utf8.encode('aes-256-gcm:secret')).replaceAll('=', '');
      final a = LinkParser.parse('ss://$ui@ss.example:8388#SS');
      expect(a.secret, 'aes-256-gcm');
      expect(a.credential, 'secret');
      expect(a.port, 8388);
      final legacy = base64.encode(utf8.encode('chacha20-ietf-poly1305:pw@1.1.1.1:443'));
      final b = LinkParser.parse('ss://$legacy#Legacy');
      expect(b.address, '1.1.1.1');
      expect(b.secret, 'chacha20-ietf-poly1305');
    });

    test('Shadowsocks 2022 plain userinfo', () {
      final s = LinkParser.parse('ss://2022-blake3-aes-128-gcm:YctPZ6U7xPPcU%2Bgp3u%2B0tx%2FtRizJN9K8y%2BuKlW2qjlI%3D@h.example:443#ss22');
      expect(s.secret, '2022-blake3-aes-128-gcm');
      expect(s.credential, 'YctPZ6U7xPPcU+gp3u+0tx/tRizJN9K8y+uKlW2qjlI=');
    });

    test('Hysteria2 & TUIC & SOCKS & WireGuard', () {
      final h = LinkParser.parse('hy2://pass@hy.example:8443?sni=hy.example&obfs=salamander&obfs-password=x&insecure=1#HY');
      expect(h.protocol, ProxyProtocol.hysteria2);
      expect(h.effectiveCore, CoreType.singbox);
      expect(h.param('obfs'), 'salamander');
      final t = LinkParser.parse('tuic://uuid:pw@tu.example:443?congestion_control=bbr&alpn=h3#TU');
      expect(t.credential, 'uuid');
      expect(t.secret, 'pw');
      final so = LinkParser.parse('socks://${base64.encode(utf8.encode('u:p'))}@s.example:1080#S');
      expect(so.credential, 'u');
      expect(so.secret, 'p');
      final w = LinkParser.parse('wireguard://privKey%3D@wg.example:51820?publickey=pub%3D&address=10.0.0.2%2F32&mtu=1280#WG');
      expect(w.credential, 'privKey=');
      expect(w.param('publickey'), 'pub=');
    });

    test('round trip export -> parse keeps fields', () {
      final orig = LinkParser.parse('vless://id@h.example:443?type=ws&path=%2Fws&host=cdn.example&security=tls&sni=cdn.example#Name%20X');
      final again = LinkParser.parse(LinkExporter.toLink(orig));
      expect(again.fingerprint, orig.fingerprint);
      expect(again.name, 'Name X');
      expect(again.param('host'), 'cdn.example');
    });

    test('masked export hides secrets', () {
      final s = LinkParser.parse('vless://secret-uuid@real.host:443?security=reality&pbk=KEY&sid=ab#n');
      final l = LinkExporter.toLink(s, mask: ShareMask.all);
      expect(l.contains('secret-uuid'), isFalse);
      expect(l.contains('real.host'), isFalse);
      expect(l.contains('KEY'), isFalse);
    });

    test('parseMany skips junk and collects errors', () {
      final errs = <String>[];
      final list = LinkParser.parseMany('# comment\nvless://id@a:1#a\nfoo\nvless://bad\n', errors: errs);
      expect(list.length, 1);
      expect(errs.length, 1);
    });
  });
}
