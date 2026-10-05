import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/models/server.dart';
import '../../core/util/country.dart';
import '../../core/util/ids.dart';
import '../l10n.dart';

/// Manual server creation / editing with every share-link parameter.
/// Common keys get dedicated fields; anything else goes to "extra params".
class ServerEditorScreen extends StatefulWidget {
  final Server? initial;
  const ServerEditorScreen({super.key, this.initial});
  @override
  State<ServerEditorScreen> createState() => _ServerEditorScreenState();
}

class _ServerEditorScreenState extends State<ServerEditorScreen> {
  final _form = GlobalKey<FormState>();
  late ProxyProtocol _protocol = widget.initial?.protocol ?? ProxyProtocol.vless;
  late CoreType _core = widget.initial?.core ?? CoreType.auto;
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _address = TextEditingController(text: widget.initial?.address ?? '');
  late final _port = TextEditingController(text: widget.initial?.port.toString() ?? '443');
  late final _cred = TextEditingController(text: widget.initial?.credential ?? '');
  late final _secret = TextEditingController(text: widget.initial?.secret ?? '');
  late final Map<String, TextEditingController> _p = {
    for (final k in _keys) k: TextEditingController(text: widget.initial?.params[k] ?? ''),
  };
  late final _extra = TextEditingController(
    text: (widget.initial?.params.entries.where((e) => !_keys.contains(e.key)) ?? const <MapEntry<String, String>>[])
        .map((e) => '${e.key}=${e.value}')
        .join('\n'),
  );

  static const _keys = ['type', 'security', 'sni', 'fp', 'alpn', 'pbk', 'sid', 'spx', 'flow', 'path', 'host', 'serviceName', 'mode', 'allowInsecure'];
  static const _transports = ['tcp', 'ws', 'grpc', 'xhttp', 'httpupgrade', 'h2', 'kcp'];
  static const _securities = ['none', 'tls', 'reality'];
  static const _fps = ['', 'chrome', 'firefox', 'safari', 'ios', 'android', 'edge', '360', 'qq', 'random', 'randomized'];

