import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_state.dart';
import '../l10n.dart';

/// Core log viewer: level filter, auto-refresh, export.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});
  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  static const _levels = ['debug', 'info', 'warning', 'error'];
  String _min = 'info';
  List<String> _lines = const [];
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String? get _path => context.read<AppState>().coreSettings.logPath;

  Future<void> _load() async {
    final p = _path;
    if (p == null || !await File(p).exists()) return;
    final all = await File(p).readAsLines();
    final tail = all.length > 2000 ? all.sublist(all.length - 2000) : all;
    if (mounted) setState(() => _lines = tail);
  }

  int _levelOf(String line) {
    final l = line.toLowerCase();
    if (l.contains('[error]') || l.contains(' error ') || l.contains('fatal')) return 3;
    if (l.contains('[warning]') || l.contains(' warn')) return 2;
    if (l.contains('[debug]') || l.contains(' debug ')) return 0;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final min = _levels.indexOf(_min);
    final visible = _lines.where((l) => _levelOf(l) >= min).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('logs')),
        actions: [
          DropdownButton<String>(
            value: _min,
            underline: const SizedBox(),
            onChanged: (v) => setState(() => _min = v!),
            items: [for (final l in _levels) DropdownMenuItem(value: l, child: Text(l))],
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: context.tr('export'),
            onPressed: _path == null ? null : () => SharePlus.instance.share(ShareParams(files: [XFile(_path!)], subject: 'KupuTUN core log')),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              if (_path != null && await File(_path!).exists()) await File(_path!).writeAsString('');
              await _load();
            },
          ),
        ],
      ),
      body: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.all(8),
        itemCount: visible.length,
        itemBuilder: (_, i) {
          final line = visible[visible.length - 1 - i];
          final lvl = _levelOf(line);
          return Text(
            line,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: lvl == 3 ? Colors.red : (lvl == 2 ? Colors.orange : null),
            ),
          );
        },
      ),
    );
  }
}
