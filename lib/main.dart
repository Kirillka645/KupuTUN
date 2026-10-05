import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_state.dart';
import 'ui/app.dart';
import 'ui/desktop/tray.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = await AppState.load();

  // Deeplinks: kuputun://, happ:// and plain share links handed to the app.
  final links = AppLinks();
  final initial = await links.getInitialLinkString();
  if (initial != null) unawaited(app.importText(initial));
  links.stringLinkStream.listen(app.importText);
  // Desktop: links passed on the command line (registered URL handler).
  for (final a in args) {
    if (a.contains('://')) unawaited(app.importText(a));
  }

  if (DesktopTray.supported) await DesktopTray(app).init();

  // Make sure the core is stopped if the process is asked to quit.
  if (!Platform.isAndroid && !Platform.isIOS) {
    ProcessSignal.sigint.watch().listen((_) async {
      await app.core.disconnect();
      exit(0);
    });
  }

  runApp(ChangeNotifierProvider.value(value: app, child: const KupuTunApp()));
}
