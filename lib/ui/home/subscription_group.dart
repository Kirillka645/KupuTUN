import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../core/models/server.dart';
import '../../core/models/subscription.dart';
import '../../core/models/test_result.dart';
import '../../core/util/country.dart';
import '../l10n.dart';
import '../servers/server_details_sheet.dart';
import '../servers/server_editor_screen.dart';
import '../widgets/animated_icons.dart';
import '../widgets/format.dart';

/// One Happ-style card: header (⌄ title/date ⟳ ⏲ ⋯), info strip
/// (ⓘ traffic · expires · 🔗), provider message, then the server rows.
/// `sub == null` is the "My servers" group for manually added servers.
class SubscriptionGroup extends StatelessWidget {
  final Subscription? sub;
  final List<Server> servers;
  const SubscriptionGroup({super.key, required this.sub, required this.servers});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = sub;
    final collapsed = s?.collapsed ?? false;
    final groupId = s?.id ?? '';
    final pinging = app.testing && app.pingingGroup == groupId;
    final updating = s != null && app.updatingSubs.contains(s.id);
    final cs = Theme.of(context).colorScheme;
    final best = app.autoPickPreview;

    return Card(
      color: cs.surfaceContainerLow.withValues(alpha: app.ui.gradientBackground ? 0.92 : 1),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ---------------------------------------------------------- header
        InkWell(
          onTap: s == null ? null : () => app.toggleCollapsed(s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 2, 6),
            child: LayoutBuilder(builder: (context, c) {
              // On narrow phones the ⟳/⏲ buttons move into the ⋯ menu so the
              // title keeps enough room.
              final narrow = c.maxWidth < 330;
              final tt = Theme.of(context).textTheme;
              return Row(children: [
                SizedBox(
                  width: 36,
                  child: s == null
                      ? Icon(Icons.folder_rounded, color: cs.onSurfaceVariant)
                      : AnimatedRotation(
                          turns: collapsed ? 0 : 0.5,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Icons.keyboard_arrow_up_rounded, color: cs.onSurfaceVariant),
                        ),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      s?.title ?? context.tr('myServers'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s == null
                          ? '${servers.length} ${context.tr('serversShort')}'
                          : [
                              if (updating) '…' else if (s.lastUpdated != null) _shortDate(context, s.lastUpdated!),
                              '${app.servers.where((e) => e.subscriptionId == s.id).length} ${context.tr('serversShort')}',
                            ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ]),
                ),
                if (s != null && !narrow)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: context.tr('update'),
                    onPressed: updating ? null : () => app.updateSubscription(s),
                    icon: SpinningSyncIcon(active: updating, color: cs.primary),
                  ),
                if (!narrow || pinging)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: context.tr('pingAll'),
                    onPressed: pinging ? app.cancelTests : (app.testing ? null : () => app.testGroup(s?.id)),
                    icon: SpeedometerIcon(active: pinging, color: cs.primary),
                  ),
                _GroupMenu(sub: s),
              ]);
            }),
          ),
        ),
        // ---------------------------------------------------------- info strip
        if (s != null && (s.userInfo != null || s.supportUrl != null || s.webPageUrl != null)) _InfoStrip(sub: s),
        // ---------------------------------------------------------- provider message
        if (s?.announce != null && s!.announce!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Text(s.announce!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ),
        // ---------------------------------------------------------- servers
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: collapsed
              ? const SizedBox(width: double.infinity)
              : Column(children: [
                  if (servers.isEmpty && s != null && !updating)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        app.filter.isActive ? context.tr('nothingFound') : context.tr('emptySubscription'),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  for (final server in servers)
                    ServerRow(
                      server: server,
                      result: app.results[server.id],
                      pending: app.pendingPing.contains(server.id),
                      selected: app.selected?.id == server.id,
                      connected: app.core.isConnected && app.core.current?.id == server.id,
                      best: best?.id == server.id,
                      compact: app.ui.compactList,
                    ),
                  const SizedBox(height: 4),
                ]),
        ),
      ]),
    );
  }

  /// "15:59" today, "вчера 15:59", "05.10 15:59" this year, else full date.
  static String _shortDate(BuildContext context, DateTime d) {
    final l = d.toLocal();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(l.hour)}:${two(l.minute)}';
    final day = DateTime(l.year, l.month, l.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return time;
    if (day == today.subtract(const Duration(days: 1))) return '${context.tr('yesterday')} $time';
    if (l.year == now.year) return '${two(l.day)}.${two(l.month)} $time';
    return '${two(l.day)}.${two(l.month)}.${l.year}';
  }

  static String _dateTime(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }
}

