import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../core/engine/core_manager.dart';
import '../../core/util/country.dart';
import '../l10n.dart';
import '../servers/server_details_sheet.dart';
import '../widgets/format.dart';

const _green = Color(0xFF2EB872);

/// Big power button with rings, status, timer, current server, auto-pick
/// mode chip and live traffic. Shared by the phone and wide layouts.
class PowerSection extends StatelessWidget {
  /// Diameter of the power button (rings included).
  final double buttonSize;

  /// Pinned header mode: tighter spacing, traffic shown inside the server card.
  final bool compact;
  const PowerSection({super.key, this.buttonSize = 236, this.compact = false});

  static Future<void> onPower(BuildContext context, AppState app) async {
    if (app.ui.haptics) unawaited(HapticFeedback.mediumImpact());
    if (app.core.isConnected && app.ui.confirmDisconnect) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.power_settings_new_rounded),
          title: Text(ctx.tr('disconnectQ')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('disconnect'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    await app.toggleConnection();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final core = app.core;
    final server = core.current ?? app.selected;
    final sub = server == null ? null : app.subscriptionOf(server);
    final gap = compact ? 8.0 : 12.0;
    final traffic = app.ui.showTraffic && core.isConnected;
    return Column(children: [
      SizedBox(height: compact ? 0 : 8),
      _PowerButton(
        state: core.state,
        picking: app.picking,
        size: buttonSize,
        onTap: () => onPower(context, app),
      ),
      SizedBox(height: gap),
      if (compact)
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [_StatusLine(app: app), _PickModeChip(app: app)],
        )
      else ...[
        _StatusLine(app: app),
        SizedBox(height: gap),
        _PickModeChip(app: app),
      ],
      if (server != null) ...[
        SizedBox(height: gap),
        _CurrentServerTile(app: app, traffic: compact && traffic),
      ],
      if (!compact)
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: traffic ? Padding(padding: EdgeInsets.only(top: gap), child: _TrafficRow(core: core)) : const SizedBox(width: double.infinity),
        ),
      if (sub?.announce != null && sub!.announce!.isNotEmpty && sub.userInfo == null) ...[
        const SizedBox(height: 12),
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(leading: const Icon(Icons.campaign_outlined), title: Text(sub.announce!)),
        ),
      ],
      if (sub?.userInfo != null && sub!.userInfo!.isExpired(DateTime.now().toUtc()) && (sub.webPageUrl ?? sub.supportUrl) != null) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.autorenew_rounded),
          label: Text(context.tr('renew')),
          onPressed: () => launchUrl(Uri.parse(sub.webPageUrl ?? sub.supportUrl!), mode: LaunchMode.externalApplication),
        ),
      ],
    ]);
  }
}

class _PowerButton extends StatefulWidget {
  final VpnState state;
  final bool picking;
  final double size;
  final VoidCallback onTap;
  const _PowerButton({required this.state, required this.picking, required this.size, required this.onTap});
  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton> with TickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  Timer? _tick;
  bool _pressed = false;

