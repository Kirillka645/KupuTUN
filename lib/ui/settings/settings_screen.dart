import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/config/core_settings.dart';
import '../../core/engine/vpn_platform.dart';
import '../../core/models/test_result.dart';
import '../../data/vault.dart';
import '../../routing/geo_updater.dart';
import '../../tester/smart_score.dart';
import '../../tester/speed_tester.dart';
import '../l10n.dart';
import '../widgets/fit_segmented.dart';
import 'appearance_screen.dart';
import 'logs_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const SettingsHub();

  /// All settings pages. The hub lists them; each opens as its own screen.
  List<_Section> _sections(BuildContext context) {
    final app = context.watch<AppState>();
    final c = app.coreSettings;
    final t = app.testerSettings;
    final ui = app.ui;
    final autoPing = t.autoTestOnLaunch || t.autoTestAfterUpdate;

    return [
          // ------------------------------------------------ server choice
          _Section(id: 'pick', color: const Color(0xFF7C4DFF), summary: context.tr(switch (ui.serverPick) { ServerPick.smart => 'pickSmart', ServerPick.ping => 'pickPing', ServerPick.manual => 'pickManual' }), title: context.tr('pickTitle'), icon: Icons.auto_awesome_rounded, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: FitSegmented<ServerPick>(
                segments: [
                  FitSegment(ServerPick.smart, context.tr('pickSmartShort'), icon: Icons.auto_awesome_rounded),
                  FitSegment(ServerPick.ping, context.tr('pickPingShort'), icon: Icons.network_ping_rounded),
                  FitSegment(ServerPick.manual, context.tr('pickManualShort'), icon: Icons.touch_app_rounded),
                ],
                selected: ui.serverPick,
                onChanged: (v) => app.updateUi(ui.copyWith(serverPick: v)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                context.tr(switch (ui.serverPick) {
                  ServerPick.smart => 'pickSmartDesc',
                  ServerPick.ping => 'pickPingDesc',
                  ServerPick.manual => 'pickManualDesc',
                }),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            SwitchListTile(
              title: Text(context.tr('pickInSub')),
              value: ui.pickInSubscription,
              onChanged: ui.serverPick == ServerPick.manual ? null : (v) => app.updateUi(ui.copyWith(pickInSubscription: v)),
            ),
          ]),
          // ------------------------------------------------ ping
          _Section(id: 'ping', color: const Color(0xFF00A86B), summary: '${autoPing ? context.tr('pingAuto') : context.tr('pingManual')} · ${t.concurrency} потоков', title: context.tr('pingSection'), icon: Icons.speed_rounded, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: FitSegmented<bool>(
                segments: [
                  FitSegment(true, context.tr('pingAuto'), icon: Icons.bolt_rounded),
                  FitSegment(false, context.tr('pingManual'), icon: Icons.speed_rounded),
                ],
                selected: autoPing,
                onChanged: (v) => app.updateTester(t.copyWith(autoTestOnLaunch: v, autoTestAfterUpdate: v)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                context.tr(autoPing ? 'pingAutoDesc' : 'pingManualDesc'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            if (autoPing) ...[
              SwitchListTile(title: Text(context.tr('pingOnLaunch')), value: t.autoTestOnLaunch, onChanged: (v) => app.updateTester(t.copyWith(autoTestOnLaunch: v))),
              SwitchListTile(title: Text(context.tr('pingAfterUpdate')), value: t.autoTestAfterUpdate, onChanged: (v) => app.updateTester(t.copyWith(autoTestAfterUpdate: v))),
            ],
            ListTile(
              title: const Text('Тип пинга'),
              trailing: DropdownButton<PingMode>(
                value: t.pingMode,
                underline: const SizedBox.shrink(),
                onChanged: (v) => app.updateTester(t.copyWith(pingMode: v)),
                items: const [
                  DropdownMenuItem(value: PingMode.realDelay, child: Text('Real delay')),
                  DropdownMenuItem(value: PingMode.tcp, child: Text('TCP')),
                  DropdownMenuItem(value: PingMode.icmp, child: Text('ICMP')),
                ],
              ),
            ),
            _sliderTile('Потоков', t.concurrency.toDouble(), 1, 64, (v) => app.updateTester(t.copyWith(concurrency: v.round()))),
            _sliderTile('Таймаут, с', t.timeout.inSeconds.toDouble(), 3, 15, (v) => app.updateTester(t.copyWith(timeout: Duration(seconds: v.round())))),
            _sliderTile('Замеров на сервер', t.samples.toDouble(), 1, 10, (v) => app.updateTester(t.copyWith(samples: v.round()))),
            SwitchListTile(title: const Text('Замерять TLS-handshake'), value: t.measureTls, onChanged: (v) => app.updateTester(t.copyWith(measureTls: v))),
            const ListTile(title: Text('Тест скорости'), dense: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FitSegmented<SpeedMode>(
                segments: const [
                  FitSegment(SpeedMode.quick, 'Быстрый', icon: Icons.bolt_rounded),
                  FitSegment(SpeedMode.accurate, 'Точный', icon: Icons.verified_rounded),
                ],
                selected: t.speedMode,
                onChanged: (v) => app.updateTester(t.copyWith(speedMode: v)),
              ),
            ),
            ExpansionTile(
              title: const Text('Smart Score — веса'),
              shape: const Border(),
              children: [
                for (final (label, value, apply) in <(String, double, ScoreWeights Function(double))>[
                  ('Пинг', t.weights.ping, (v) => ScoreWeights(ping: v, speed: t.weights.speed, stability: t.weights.stability, loss: t.weights.loss)),
                  ('Скорость', t.weights.speed, (v) => ScoreWeights(ping: t.weights.ping, speed: v, stability: t.weights.stability, loss: t.weights.loss)),
                  ('Стабильность', t.weights.stability, (v) => ScoreWeights(ping: t.weights.ping, speed: t.weights.speed, stability: v, loss: t.weights.loss)),
                  ('Потери', t.weights.loss, (v) => ScoreWeights(ping: t.weights.ping, speed: t.weights.speed, stability: t.weights.stability, loss: v)),
                ])
                  _sliderTile(label, value * 100, 0, 100, (v) => app.updateTester(t.copyWith(weights: apply(v / 100)))),
              ],
            ),
          ]),
          // ------------------------------------------------ appearance
          _Section(id: 'look', color: const Color(0xFFE91E63), summary: 'Тема, цвета, язык', title: context.tr('appearance'), icon: Icons.palette_rounded, children: [
            ListTile(
              leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary, radius: 14),
              title: Text(context.tr('themeAndColors')),
              subtitle: Text([
                switch (ui.themeMode) { ThemeMode.system => 'Как в системе', ThemeMode.light => 'Светлая', ThemeMode.dark => 'Тёмная' },
                if (ui.dynamicColor) 'Material You',
                if (ui.amoled) 'AMOLED',
              ].join(' · ')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceScreen())),
            ),
            ListTile(
              title: const Text('Язык / Language'),
              trailing: DropdownButton<String>(
                value: ui.locale ?? '',
                underline: const SizedBox.shrink(),
                onChanged: (v) => app.updateUi(UiSettings.fromJson({...ui.toJson(), 'locale': (v ?? '').isEmpty ? null : v})),
                items: const [
                  DropdownMenuItem(value: '', child: Text('System')),
                  DropdownMenuItem(value: 'ru', child: Text('Русский')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'fa', child: Text('فارسی')),
                  DropdownMenuItem(value: 'zh', child: Text('中文')),
                ],
              ),
            ),
          ]),
          // ------------------------------------------------ home screen
          _Section(id: 'home', color: const Color(0xFF8E24AA), summary: ui.pinPowerButton ? 'Кнопка закреплена' : 'Кнопка прокручивается', title: 'Главный экран', icon: Icons.home_rounded, children: [
            SwitchListTile(
              secondary: const Icon(Icons.push_pin_rounded),
              title: const Text('Закрепить кнопку подключения'),
              subtitle: const Text('Кнопка остаётся на месте, листается только список серверов'),
              value: ui.pinPowerButton,
              onChanged: (v) => app.updateUi(ui.copyWith(pinPowerButton: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.swap_vert_rounded),
              title: const Text('Скорость и трафик'),
              subtitle: const Text('Показывать ↑/↓ во время подключения'),
              value: ui.showTraffic,
              onChanged: (v) => app.updateUi(ui.copyWith(showTraffic: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.flag_rounded),
              title: const Text('Флаги стран'),
              value: ui.showFlags,
              onChanged: (v) => app.updateUi(ui.copyWith(showFlags: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_rounded),
              title: const Text('Скрывать недоступные серверы'),
              subtitle: const Text('Серверы с timeout после последнего пинга'),
              value: ui.hideDead,
              onChanged: (v) => app.updateUi(ui.copyWith(hideDead: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.view_agenda_outlined),
              title: const Text('Компактный список'),
              value: ui.compactList,
              onChanged: (v) => app.updateUi(ui.copyWith(compactList: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.vibration_rounded),
              title: const Text('Вибрация при нажатии'),
              value: ui.haptics,
              onChanged: (v) => app.updateUi(ui.copyWith(haptics: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.help_outline_rounded),
              title: const Text('Подтверждать отключение'),
              value: ui.confirmDisconnect,
              onChanged: (v) => app.updateUi(ui.copyWith(confirmDisconnect: v)),
            ),
          ]),
          // ------------------------------------------------ connection
          _Section(id: 'conn', color: const Color(0xFF2E7DFF), summary: [c.connectionMode == ConnectionMode.tun ? 'TUN (VPN)' : c.connectionMode.name, if (c.killSwitch) 'Kill switch', if (c.autoSwitch) 'автопереключение'].join(' · '), title: 'Подключение', icon: Icons.vpn_lock_rounded, children: [
            ListTile(
              title: const Text('Режим'),
              trailing: DropdownButton<ConnectionMode>(
                value: c.connectionMode,
                underline: const SizedBox.shrink(),
                onChanged: (v) => app.updateCore(c.copyWith(connectionMode: v)),
                items: const [
                  DropdownMenuItem(value: ConnectionMode.tun, child: Text('TUN (VPN)')),
                  DropdownMenuItem(value: ConnectionMode.systemProxy, child: Text('Системный прокси')),
                  DropdownMenuItem(value: ConnectionMode.proxyOnly, child: Text('Только SOCKS/HTTP')),
                ],
              ),
            ),
            if (!Platform.isAndroid)
              ListTile(
                title: const Text('TUN-движок'),
                subtitle: const Text('sing-box — рекомендуется; Xray — экспериментально'),
                trailing: DropdownButton<TunEngine>(
                  value: c.tunEngine,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) => app.updateCore(c.copyWith(tunEngine: v)),
                  items: const [
                    DropdownMenuItem(value: TunEngine.singboxTun, child: Text('sing-box')),
                    DropdownMenuItem(value: TunEngine.tun2socks, child: Text('tun2socks')),
                    DropdownMenuItem(value: TunEngine.xrayTun, child: Text('Xray')),
                  ],
                ),
              ),
            SwitchListTile(title: const Text('Подключаться при запуске'), value: ui.connectOnLaunch, onChanged: (v) => app.updateUi(ui.copyWith(connectOnLaunch: v))),
            SwitchListTile(
              title: const Text('Подключаться в Wi-Fi сетях'),
              subtitle: const Text('Автоматически включать VPN при подключении к Wi-Fi'),
              value: ui.connectOnUntrustedWifi,
              onChanged: (v) => app.updateUi(ui.copyWith(connectOnUntrustedWifi: v)),
            ),
            SwitchListTile(
              title: Text(context.tr('autoSwitch')),
              subtitle: Text('Проверка каждые ${c.healthCheckInterval.inMinutes} мин, переключение при деградации'),
              value: c.autoSwitch,
              onChanged: (v) => app.updateCore(c.copyWith(autoSwitch: v)),
            ),
            if (c.autoSwitch)
              Slider(
                min: 1,
                max: 30,
                divisions: 29,
                value: c.healthCheckInterval.inMinutes.toDouble().clamp(1, 30),
                label: '${c.healthCheckInterval.inMinutes} мин',
                onChanged: (v) => app.updateCore(c.copyWith(healthCheckInterval: Duration(minutes: v.round()))),
              ),
            SwitchListTile(title: const Text('Kill switch'), value: c.killSwitch, onChanged: (v) => app.updateCore(c.copyWith(killSwitch: v))),
            SwitchListTile(title: const Text('Блокировать IPv6 (защита от утечек)'), value: c.blockIpv6, onChanged: (v) => app.updateCore(c.copyWith(blockIpv6: v))),
            SwitchListTile(title: const Text('Mux'), value: c.mux, onChanged: (v) => app.updateCore(c.copyWith(mux: v))),
            SwitchListTile(title: const Text('Разрешить подключения из LAN'), value: c.allowLan, onChanged: (v) => app.updateCore(c.copyWith(allowLan: v))),
            if (Platform.isAndroid) ...[
              ListTile(
                title: const Text('Always-on VPN'),
                subtitle: const Text('Системные настройки: «Постоянная VPN» и «Блокировать без VPN»'),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => VpnPlatform().openAlwaysOnSettings(),
              ),
              ListTile(
                title: const Text('Раздельное туннелирование'),
                subtitle: Text(switch (ui.splitMode) {
                  SplitMode.off => 'Выключено',
                  SplitMode.onlySelected => 'Только выбранные (${ui.splitPackages.length})',
                  SplitMode.exceptSelected => 'Кроме выбранных (${ui.splitPackages.length})',
                }),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _SplitTunnelScreen())),
              ),
            ],
          ]),
          // ------------------------------------------------ quick settings tile
          if (Platform.isAndroid)
            _Section(id: 'tile', color: const Color(0xFFFF9800), summary: 'Плитка, уведомление', title: 'Плитка и уведомление', icon: Icons.widgets_rounded, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Добавьте плитку KupuTUN в быстрые настройки (шторка → ✎). Что делать при нажатии:',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              RadioGroup<TileAction>(
                groupValue: ui.tileAction,
                onChanged: (v) => app.updateUi(ui.copyWith(tileAction: v)),
                child: const Column(children: [
                  RadioListTile<TileAction>(
                    value: TileAction.toggleLast,
                    title: Text('Подключить в одно касание'),
                    subtitle: Text('К последнему серверу, без открытия приложения'),
                  ),
                  RadioListTile<TileAction>(
                    value: TileAction.connectBest,
                    title: Text('Лучший сервер'),
                    subtitle: Text('Открыть приложение, выбрать лучший сервер и подключиться'),
                  ),
                  RadioListTile<TileAction>(
                    value: TileAction.openApp,
                    title: Text('Только открыть приложение'),
                  ),
                ]),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Скорость в уведомлении'),
                subtitle: const Text('↓/↑ и трафик в уведомлении VPN, обновление раз в 2 с'),
                value: ui.notifSpeed,
                onChanged: (v) => app.updateUi(ui.copyWith(notifSpeed: v)),
              ),
            ]),
          // ------------------------------------------------ bypass
          _Section(id: 'bypass', color: const Color(0xFF009688), summary: [c.fragment.enabled ? 'Фрагментация' : 'Без фрагментации', c.fingerprintOverride ?? 'uTLS из конфига'].join(' · '), title: 'Обход блокировок', icon: Icons.shield_moon_rounded, children: [
            SwitchListTile(
              title: const Text('Фрагментация TLS ClientHello'),
              subtitle: Text(c.fragment.enabled ? c.fragment.toString() : 'выкл'),
              value: c.fragment.enabled,
              onChanged: (v) => app.updateCore(c.copyWith(fragment: c.fragment.copyWith(enabled: v))),
            ),
            ListTile(
              title: const Text('uTLS fingerprint'),
              trailing: DropdownButton<String>(
                value: c.fingerprintOverride ?? '',
                underline: const SizedBox.shrink(),
                onChanged: (v) => app.updateCore(CoreSettings.fromJson({...c.toJson(), 'fingerprintOverride': (v ?? '').isEmpty ? null : v}).copyWith(logPath: c.logPath)),
                items: [
                  for (final f in const ['', 'chrome', 'firefox', 'safari', 'ios', 'android', 'edge', 'randomized'])
                    DropdownMenuItem(value: f, child: Text(f.isEmpty ? 'Из конфига' : f)),
                ],
              ),
            ),
          ]),
          // ------------------------------------------------ routing
          _Section(id: 'routing', color: const Color(0xFF3F51B5), summary: app.activeRouting.name, title: context.tr('routing'), icon: Icons.alt_route_rounded, children: [
            RadioGroup<String>(
              groupValue: app.activeRoutingId,
              onChanged: (v) {
                if (v != null) app.setRouting(v);
              },
              child: Column(children: [
                for (final r in app.routings) RadioListTile<String>(value: r.id, title: Text(r.name), subtitle: Text(r.mode.name)),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.public_rounded),
              title: const Text('Обновить geo-файлы'),
              onTap: () async {
                final m = ScaffoldMessenger.of(context);
                try {
                  await GeoUpdater(app.assetDir).update(app.activeRouting, proxyPort: app.core.isConnected ? c.httpPort : null);
                  m.showSnackBar(const SnackBar(content: Text('Geo-файлы обновлены')));
                } on Object catch (e) {
                  m.showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                }
              },
            ),
          ]),
          // ------------------------------------------------ advanced
          _Section(id: 'adv', color: const Color(0xFF795548), summary: 'MTU ${c.tunMtu} · порты ${c.socksPort}/${c.httpPort}', title: 'Дополнительно', icon: Icons.tune_rounded, children: [
            SwitchListTile(
              title: const Text('Sniffing (определение доменов)'),
              subtitle: const Text('Нужен для маршрутизации по доменам'),
              value: c.sniffing,
              onChanged: (v) => app.updateCore(c.copyWith(sniffing: v)),
            ),
            if (c.mux)
              _sliderTile('Mux: потоков на соединение', c.muxConcurrency.toDouble(), 1, 32, (v) => app.updateCore(c.copyWith(muxConcurrency: v.round()))),
            ListTile(
              title: const Text('MTU туннеля'),
              subtitle: const Text('Меньше — стабильнее в мобильных сетях'),
              trailing: DropdownButton<int>(
                value: const [1280, 1380, 1400, 1450, 1500, 9000].contains(c.tunMtu) ? c.tunMtu : 1500,
                underline: const SizedBox.shrink(),
                onChanged: (v) => app.updateCore(c.copyWith(tunMtu: v)),
                items: [for (final m in const [1280, 1380, 1400, 1450, 1500, 9000]) DropdownMenuItem(value: m, child: Text('$m'))],
              ),
            ),
            ListTile(
              title: const Text('Адрес проверки (ping)'),
              subtitle: Text(c.testUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.edit_rounded),
              onTap: () => _pickTestUrl(context, app),
            ),
            ListTile(
              title: const Text('Порт SOCKS'),
              trailing: Text('${c.socksPort}', style: Theme.of(context).textTheme.titleMedium),
              onTap: () async {
                final v = await _askPort(context, 'Порт SOCKS', c.socksPort);
                if (v != null) await app.updateCore(c.copyWith(socksPort: v));
              },
            ),
            ListTile(
              title: const Text('Порт HTTP'),
              trailing: Text('${c.httpPort}', style: Theme.of(context).textTheme.titleMedium),
              onTap: () async {
                final v = await _askPort(context, 'Порт HTTP', c.httpPort);
                if (v != null) await app.updateCore(c.copyWith(httpPort: v));
              },
            ),
            ListTile(
              title: const Text('Уровень логов'),
              trailing: DropdownButton<String>(
                value: c.logLevel,
                underline: const SizedBox.shrink(),
                onChanged: (v) => app.updateCore(c.copyWith(logLevel: v)),
                items: [for (final l in const ['debug', 'info', 'warning', 'error', 'none']) DropdownMenuItem(value: l, child: Text(l))],
              ),
            ),
            ListTile(
              leading: Icon(Icons.restart_alt_rounded, color: Theme.of(context).colorScheme.error),
              title: const Text('Сбросить настройки подключения'),
              subtitle: const Text('Серверы и подписки не удаляются'),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Сбросить настройки?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('reset'))),
                    ],
                  ),
                );
                if (ok == true) await app.updateCore(const CoreSettings().copyWith(logPath: c.logPath));
              },
            ),
          ]),
          // ------------------------------------------------ data
          _Section(id: 'data', color: const Color(0xFF607D8B), summary: 'Логи, бэкап, подписки', title: 'Данные', icon: Icons.storage_rounded, children: [
            ListTile(leading: const Icon(Icons.article_outlined), title: Text(context.tr('logs')), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogsScreen()))),
            ListTile(leading: const Icon(Icons.backup_outlined), title: Text(context.tr('backup')), onTap: () => _backup(context, app)),
            ListTile(leading: const Icon(Icons.restore_rounded), title: Text(context.tr('restore')), onTap: () => _restore(context, app)),
            ListTile(
              leading: const Icon(Icons.playlist_add_check_rounded),
              title: const Text('Вернуть стандартные подписки'),
              subtitle: const Text('Белые и чёрные списки серверов'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final n = await app.restoreStockSubscriptions();
                messenger.showSnackBar(SnackBar(content: Text(n == 0 ? 'Все стандартные подписки уже добавлены' : 'Добавлено подписок: $n')));
              },
            ),
          ]),
    ];
  }

  Future<int?> _askPort(BuildContext context, String title, int current) async {
    final ctl = TextEditingController(text: '$current');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder(), helperText: '1024–65535'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(ctx.tr('save'))),
        ],
      ),
    );
    final n = int.tryParse(v ?? '');
    return n != null && n >= 1024 && n <= 65535 ? n : null;
  }

  Future<void> _pickTestUrl(BuildContext context, AppState app) async {
    const presets = [
      ('Cloudflare', 'https://cp.cloudflare.com/generate_204'),
      ('Google', 'https://www.gstatic.com/generate_204'),
      ('Apple', 'https://captive.apple.com/hotspot-detect.html'),
      ('Microsoft', 'https://www.msftconnecttest.com/connecttest.txt'),
    ];
    final c = app.coreSettings;
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (n, u) in presets)
            ListTile(
              leading: Icon(c.testUrl == u ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
              title: Text(n),
              subtitle: Text(u, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(ctx, u),
            ),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('Свой адрес…'),
            onTap: () async {
              final ctl = TextEditingController(text: c.testUrl);
              final u = await showDialog<String>(
                context: ctx,
                builder: (d) => AlertDialog(
                  title: const Text('Адрес проверки'),
                  content: TextField(controller: ctl, autofocus: true, keyboardType: TextInputType.url),
                  actions: [FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('OK'))],
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx, u);
            },
          ),
        ]),
      ),
    );
    if (v != null && (Uri.tryParse(v)?.hasScheme ?? false)) await app.updateCore(c.copyWith(testUrl: v));
  }

  Widget _sliderTile(String label, double value, double min, double max, ValueChanged<double> onChanged) => ListTile(
        title: Text('$label: ${value.round()}'),
        subtitle: Slider(min: min, max: max, divisions: (max - min).round(), value: value.clamp(min, max), onChanged: onChanged),
      );

  Future<String?> _askPassword(BuildContext context) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('password')),
        content: TextField(controller: c, obscureText: true, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _backup(BuildContext context, AppState app) async {
    final pw = await _askPassword(context);
    if (pw == null || pw.length < 6) return;
    final bytes = await BackupService(app.vault).export(pw);
    final path = await FilePicker.platform.saveFile(fileName: 'kuputun-backup.ktbk', bytes: bytes);
    if (path != null && !Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(bytes);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Бэкап сохранён')));
  }

  Future<void> _restore(BuildContext context, AppState app) async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    final f = res?.files.single;
    if (f == null || !context.mounted) return;
    final pw = await _askPassword(context);
    if (pw == null || !context.mounted) return;
    final m = ScaffoldMessenger.of(context);
    try {
      final data = f.bytes ?? Uint8List.fromList(await File(f.path!).readAsBytes());
      final n = await BackupService(app.vault).restore(data, pw);
      m.showSnackBar(SnackBar(content: Text('Восстановлено записей: $n. Перезапустите приложение.')));
    } on Object {
      m.showSnackBar(const SnackBar(content: Text('Неверный пароль или повреждённый файл')));
    }
  }
}