  @override
  void dispose() {
    for (final c in [_name, _address, _port, _cred, _secret, _extra, ..._p.values]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _credLabel => switch (_protocol) {
        ProxyProtocol.vless || ProxyProtocol.vmess || ProxyProtocol.tuic => 'UUID',
        ProxyProtocol.socks => 'Username',
        ProxyProtocol.wireguard => 'Private key',
        _ => 'Password',
      };

  String? get _secretLabel => switch (_protocol) {
        ProxyProtocol.shadowsocks => 'Method (e.g. 2022-blake3-aes-128-gcm)',
        ProxyProtocol.socks => 'Password',
        ProxyProtocol.tuic => 'Password',
        _ => null,
      };

  bool get _hasTransport => const {ProxyProtocol.vless, ProxyProtocol.vmess, ProxyProtocol.trojan}.contains(_protocol);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final params = <String, String>{
      for (final e in _p.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    };
    for (final line in _extra.text.split('\n')) {
      final i = line.indexOf('=');
      if (i > 0) params[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
    final name = _name.text.trim().isEmpty ? '${_address.text.trim()}:${_port.text.trim()}' : _name.text.trim();
    final s = Server(
      id: widget.initial?.id ?? uuidV4(),
      subscriptionId: widget.initial?.subscriptionId,
      name: name,
      protocol: _protocol,
      address: _address.text.trim(),
      port: int.parse(_port.text.trim()),
      credential: _cred.text.trim(),
      secret: _secret.text.trim().isEmpty ? null : _secret.text.trim(),
      params: params,
      countryCode: CountryDetector.detect(name),
      sortIndex: widget.initial?.sortIndex ?? 0,
      core: _core,
      favorite: widget.initial?.favorite ?? false,
    );
    await context.read<AppState>().addManualServer(s);
    if (mounted) Navigator.pop(context);
  }

  Widget _text(TextEditingController c, String label, {bool required = false, TextInputType? kb, String? Function(String)? validator}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          keyboardType: kb,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          validator: (v) {
            if (required && (v == null || v.trim().isEmpty)) return 'Required';
            return validator?.call(v ?? '');
          },
        ),
      );

  Widget _drop(String key, List<String> options, String label) {
    final cur = _p[key]!.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: options.contains(cur) ? cur : options.first,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o.isEmpty ? '—' : o))],
        onChanged: (v) => setState(() => _p[key]!.text = v ?? ''),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sec = _p['security']!.text;
    final net = _p['type']!.text.isEmpty ? 'tcp' : _p['type']!.text;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? context.tr('manual') : context.tr('edit')),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _save)],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<ProxyProtocol>(
              initialValue: _protocol,
              decoration: InputDecoration(labelText: context.tr('protocol'), border: const OutlineInputBorder()),
              items: [for (final p in ProxyProtocol.values) DropdownMenuItem(value: p, child: Text(p.label))],
              onChanged: widget.initial == null ? (v) => setState(() => _protocol = v!) : null,
            ),
          ),
          _text(_name, 'Name'),
          _text(_address, 'Address', required: true),
          _text(_port, 'Port', required: true, kb: TextInputType.number, validator: (v) {
            final p = int.tryParse(v.trim());
            return p == null || p < 1 || p > 65535 ? '1–65535' : null;
          }),
          _text(_cred, _credLabel, required: _protocol != ProxyProtocol.socks),
          if (_secretLabel != null) _text(_secret, _secretLabel!),
          if (_hasTransport) ...[
            _drop('type', _transports, 'Transport'),
            _drop('security', _securities, 'Security'),
            if (sec == 'tls' || sec == 'reality') ...[
              _text(_p['sni']!, 'SNI'),
              _drop('fp', _fps, 'uTLS fingerprint'),
              _text(_p['alpn']!, 'ALPN (h2,http/1.1)'),
            ],
            if (sec == 'reality') ...[
              _text(_p['pbk']!, 'Public key (pbk)', required: true),
              _text(_p['sid']!, 'Short ID (sid)'),
              _text(_p['spx']!, 'SpiderX (spx)'),
            ],
            if (_protocol == ProxyProtocol.vless) _drop('flow', const ['', 'xtls-rprx-vision', 'xtls-rprx-vision-udp443'], 'Flow'),
            if (net == 'ws' || net == 'xhttp' || net == 'httpupgrade' || net == 'h2') ...[
              _text(_p['path']!, 'Path'),
              _text(_p['host']!, 'Host'),
            ],
            if (net == 'xhttp') _drop('mode', const ['auto', 'packet-up', 'stream-up', 'stream-one'], 'XHTTP mode'),
            if (net == 'grpc') ...[
              _text(_p['serviceName']!, 'gRPC serviceName'),
              _drop('mode', const ['gun', 'multi'], 'gRPC mode'),
            ],
            if (sec == 'tls') _drop('allowInsecure', const ['', '0', '1'], 'Allow insecure'),
          ],
          if (_protocol == ProxyProtocol.hysteria2 || _protocol == ProxyProtocol.tuic) _text(_p['sni']!, 'SNI'),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<CoreType>(
              initialValue: _core,
              decoration: const InputDecoration(labelText: 'Core', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: CoreType.auto, child: Text('Auto')),
                DropdownMenuItem(value: CoreType.xray, child: Text('Xray-core')),
                DropdownMenuItem(value: CoreType.singbox, child: Text('sing-box')),
              ],
              onChanged: (v) => setState(() => _core = v!),
            ),
          ),
          TextFormField(
            controller: _extra,
            minLines: 3,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Extra params (key=value per line): obfs, obfs-password, publickey, address, reserved, mtu, ech, extra…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ]),
      ),
    );
  }
}
