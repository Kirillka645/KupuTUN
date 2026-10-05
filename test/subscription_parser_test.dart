import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuputun/core/models/subscription.dart';
import 'package:kuputun/subscriptions/deeplink.dart';
import 'package:kuputun/subscriptions/subscription_parser.dart';

void main() {
  test('base64 body + Happ headers', () {
    final body = base64.encode(utf8.encode('vless://a@h1:443#one\ntrojan://p@h2:443#two\n'));
    final p = SubscriptionParser.parse(body, headers: {
      'subscription-userinfo': 'upload=100; download=200; total=1000; expire=1893456000',
      'profile-title': 'base64:${base64.encode(utf8.encode('Мой VPN'))}',
      'profile-update-interval': '6',
      'support-url': 'https://t.me/support',
      'announce': 'Привет',
      'ping-type': 'proxy',
      'subscriptions-sort-type': 'ping',
      'fragmentation-enable': '1',
      'fragmentation-length': '10-20',
    });
    expect(p.servers.length, 2);
    final sub = p.applyTo(const Subscription(id: 's', url: 'https://x', title: 'old'), DateTime(2030));
    expect(sub.title, 'Мой VPN');
    expect(sub.updateInterval, const Duration(hours: 6));
    expect(sub.userInfo!.used, 300);
    expect(sub.userInfo!.remaining, 700);
    expect(sub.userInfo!.expire!.year, 2030);
    expect(sub.supportUrl, 'https://t.me/support');
    expect(sub.sortType, ProviderSortType.ping);
    expect(sub.fragment!.enabled, isTrue);
    expect(sub.fragment!.length, '10-20');
  });

  test('#key: value comments in plain body, headers win', () {
    const body = '#profile-title: FromBody\n#profile-update-interval: 3\nvless://a@h:1#x';
    final p = SubscriptionParser.parse(body, headers: {'profile-title': 'FromHeader'});
    expect(p.meta['profile-title'], 'FromHeader');
    expect(p.meta['profile-update-interval'], '3');
    expect(p.servers.single.name, 'x');
  });

  test('Xray JSON array import keeps raw config', () {
    final cfg = [
      {
        'remarks': 'JSON server',
        'outbounds': [
          {
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {'address': 'j.example', 'port': 443, 'users': [{'id': 'x'}]}
              ]
            }
          },
          {'protocol': 'freedom', 'tag': 'direct'}
        ]
      }
    ];
    final p = SubscriptionParser.parse(jsonEncode(cfg));
    expect(p.servers.single.name, 'JSON server');
    expect(p.servers.single.address, 'j.example');
    expect(p.servers.single.params['jsonCore'], 'xray');
  });

  test('deeplinks', () {
    final a = DeepLinkParser.parse('kuputun://add/${Uri.encodeComponent('https://p.example/sub/abc')}#My');
    expect(a, isA<AddSubscriptionAction>());
    expect((a as AddSubscriptionAction).url, 'https://p.example/sub/abc');
    expect(a.name, 'My');
    final happ = base64.encode(utf8.encode(jsonEncode({'Name': 'RU', 'GlobalProxy': 'true', 'DirectSites': ['geosite:category-ru'], 'DirectIp': ['geoip:ru']})));
    final r = DeepLinkParser.parse('happ://routing/onadd/$happ');
    expect(r, isA<AddRoutingAction>());
    expect((r as AddRoutingAction).activate, isTrue);
    expect(r.profile.rules.length, 2);
  });
}
