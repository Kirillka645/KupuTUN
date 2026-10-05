import 'package:flutter_test/flutter_test.dart';
import 'package:kuputun/core/config/core_settings.dart';
import 'package:kuputun/core/config/singbox_config_builder.dart';
import 'package:kuputun/core/config/xray_config_builder.dart';
import 'package:kuputun/core/models/subscription.dart';
import 'package:kuputun/routing/routing_presets.dart';
import 'package:kuputun/subscriptions/link_parser.dart';

void main() {
  final reality = LinkParser.parse('vless://id@1.2.3.4:443?flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&pbk=PBK&sid=ab&fp=chrome&type=tcp#r');
  final ws = LinkParser.parse('vless://id@h.example:443?type=ws&path=%2Fws&host=cdn.example&security=tls&sni=cdn.example#w');

  test('xray reality outbound', () {
    final o = XrayConfigBuilder(const CoreSettings()).outbound(reality, 'proxy');
    final rs = o['streamSettings']['realitySettings'] as Map;
    expect(rs['publicKey'], 'PBK');
    expect(rs['serverName'], 'www.microsoft.com');
    expect((o['settings']['vnext'] as List).first['users'].first['flow'], 'xtls-rprx-vision');
  });

  test('xray fragmentation via dialerProxy', () {
    const settings = CoreSettings(fragment: FragmentSettings(enabled: true));
    final cfg = XrayConfigBuilder(settings).buildMain(ws, RoutingPresets.russiaDirect());
    final proxy = (cfg['outbounds'] as List).first as Map;
    expect(proxy['streamSettings']['sockopt']['dialerProxy'], 'fragment');
    expect((cfg['outbounds'] as List).any((o) => (o as Map)['tag'] == 'fragment'), isTrue);
  });

  test('xray batch test config maps inbound i -> outbound i', () {
    final cfg = XrayConfigBuilder(const CoreSettings()).buildBatchTest([reality, ws], [20001, 20002]);
    expect((cfg['inbounds'] as List).length, 2);
    final rules = cfg['routing']['rules'] as List;
    expect(rules[1]['inboundTag'], ['in-1']);
    expect(rules[1]['outboundTag'], 'out-1');
  });

  test('xray russia preset has geoip:ru direct and catch-all proxy', () {
    final cfg = XrayConfigBuilder(const CoreSettings()).buildMain(ws, RoutingPresets.russiaDirect());
    final rules = (cfg['routing']['rules'] as List).cast<Map<dynamic, dynamic>>();
    expect(rules.any((r) => (r['ip'] as List?)?.contains('geoip:ru') == true && r['outboundTag'] == 'direct'), isTrue);
    expect(rules.last['outboundTag'], 'proxy');
  });

  test('sing-box hysteria2 + rule-sets', () {
    final hy = LinkParser.parse('hy2://pw@hy.example:443?sni=hy.example&obfs=salamander&obfs-password=o#h');
    final cfg = SingboxConfigBuilder(const CoreSettings()).buildMain(hy, RoutingPresets.russiaDirect());
    final ob = (cfg['outbounds'] as List).first as Map;
    expect(ob['type'], 'hysteria2');
    expect(ob['obfs']['type'], 'salamander');
    final ruleSets = cfg['route']['rule_set'] as List;
    expect(ruleSets.any((r) => (r as Map)['tag'] == 'geoip-ru'), isTrue);
  });

  test('sing-box rejects xhttp', () {
    final x = LinkParser.parse('vless://id@h:443?type=xhttp#x');
    expect(() => SingboxConfigBuilder(const CoreSettings()).outbound(x, 'p'), throwsA(isA<ConfigBuildException>()));
  });
}