class _SplitTunnelScreen extends StatefulWidget {
  const _SplitTunnelScreen();
  @override
  State<_SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends State<_SplitTunnelScreen> {
  List<InstalledApp>? _apps;
  bool _showSystem = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    VpnPlatform().installedApps().then((a) {
      if (mounted) setState(() => _apps = a);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ui = app.ui;
    final list = (_apps ?? const <InstalledApp>[])
        .where((a) => (_showSystem || !a.system) && (a.label.toLowerCase().contains(_q) || a.package.contains(_q)))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Приложения'),
        actions: [
          IconButton(
            icon: Icon(_showSystem ? Icons.android : Icons.apps),
            tooltip: 'Системные',
            onPressed: () => setState(() => _showSystem = !_showSystem),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: FitSegmented<SplitMode>(
            segments: const [
              FitSegment(SplitMode.off, 'Выкл'),
              FitSegment(SplitMode.onlySelected, 'Только'),
              FitSegment(SplitMode.exceptSelected, 'Кроме'),
            ],
            selected: ui.splitMode,
            onChanged: (v) => app.updateUi(ui.copyWith(splitMode: v)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v.toLowerCase())),
        ),
        Expanded(
          child: _apps == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final a = list[i];
                    final on = ui.splitPackages.contains(a.package);
                    return CheckboxListTile(
                      value: on,
                      title: Text(a.label),
                      subtitle: Text(a.package, style: const TextStyle(fontSize: 11)),
                      onChanged: (v) => app.updateUi(ui.copyWith(
                        splitPackages: v == true ? [...ui.splitPackages, a.package] : ui.splitPackages.where((p) => p != a.package).toList(),
                      )),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// Material 3 settings group: tonal header + rounded card.
class _Section extends StatelessWidget {
  final String id;
  final String title;
  final String? summary;
  final IconData icon;
  final Color color;
  final List<Widget> children;
  const _Section({required this.id, required this.title, required this.icon, required this.children, this.summary, this.color = Colors.indigo});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary)),
          ]),
        ),
        Card(child: Column(children: children)),
      ]),
    );
  }
}

