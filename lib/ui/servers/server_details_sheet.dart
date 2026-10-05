import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/app_state.dart';
import '../../core/models/server.dart';
import '../../core/models/test_result.dart';
import '../../core/util/country.dart';
import '../../subscriptions/link_parser.dart';
import '../../tester/bypass_finder.dart';
import '../../tester/speed_tester.dart';
import '../l10n.dart';
import '../widgets/charts.dart';
import '../widgets/format.dart';
import 'server_editor_screen.dart';

Future<void> showServerDetails(BuildContext context, Server s) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, ctrl) => _Details(server: s, scroll: ctrl),
      ),
    );

class _Details extends StatefulWidget {
  final Server server;
  final ScrollController scroll;
  const _Details({required this.server, required this.scroll});
  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  List<TestResult> _history = const [];
  final _down = <double?>[];
  final _up = <double?>[];
  bool _speedRunning = false, _svcRunning = false, _bypassRunning = false;
  String? _bypassLog;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    // Read the provider before awaiting: the sheet can be closed while the
    // query runs, and context.read on a deactivated element throws.
    final app = context.read<AppState>();
    final h = await app.historyOf(widget.server);
    if (mounted) setState(() => _history = h);
  }

  Future<void> _speed(AppState app) async {
    final est = app.speedTrafficEstimate(1);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.tr('speedTest')),
        content: Text('${context.tr('trafficWarning')} ${formatBytes(est)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(context.tr('start'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _speedRunning = true;
      _down.clear();
      _up.clear();
    });
    try {
      await app.speedTest(widget.server, onSample: (SpeedSample s) {
        if (!mounted) return;
        setState(() => (s.upload ? _up : _down).add(s.mbps));
      });
    } on Object catch (e) {
      // The bridge can fail (no free port, core refuses to stop); without this
      // the flag stayed true and the button was disabled forever.
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _speedRunning = false);
    }
    await _loadHistory();
  }

  Future<void> _services(AppState app) async {
    setState(() => _svcRunning = true);
    try {
      await app.checkServices(widget.server);
    } on Object catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _svcRunning = false);
    }
  }

  Future<void> _bypass(AppState app) async {
    setState(() {
      _bypassRunning = true;
      _bypassLog = '';
    });
    final finder = BypassFinder(app.bridge, app.coreSettings);
    try {
      await for (final (preset, ms) in finder.tryAll(widget.server)) {
        if (!mounted) return;
        setState(() => _bypassLog = '${_bypassLog!}${preset.enabled ? preset.toString() : 'без фрагментации'}: ${ms == null ? '✕' : '$ms ms'}\n');
        if (ms != null) {
          await app.updateCore(app.coreSettings.copyWith(fragment: preset));
          if (!mounted) return;
          setState(() => _bypassLog = '${_bypassLog!}✓ Применено: ${preset.enabled ? preset : 'off'}');
          break;
        }
      }
    } on Object catch (e) {
      if (mounted) setState(() => _bypassLog = '${_bypassLog ?? ''}$e');
    } finally {
      if (mounted) setState(() => _bypassRunning = false);
    }
  }

  Future<void> _share(AppState app) async {
    var mask = ShareMask.none;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final link = app.exportLink(widget.server, mask: mask);
        return AlertDialog(
          title: Text(context.tr('share')),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(color: Colors.white, padding: const EdgeInsets.all(8), child: QrImageView(data: link, size: 240)),
              SwitchListTile(
                title: Text(context.tr('hideSensitive')),
                value: mask != ShareMask.none,
                onChanged: (v) => set(() => mask = v ? ShareMask.all : ShareMask.none),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: link));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
              },
              child: const Text('Copy'),
            ),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.servers.firstWhere((e) => e.id == widget.server.id, orElse: () => widget.server);
    final r = app.results[s.id];
    final theme = Theme.of(context);
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Row(children: [
        Text(CountryDetector.flagOf(r?.exitCountry ?? s.countryCode), style: const TextStyle(fontSize: 36)),
        const SizedBox(width: 12),
        Expanded(child: Text(s.name, style: theme.textTheme.titleLarge)),
        IconButton(
          icon: Icon(s.favorite ? Icons.star_rounded : Icons.star_outline_rounded, color: s.favorite ? Colors.amber : null),
          onPressed: () => app.toggleFavorite(s),
        ),
      ]),
      Text('${s.protocol.label} · ${s.transport} · ${s.security} · ${s.address}:${s.port}', style: theme.textTheme.bodySmall),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _metric(context, 'Ping', r?.medianMs == null ? '—' : '${r!.medianMs} ms', pingColor(r?.medianMs)),
        _metric(context, 'Jitter', r?.jitterMs == null ? '—' : '${r!.jitterMs!.toStringAsFixed(1)} ms', null),
        _metric(context, 'Loss', r == null ? '—' : '${r.lossPercent.toStringAsFixed(0)} %', null),
        _metric(context, 'TLS', r?.tlsHandshakeMs == null ? '—' : '${r!.tlsHandshakeMs} ms', null),
        _metric(context, '↓', formatMbps(r?.downloadMbps), null),
        _metric(context, '↑', formatMbps(r?.uploadMbps), null),
        _metric(context, 'Smart', app.score(s) < 0 ? '—' : app.score(s).toStringAsFixed(0), theme.colorScheme.primary),
      ]),
      if (r?.exitIp != null) ...[
        const SizedBox(height: 8),
        Text('${context.tr('exitIp')}: ${r!.exitIp} ${CountryDetector.flagOf(r.exitCountry)}'),
      ],
      if (r?.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r!.error!, style: TextStyle(color: theme.colorScheme.error))),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: _speedRunning ? null : () => _speed(app),
          icon: const Icon(Icons.speed),
          label: Text(context.tr('speedTest')),
        ),
        OutlinedButton.icon(
          onPressed: _svcRunning ? null : () => _services(app),
          icon: _svcRunning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.public),
          label: Text(context.tr('services')),
        ),
        OutlinedButton.icon(onPressed: () => _share(app), icon: const Icon(Icons.qr_code), label: Text(context.tr('share'))),
        OutlinedButton.icon(
          onPressed: _bypassRunning ? null : () => _bypass(app),
          icon: const Icon(Icons.tune),
          label: Text(context.tr('bypassAuto')),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ServerEditorScreen(initial: s))),
          icon: const Icon(Icons.edit),
          label: Text(context.tr('edit')),
        ),
      ]),
      if (_down.isNotEmpty || _speedRunning) ...[
        const SizedBox(height: 16),
        Text('↓ Mbit/s', style: theme.textTheme.labelMedium),
        Sparkline(values: _down, color: Colors.blue, height: 80),
        if (_up.isNotEmpty) ...[
          Text('↑ Mbit/s', style: theme.textTheme.labelMedium),
          Sparkline(values: _up, color: Colors.orange, height: 60),
        ],
      ],
      if (r != null && r.services.isNotEmpty) ...[
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in r.services.entries)
            Chip(
              avatar: Icon(e.value ? Icons.check_circle : Icons.cancel, color: e.value ? Colors.green : Colors.red, size: 18),
              label: Text(e.key),
            ),
        ]),
      ],
      if (_bypassLog != null) ...[
        const SizedBox(height: 16),
        Text(_bypassLog!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ],
      if (_history.length >= 2) ...[
        const SizedBox(height: 16),
        Text('${context.tr('history')} · ping', style: theme.textTheme.labelMedium),
        Sparkline(values: _history.map((h) => h.medianMs?.toDouble()).toList(), color: theme.colorScheme.primary, height: 48),
        if (_history.any((h) => h.downloadMbps != null)) ...[
          Text('${context.tr('history')} · ↓', style: theme.textTheme.labelMedium),
          Sparkline(values: _history.where((h) => h.downloadMbps != null).map((h) => h.downloadMbps).toList(), color: Colors.blue, height: 48),
        ],
      ],
    ]);
  }

  Widget _metric(BuildContext context, String label, String value, Color? color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}