class _InfoStrip extends StatelessWidget {
  final Subscription sub;
  const _InfoStrip({required this.sub});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = sub.userInfo;
    final now = DateTime.now().toUtc();
    final soon = info != null && (info.expiresWithin(const Duration(days: 3), now) || info.isExpired(now));
    final link = sub.webPageUrl ?? sub.supportUrl;
    final total = info == null ? null : (info.total > 0 ? formatBytes(info.total) : '∞');
    return Container(
      color: cs.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.info_outline_rounded, size: 20, color: cs.primary),
          onPressed: () => _showInfo(context),
        ),
        if (info != null)
          Expanded(
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(alignment: Alignment.center, children: [
                  if (info.usedFraction != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: info.usedFraction,
                        child: Container(color: (info.usedFraction! > 0.9 ? cs.error : cs.primary).withValues(alpha: 0.25)),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('${formatBytes(info.used)} / $total', maxLines: 1, style: Theme.of(context).textTheme.labelSmall),
                    ),
                  ),
                ]),
              ),
            ),
          )
        else
          const Spacer(),
        if (info?.expire != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.event_rounded, size: 14, color: soon ? cs.error : cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '${context.tr('until')} ${formatDate(info!.expire!)}',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: soon ? cs.error : null,
                        fontWeight: soon ? FontWeight.bold : null,
                      ),
                ),
              ]),
            ),
          ),
        ],
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: link == null ? null : context.tr('openSite'),
          icon: Icon(Icons.link_rounded, size: 20, color: link == null ? cs.outline : cs.primary),
          onPressed: link == null ? null : () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
        ),
      ]),
    );
  }

  void _showInfo(BuildContext context) {
    final info = sub.userInfo;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline_rounded),
        title: Text(sub.title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (info != null) ...[
            Text('↑ ${formatBytes(info.upload)}   ↓ ${formatBytes(info.download)}'),
            Text('${ctx.tr('trafficLeft')}: ${info.remaining == null ? ctx.tr('unlimited') : formatBytes(info.remaining!)}'),
            if (info.expire != null) Text('${ctx.tr('expires')}: ${formatDate(info.expire!)}'),
            const SizedBox(height: 8),
          ],
          if (sub.lastUpdated != null) Text('${ctx.tr('updated')}: ${SubscriptionGroup._dateTime(sub.lastUpdated!)}'),
          Text('${ctx.tr('autoUpdate')}: ${sub.autoUpdate ? '${sub.updateInterval.inHours} h' : '—'}'),
          const SizedBox(height: 8),
          SelectableText(sub.url, style: Theme.of(ctx).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: sub.url));
              Navigator.pop(ctx);
            },
            child: Text(ctx.tr('copyUrl')),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }
}

class _GroupMenu extends StatelessWidget {
  final Subscription? sub;
  const _GroupMenu({required this.sub});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final s = sub;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (a) async {
        switch (a) {
          case 'update':
            if (s != null) await app.updateSubscription(s);
          case 'ping':
            await app.testGroup(s?.id);
          case 'best':
            final list = app.servers.where((e) => e.subscriptionId == s?.id).toList();
            final b = app.bestOf(list, app.ui.serverPick == ServerPick.ping ? ServerPick.ping : ServerPick.smart);
            if (b != null) await app.select(b);
          case 'copy':
            if (s != null) await Clipboard.setData(ClipboardData(text: s.url));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
          case 'rename':
            if (s != null && context.mounted) await _rename(context, app, s);
          case 'delete':
            if (s != null && context.mounted) await _confirmDelete(context, app, s);
        }
      },
      itemBuilder: (ctx) => [
        if (s != null) _item('update', Icons.sync_rounded, ctx.tr('update')),
        _item('ping', Icons.speed_rounded, ctx.tr('pingAll')),
        _item('best', Icons.auto_awesome_rounded, ctx.tr('selectBest')),
        if (s != null) ...[
          _item('copy', Icons.copy_rounded, ctx.tr('copyUrl')),
          _item('rename', Icons.edit_rounded, ctx.tr('rename')),
          const PopupMenuDivider(),
          _item('delete', Icons.delete_outline_rounded, ctx.tr('delete')),
        ],
      ],
    );
  }

  PopupMenuItem<String> _item(String v, IconData i, String t) =>
      PopupMenuItem(value: v, child: Row(children: [Icon(i, size: 20), const SizedBox(width: 12), Text(t)]));

  Future<void> _rename(BuildContext context, AppState app, Subscription s) async {
    final c = TextEditingController(text: s.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('rename')),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(ctx.tr('save'))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await app.renameSubscription(s, name);
  }

  Future<void> _confirmDelete(BuildContext context, AppState app, Subscription s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: Text('${ctx.tr('delete')} «${s.title}»?'),
        content: Text(ctx.tr('deleteSubHint')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('delete')),
          ),
        ],
      ),
    );
    if (ok == true) await app.deleteSubscription(s);
  }
}