/// Settings home: brand header + grouped categories with live summaries.
class SettingsHub extends StatelessWidget {
  const SettingsHub({super.key});

  static const _groups = [
    ['conn', 'pick', 'ping'],
    ['home', 'look', 'tile'],
    ['bypass', 'routing', 'adv'],
    ['data'],
  ];

  @override
  Widget build(BuildContext context) {
    final sections = {for (final s in const SettingsScreen()._sections(context)) s.id: s};
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar.large(title: Text(context.tr('settings'))),
        SliverList.list(children: [
          const _BrandHeader(),
          for (final g in _groups)
            if (g.any(sections.containsKey))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final id in g)
                      if (sections[id] != null) _HubTile.section(context, sections[id]!),
                  ]),
                ),
              ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: _HubTile.raw(
                icon: Icons.info_outline_rounded,
                color: cs.primary,
                title: 'О приложении',
                summary: 'Версия, ядра, лицензия',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _HubTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? summary;
  final VoidCallback onTap;
  const _HubTile.raw({required this.icon, required this.color, required this.title, required this.summary, required this.onTap});

  _HubTile.section(BuildContext context, _Section s)
      : icon = s.icon,
        color = s.color,
        title = s.title,
        summary = s.summary,
        onTap = (() => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsSectionPage(id: s.id, title: s.title))));

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.22 : 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: dark ? Color.lerp(color, Colors.white, 0.35) : color, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: summary == null ? null : Text(summary!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.outline),
      onTap: onTap,
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final on = app.core.isConnected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF033FBA), Color(0xFF0186F2), Color(0xFF48E0EC)],
            ),
          ),
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset('assets/branding/logo_192.png', width: 56, height: 56),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('KupuTUN', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    Text('Версия ${app.fetcher.identity.appVersion}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(on ? Icons.verified_user_rounded : Icons.shield_outlined, size: 16, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(on ? 'Защищено' : 'Отключено', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// One settings category on its own screen.
class SettingsSectionPage extends StatelessWidget {
  final String id;
  final String title;
  const SettingsSectionPage({super.key, required this.id, required this.title});

  @override
  Widget build(BuildContext context) {
    final list = const SettingsScreen()._sections(context).where((s) => s.id == id);
    final s = list.isEmpty ? null : list.first;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar.large(title: Text(s?.title ?? title)),
        if (s != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverToBoxAdapter(
              child: Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: Column(children: s.children)),
            ),
          ),
      ]),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset('assets/branding/logo_192.png', width: 112, height: 112),
          ),
        ),
        const SizedBox(height: 16),
        Center(child: Text('KupuTUN', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
        Center(child: Text('Версия ${app.fetcher.identity.appVersion}', style: tt.bodyMedium)),
        const SizedBox(height: 24),
        Card(
          child: FutureBuilder<Map<String, String>>(
            future: () async {
              try {
                return await app.bridge.version();
              } on Object {
                return <String, String>{};
              }
            }(),
            builder: (ctx, snap) => Column(children: [
              const ListTile(leading: Icon(Icons.memory_rounded), title: Text('Ядра')),
              for (final e in (snap.data ?? const <String, String>{}).entries)
                ListTile(dense: true, title: Text(e.key), trailing: Text(e.value)),
              if (snap.data?.isEmpty ?? true) const ListTile(dense: true, title: Text('Xray-core · sing-box · tun2socks')),
            ]),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.gavel_rounded),
            title: const Text('Лицензии'),
            subtitle: const Text('GPL-3.0 и сторонние библиотеки'),
            onTap: () => showLicensePage(context: context, applicationName: 'KupuTUN', applicationVersion: app.fetcher.identity.appVersion),
          ),
        ),
      ]),
    );
  }
}
