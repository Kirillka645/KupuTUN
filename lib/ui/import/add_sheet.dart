import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../l10n.dart';
import '../servers/server_editor_screen.dart';
import 'qr_scan_screen.dart';

/// "+" button: one bottom sheet with every way to add servers.
/// Clipboard is first because that is how most users receive links.
Future<void> showAddSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => const _AddSheet(),
    );

class _AddSheet extends StatelessWidget {
  const _AddSheet();

  @override
  Widget build(BuildContext context) {
    final mobile = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
    Widget item(IconData icon, String title, String? subtitle, Future<void> Function(BuildContext, AppState) run) => ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
            child: Icon(icon),
          ),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          onTap: () {
            final app = context.read<AppState>();
            final nav = Navigator.of(context);
            final root = nav.context;
            nav.pop();
            run(root, app);
          },
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(context.tr('import'), style: Theme.of(context).textTheme.titleLarge),
        ),
        item(Icons.content_paste_rounded, context.tr('fromClipboard'), 'vless://, vmess://, ss://, https://подписка…', _clipboard),
        item(Icons.link_rounded, context.tr('addSubscription'), null, _subscription),
        if (mobile) item(Icons.qr_code_scanner_rounded, context.tr('scanQr'), null, _qr),
        item(Icons.image_outlined, context.tr('qrFromImage'), null, _qrImage),
        item(Icons.file_open_outlined, context.tr('fromFile'), '.txt, .json, Xray / sing-box', _file),
        item(Icons.edit_note_rounded, context.tr('manual'), null, _manual),
      ]),
    );
  }
}

void _snack(BuildContext context, String text) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> _importText(BuildContext context, AppState app, String text) async {
  if (text.trim().isEmpty) {
    _snack(context, 'Буфер обмена пуст');
    return;
  }
  // A lone http(s) URL is treated as a subscription.
  final t = text.trim();
  if (!t.contains('\n') && (t.startsWith('http://') || t.startsWith('https://'))) {
    await app.addSubscription(t);
    if (context.mounted) _snack(context, context.tr('subscriptionAdded'));
    return;
  }
  final n = await app.importText(text);
  if (context.mounted) _snack(context, n > 0 ? '${context.tr('imported')}: $n' : context.tr('nothingFound'));
}

Future<void> _clipboard(BuildContext context, AppState app) async {
  final d = await Clipboard.getData(Clipboard.kTextPlain);
  if (context.mounted) await _importText(context, app, d?.text ?? '');
}

Future<void> _subscription(BuildContext context, AppState app) async {
  final url = TextEditingController();
  final name = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.link_rounded),
      title: Text(context.tr('addSubscription')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: url,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'URL', hintText: 'https://…', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: name,
          decoration: InputDecoration(labelText: context.tr('nameOptional'), border: const OutlineInputBorder()),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('add'))),
      ],
    ),
  );
  final u = url.text.trim();
  if (ok != true || u.isEmpty) return;
  try {
    await app.addSubscription(u, name: name.text.trim().isEmpty ? null : name.text.trim());
    if (context.mounted) _snack(context, context.tr('subscriptionAdded'));
  } on Object catch (e) {
    if (context.mounted) _snack(context, '${context.tr('error')}: $e');
  }
}

Future<void> _qr(BuildContext context, AppState app) async {
  final text = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
  if (text != null && context.mounted) await _importText(context, app, text);
}

Future<void> _qrImage(BuildContext context, AppState app) async {
  final text = await QrScanScreen.fromImage(context);
  if (text != null && context.mounted) await _importText(context, app, text);
}

Future<void> _file(BuildContext context, AppState app) async {
  final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
  final f = res?.files.single;
  if (f == null) return;
  final text = f.bytes != null ? utf8.decode(f.bytes!, allowMalformed: true) : await File(f.path!).readAsString();
  if (context.mounted) await _importText(context, app, text);
}

Future<void> _manual(BuildContext context, AppState app) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServerEditorScreen()));
}