  bool get _busy => widget.picking || widget.state == VpnState.connecting || widget.state == VpnState.disconnecting;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_PowerButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_busy) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
    if (widget.state == VpnState.connected) {
      if (!_pulse.isAnimating) _pulse.repeat();
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _pulse.stop();
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final connected = widget.state == VpnState.connected;
    final accent = connected ? _green : cs.primary;
    final label = widget.picking
        ? context.tr('pickingServer')
        : switch (widget.state) {
            VpnState.connected => context.tr('disconnect'),
            VpnState.connecting => context.tr('connecting'),
            VpnState.disconnecting => context.tr('disconnecting'),
            _ => context.tr('connect'),
          };
    final size = widget.size;
    final small = size < 190;
    final core = context.read<AppState>().core;
    return Semantics(
      button: true,
      label: label,
      child: FocusableActionDetector(
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap())},
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.state == VpnState.disconnecting ? null : widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1,
            duration: const Duration(milliseconds: 120),
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(alignment: Alignment.center, children: [
                // outer pulse (connected)
                AnimatedBuilder(
                  // _pulse is stopped while connecting/disconnecting, so the
                  // spinning arc needs _spin too — otherwise the ring is painted
                  // once and stays frozen for the whole connect.
                  animation: Listenable.merge([_pulse, _spin]),
                  builder: (_, __) => CustomPaint(
                    size: Size.square(size),
                    painter: _RingsPainter(
                      color: accent,
                      track: cs.outlineVariant,
                      pulse: connected ? _pulse.value : null,
                      spin: _busy ? _spin.value : null,
                    ),
                  ),
                ),
                // middle disk
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: size * 0.74,
                  height: size * 0.74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.alphaBlend(accent.withValues(alpha: connected ? 0.18 : 0.10), cs.surfaceContainerLow),
                    boxShadow: [
                      BoxShadow(color: accent.withValues(alpha: connected ? 0.35 : 0.15), blurRadius: connected ? 40 : 24),
                    ],
                  ),
                ),
                // inner button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: size * 0.56,
                  height: size * 0.56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: connected
                          ? [_green, Color.lerp(_green, Colors.black, 0.25)!]
                          : [cs.surfaceContainerHighest, cs.surfaceContainerHigh],
                    ),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        Icons.power_settings_new_rounded,
                        key: ValueKey(connected),
                        size: size * 0.22,
                        color: connected ? Colors.white : accent,
                      ),
                    ),
                    SizedBox(height: small ? 2 : 4),
                    Text(
                      label.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            letterSpacing: small ? 0.6 : 1.1,
                            fontSize: small ? 9.5 : null,
                            color: connected ? Colors.white : cs.onSurfaceVariant,
                          ),
                    ),
                    if (connected)
                      Text(
                        formatDuration(core.sessionDuration),
                        style: (small ? Theme.of(context).textTheme.titleSmall : Theme.of(context).textTheme.titleMedium)?.copyWith(
                              color: Colors.white,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                      ),
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

class _RingsPainter extends CustomPainter {
  final Color color;
  final Color track;
  final double? pulse; // 0..1 when connected
  final double? spin; // 0..1 when busy
  _RingsPainter({required this.color, required this.track, this.pulse, this.spin});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    // thin track ring
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = track.withValues(alpha: 0.6),
    );
    // gradient arc (always a hint of accent, like Happ)
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)],
        transform: GradientRotation((spin ?? 0) * 2 * math.pi),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    final start = -math.pi / 2 + (spin ?? 0) * 2 * math.pi;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, spin != null ? math.pi * 1.2 : math.pi * 2, false, arc);
    // expanding pulse
    if (pulse != null) {
      final p = pulse!;
      canvas.drawCircle(
        c,
        r * (0.74 + 0.26 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: (1 - p) * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter o) => o.pulse != pulse || o.spin != spin || o.color != color || o.track != track;
}

class _StatusLine extends StatelessWidget {
  final AppState app;
  const _StatusLine({required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final core = app.core;
    final (text, color, icon) = app.picking
        ? (context.tr('pickingServer'), theme.colorScheme.primary, Icons.auto_awesome_rounded)
        : switch (core.state) {
            VpnState.connected => (context.tr('connected'), _green, Icons.verified_user_rounded),
            VpnState.connecting => (context.tr('connecting'), theme.colorScheme.primary, Icons.sync_rounded),
            VpnState.disconnecting => (context.tr('disconnecting'), theme.colorScheme.primary, Icons.sync_rounded),
            VpnState.error => (core.error ?? context.tr('error'), theme.colorScheme.error, Icons.error_outline_rounded),
            VpnState.disconnected => (context.tr('notConnected'), theme.colorScheme.onSurfaceVariant, Icons.shield_outlined),
          };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Row(
        key: ValueKey(text),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(text, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: color))),
        ],
      ),
    );
  }
}

/// "✨ Авто: Smart Score" — tap to change how the power button picks a server.
class _PickModeChip extends StatelessWidget {
  final AppState app;
  const _PickModeChip({required this.app});

  @override
  Widget build(BuildContext context) {
    final mode = app.ui.serverPick;
    final (icon, key) = switch (mode) {
      ServerPick.manual => (Icons.touch_app_rounded, 'pickManual'),
      ServerPick.smart => (Icons.auto_awesome_rounded, 'pickSmart'),
      ServerPick.ping => (Icons.network_ping_rounded, 'pickPing'),
    };
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(mode == ServerPick.manual ? context.tr(key) : '${context.tr('autoPick')}: ${context.tr(key)}'),
      onPressed: () => showPickModeSheet(context),
    );
  }
}