/// Server row like Happ: ◉ radio · flag · name/protocol · ping · ›
class ServerRow extends StatelessWidget {
  final Server server;
  final TestResult? result;
  final bool pending;
  final bool selected;
  final bool connected;
  final bool best;
  final bool compact;
  const ServerRow({
    super.key,
    required this.server,
    required this.result,
    required this.pending,
    required this.selected,
    required this.connected,
    required this.best,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    final r = result;
    final dead = r != null && !r.isAlive;
    final cc = r?.exitCountry ?? server.countryCode;
    final showFlag = context.select<AppState, bool>((a) => a.ui.showFlags);
    final dotColor = connected ? const Color(0xFF2EB872) : cs.primary;
    final subtitle = [
      server.protocol.label,
      if (server.transport != 'tcp') server.transport,
      if (server.security == 'reality') 'Reality',
      if (r?.downloadMbps != null) '↓ ${formatMbps(r!.downloadMbps)}',
    ].join(' · ');

    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: () => app.select(server),
        onLongPress: () => _menu(context, app),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, compact ? 4 : 8, 0, compact ? 4 : 8),
          child: Row(children: [
            // radio
            SizedBox(
              width: 28,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? dotColor.withValues(alpha: 0.18) : Colors.transparent,
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: selected ? 10 : 0,
                      height: selected ? 10 : 0,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                    ),
                  ),
                ),
              ),
            ),
            // flag
            if (showFlag) ...[
              Opacity(
                opacity: dead ? 0.4 : 1,
                child: Text(CountryDetector.flagOf(cc), style: TextStyle(fontSize: compact ? 22 : 26)),
              ),
              const SizedBox(width: 10),
            ],
            // name + protocol
            Expanded(
              child: Opacity(
                opacity: dead ? 0.5 : 1,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (server.favorite)
                      const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.star_rounded, size: 16, color: Colors.amber)),
                    Flexible(
                      child: Text(
                        showFlag ? displayServerName(server.name) : server.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (compact ? Theme.of(context).textTheme.bodyMedium : Theme.of(context).textTheme.bodyLarge)
                            ?.copyWith(fontWeight: FontWeight.w500, fontSize: compact ? 14 : 15),
                      ),
                    ),
                    if (best) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: context.tr('bestServer'),
                        child: Icon(Icons.auto_awesome_rounded, size: 14, color: cs.tertiary),
                      ),
                    ],
                  ]),
                  if (!compact)
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            // ping
            SizedBox(
              width: 54,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: pending
                      ? const SizedBox(key: ValueKey('p'), width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(
                          dead ? 'timeout' : (r?.medianMs == null ? 'n/a' : '${r!.medianMs}ms'),
                          key: ValueKey('${r?.medianMs}-$dead'),
                          style: TextStyle(
                            color: dead ? cs.error : (r?.medianMs == null ? cs.onSurfaceVariant : pingColor(r!.medianMs)),
                            fontWeight: r?.medianMs == null ? FontWeight.w400 : FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                  ),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 40),
              padding: EdgeInsets.zero,
              icon: Icon(Icons.chevron_right_rounded, color: cs.outline),
              onPressed: () => showServerDetails(context, server),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, AppState app) async {
    unawaited(HapticFeedback.selectionClick());
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Text(CountryDetector.flagOf(result?.exitCountry ?? server.countryCode), style: const TextStyle(fontSize: 28)),
            title: Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(server.protocol.label),
          ),
          const Divider(),
          ListTile(leading: const Icon(Icons.power_settings_new_rounded), title: Text(ctx.tr('connect')), onTap: () => Navigator.pop(ctx, 'connect')),
          ListTile(
            leading: Icon(server.favorite ? Icons.star_rounded : Icons.star_outline_rounded),
            title: Text(ctx.tr(server.favorite ? 'unfavorite' : 'favorite')),
            onTap: () => Navigator.pop(ctx, 'fav'),
          ),
          ListTile(leading: const Icon(Icons.speed_rounded), title: Text(ctx.tr('pingOne')), onTap: () => Navigator.pop(ctx, 'ping')),
          ListTile(leading: const Icon(Icons.info_outline_rounded), title: Text(ctx.tr('details')), onTap: () => Navigator.pop(ctx, 'details')),
          ListTile(leading: const Icon(Icons.edit_rounded), title: Text(ctx.tr('edit')), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: Theme.of(ctx).colorScheme.error),
            title: Text(ctx.tr('delete'), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (!context.mounted) return;
    switch (a) {
      case 'connect':
        await app.select(server);
        if (!app.core.isConnected) await app.toggleConnection();
      case 'fav':
        await app.toggleFavorite(server);
      case 'ping':
        await app.testAll(only: [server]);
      case 'details':
        await showServerDetails(context, server);
      case 'edit':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ServerEditorScreen(initial: server)));
      case 'delete':
        await app.deleteServer(server);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${context.tr('deleted')}: ${server.name}')));
    }
  }
}
