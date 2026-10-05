import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_state.dart';
import '../../core/engine/core_manager.dart';
import '../../core/util/country.dart';

/// Desktop tray: connect/disconnect, quick server switch (top 10 by Smart
/// Score), show/hide window. Closing the window hides to tray.
class DesktopTray with TrayListener, WindowListener {
  final AppState app;
  DesktopTray(this.app);

  static bool get supported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> init() async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);
    await trayManager.setIcon(Platform.isWindows ? 'assets/tray/tray.ico' : 'assets/tray/tray.png');
    app.addListener(_rebuild);
    await _rebuild();
  }

  VpnState? _lastState;
  String? _lastServer;
  int _lastCount = -1;

  Future<void> _rebuild() async {
    final st = app.core.state;
    final cur = app.core.current?.id ?? app.selected?.id;
    // rebuild menu only when something visible changed (cheap on every notify)
    if (st == _lastState && cur == _lastServer && app.servers.length == _lastCount && !app.testing) return;
    _lastState = st;
    _lastServer = cur;
    _lastCount = app.servers.length;

    final top = [...app.servers]..sort((a, b) => app.score(b).compareTo(app.score(a)));
    await trayManager.setToolTip('KupuTUN — ${app.core.isConnected ? (app.core.current?.name ?? '') : 'отключено'}');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'toggle', label: app.core.isConnected ? 'Отключить' : 'Подключить'),
      MenuItem(key: 'best', label: 'Лучший сервер'),
      MenuItem.separator(),
      MenuItem.submenu(
        label: 'Сервер',
        submenu: Menu(items: [
          for (final s in top.take(10))
            MenuItem.checkbox(
              key: 'srv:${s.id}',
              label: '${CountryDetector.flagOf(app.results[s.id]?.exitCountry ?? s.countryCode)} ${s.name}'
                  '${app.results[s.id]?.medianMs != null ? '  ${app.results[s.id]!.medianMs} ms' : ''}',
              checked: s.id == cur,
            ),
        ]),
      ),
      MenuItem.separator(),
      MenuItem(key: 'show', label: 'Открыть'),
      MenuItem(key: 'quit', label: 'Выход'),
    ]));
  }

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  Future<void> onTrayMenuItemClick(MenuItem menuItem) async {
    final k = menuItem.key ?? '';
    if (k == 'toggle') await app.toggleConnection();
    if (k == 'best') await app.connectBest();
    if (k == 'show') await _show();
    if (k == 'quit') {
      await app.core.disconnect();
      await app.bridge.stopAll();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
    if (k.startsWith('srv:')) {
      final id = k.substring(4);
      final s = app.servers.where((e) => e.id == id).firstOrNull;
      if (s != null) await app.select(s);
    }
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> onWindowClose() async => windowManager.hide();
}