Future<void> showPickModeSheet(BuildContext context) {
  final app = context.read<AppState>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => ChangeNotifierProvider.value(
      value: app,
      child: Consumer<AppState>(
        builder: (ctx, app, _) => SafeArea(
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(ctx.tr('pickTitle'), style: Theme.of(ctx).textTheme.titleLarge),
            ),
            RadioGroup<ServerPick>(
              groupValue: app.ui.serverPick,
              onChanged: (v) => app.updateUi(app.ui.copyWith(serverPick: v)),
              child: Column(children: [
                for (final (v, k, d) in const [
                  (ServerPick.smart, 'pickSmart', 'pickSmartDesc'),
                  (ServerPick.ping, 'pickPing', 'pickPingDesc'),
                  (ServerPick.manual, 'pickManual', 'pickManualDesc'),
                ])
                  RadioListTile<ServerPick>(value: v, title: Text(ctx.tr(k)), subtitle: Text(ctx.tr(d))),
              ]),
            ),
            SwitchListTile(
              title: Text(ctx.tr('pickInSub')),
              value: app.ui.pickInSubscription,
              onChanged: app.ui.serverPick == ServerPick.manual ? null : (v) => app.updateUi(app.ui.copyWith(pickInSubscription: v)),
            ),
            const SizedBox(height: 8),
          ])),
        ),
      ),
    ),
  );
}

class _CurrentServerTile extends StatelessWidget {
  final AppState app;
  final bool traffic;
  const _CurrentServerTile({required this.app, this.traffic = false});

  @override
  Widget build(BuildContext context) {
    final s = app.core.current ?? app.selected!;
    final r = app.results[s.id];
    final ping = app.core.isConnected ? (app.core.livePingMs ?? r?.medianMs) : r?.medianMs;
    final cc = r?.exitCountry ?? s.countryCode;
    final cs = Theme.of(context).colorScheme;
    final core = app.core;
    final tt = Theme.of(context).textTheme;
    Widget rate(IconData i, Color c, double v) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 15, color: c),
          const SizedBox(width: 3),
          Text(formatRate(v), style: tt.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]);
    final tile = ListTile(
        dense: traffic,
        visualDensity: traffic ? VisualDensity.compact : null,
        leading: Text(CountryDetector.flagOf(cc), style: TextStyle(fontSize: traffic ? 26 : 30)),
        title: Text(displayServerName(s.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            s.protocol.label,
            if (app.core.isBalanced) context.tr('autoSwitch'),
            if (r?.downloadMbps != null) '↓ ${formatMbps(r!.downloadMbps)}',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          ping == null ? 'n/a' : '$ping ms',
          style: TextStyle(color: pingColor(ping), fontWeight: FontWeight.w700, fontSize: 15),
        ),
        onTap: () => showServerDetails(context, s),
      );
    return Card(
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow.withValues(alpha: 0.9),
      child: !traffic
          ? tile
          : Column(mainAxisSize: MainAxisSize.min, children: [
              tile,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(children: [
                  rate(Icons.arrow_upward_rounded, Colors.orange, core.upRate),
                  const SizedBox(width: 16),
                  rate(Icons.arrow_downward_rounded, Colors.blue, core.downRate),
                  const Spacer(),
                  Text(formatBytes(core.upBytes + core.downBytes), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
    );
  }
}

class _TrafficRow extends StatelessWidget {
  final CoreManager core;
  const _TrafficRow({required this.core});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget cell(IconData i, double rate, int total, Color c) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              child: Row(children: [
                CircleAvatar(radius: 16, backgroundColor: c.withValues(alpha: 0.15), child: Icon(i, size: 18, color: c)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(formatRate(rate), style: t.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    Text(formatBytes(total), style: t.bodySmall),
                  ]),
                ),
              ]),
            ),
          ),
        );
    return Row(children: [
      cell(Icons.arrow_upward_rounded, core.upRate, core.upBytes, Colors.orange),
      const SizedBox(width: 8),
      cell(Icons.arrow_downward_rounded, core.downRate, core.downBytes, Colors.blue),
    ]);
  }
}
