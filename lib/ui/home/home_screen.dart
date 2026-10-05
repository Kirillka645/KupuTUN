import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/models/server.dart';
import '../../core/models/subscription.dart';
import '../../tester/server_sorter.dart';
import '../import/add_sheet.dart';
import '../l10n.dart';
import '../servers/filter_sheet.dart';
import '../settings/settings_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_icons.dart';
import 'power_section.dart';
import 'subscription_group.dart';

/// Happ-style single screen: ⚙ … ＋ on top, big power button, then
/// collapsible subscription cards with their servers. On wide windows
/// (desktop / TV / tablets) the power pane and the list sit side by side.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch(AppState app) => setState(() {
        _searching = !_searching;
        if (!_searching) {
          _search.clear();
          app.setFilter(app.filter.copyWith(query: ''));
        }
      });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final msg = app.takeMessage();
    if (msg != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      });
    }

    final topBar = _TopBar(
      searching: _searching,
      search: _search,
      onSearchToggle: () => _toggleSearch(app),
      onQuery: (q) => app.setFilter(app.filter.copyWith(query: q)),
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: AppTheme.background(cs, enabled: app.ui.gradientBackground),
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 900;
            if (wide) {
              return Column(children: [
                topBar,
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 400,
                      child: LayoutBuilder(
                        builder: (context, pc) => SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: pc.maxHeight - 32),
                            child: const Center(child: PowerSection()),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: app.updateAllSubscriptions,
                        child: CustomScrollView(slivers: _listSlivers(context, app)),
                      ),
                    ),
                  ]),
                ),
              ]);
            }
            // Pinned: the power button stays put and only the server list
            // scrolls (needs enough height, otherwise fall back to one scroll).
            if (app.ui.pinPowerButton && c.maxHeight >= 560) {
              final btn = (c.maxHeight * 0.24).clamp(136.0, 210.0);
              return Column(children: [
                topBar,
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: PowerSection(buttonSize: btn, compact: true),
                ),
                Expanded(
                  child: _ListSheet(
                    child: RefreshIndicator(
                      onRefresh: app.updateAllSubscriptions,
                      child: CustomScrollView(slivers: _listSlivers(context, app)),
                    ),
                  ),
                ),
              ]);
            }
            return RefreshIndicator(
              onRefresh: app.updateAllSubscriptions,
              child: CustomScrollView(slivers: [
                SliverToBoxAdapter(child: topBar),
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: PowerSection()),
                ),
                ..._listSlivers(context, app),
              ]),
            );
          }),
        ),
      ),
    );
  }

  List<Widget> _listSlivers(BuildContext context, AppState app) {
    if (app.servers.isEmpty && app.subscriptions.isEmpty) {
      return const [SliverFillRemaining(hasScrollBody: false, child: _EmptyState())];
    }
    final manual = app.visibleServers();
    final groups = <(Subscription?, List<Server>)>[
      for (final sub in [...app.subscriptions]..sort((a, b) => a.order.compareTo(b.order))) (sub, app.visibleServers(subscriptionId: sub.id)),
      if (manual.isNotEmpty || app.servers.any((s) => s.subscriptionId == null)) (null, manual),
    ];
    return [
      SliverToBoxAdapter(child: _ListHeader(app: app)),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
        sliver: SliverList.separated(
          itemCount: groups.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => SubscriptionGroup(sub: groups[i].$1, servers: groups[i].$2),
        ),
      ),
    ];
  }
}

/// Rounded "sheet" that holds the scrolling server list under the pinned
/// power button.
class _ListSheet extends StatelessWidget {
  final Widget child;
  const _ListSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest.withValues(alpha: 0.55),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: child,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool searching;
  final TextEditingController search;
  final VoidCallback onSearchToggle;
  final ValueChanged<String> onQuery;
  const _TopBar({required this.searching, required this.search, required this.onSearchToggle, required this.onQuery});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final filterActive = context.select<AppState, bool>((a) => a.filter.isActive);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: SizedBox(
        height: 56,
        child: Row(children: [
          IconButton(
            tooltip: context.tr('settings'),
            icon: const Icon(Icons.settings_rounded, size: 28),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: searching
                  ? Padding(
                      key: const ValueKey('search'),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SearchBar(
                        controller: search,
                        autoFocus: true,
                        hintText: context.tr('search'),
                        elevation: const WidgetStatePropertyAll(0),
                        constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
                        leading: const Icon(Icons.search_rounded),
                        onChanged: onQuery,
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ),
          IconButton(
            tooltip: context.tr('search'),
            icon: Icon(searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: onSearchToggle,
          ),
          IconButton(
            tooltip: context.tr('sort'),
            icon: Badge(isLabelVisible: filterActive, smallSize: 8, child: const Icon(Icons.tune_rounded)),
            onPressed: () => _showSortSheet(context, app),
          ),
          IconButton(
            tooltip: context.tr('import'),
            icon: const Icon(Icons.add_rounded, size: 30),
            onPressed: () => showAddSheet(context),
          ),
        ]),
      ),
    );
  }
}

Future<void> _showSortSheet(BuildContext context, AppState app) => showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: app,
        child: Consumer<AppState>(
          builder: (ctx, app, _) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ctx.tr('sort'), style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (s, k, i) in const [
                  (SortBy.subscription, 'sortSubscription', Icons.format_list_numbered_rounded),
                  (SortBy.smart, 'sortSmart', Icons.auto_awesome_rounded),
                  (SortBy.ping, 'sortPing', Icons.network_ping_rounded),
                  (SortBy.speed, 'sortSpeed', Icons.speed_rounded),
                  (SortBy.jitter, 'sortJitter', Icons.show_chart_rounded),
                  (SortBy.country, 'sortCountry', Icons.flag_rounded),
                  (SortBy.name, 'sortName', Icons.sort_by_alpha_rounded),
                ])
                  ChoiceChip(
                    avatar: Icon(i, size: 18),
                    label: Text(ctx.tr(k)),
                    selected: app.sortBy == s,
                    onSelected: (_) => app.setSort(s),
                  ),
              ]),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.filter_list_rounded),
                    label: Text(ctx.tr('filter')),
                    onPressed: () async {
                      final f = await showFilterSheet(ctx, app.filter, app.knownCountries);
                      if (f != null) app.setFilter(f);
                    },
                  ),
                ),
                if (app.filter.isActive) ...[
                  const SizedBox(width: 8),
                  TextButton(onPressed: () => app.setFilter(const ServerFilter()), child: Text(ctx.tr('reset'))),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );

/// "⏲ Пинг всех · 12/40" on the left, "Скрыть всё" on the right (Happ).
class _ListHeader extends StatelessWidget {
  final AppState app;
  const _ListHeader({required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = app.progress;
    final allPing = app.testing && app.pingingGroup == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Column(children: [
        Row(children: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant, visualDensity: VisualDensity.compact),
            icon: SpeedometerIcon(active: allPing, size: 20),
            label: Text(allPing && p != null ? '${p.done}/${p.total}' : context.tr('pingAll')),
            onPressed: app.testing ? app.cancelTests : () => app.testAll(),
          ),
          const Spacer(),
          if (app.subscriptions.isNotEmpty)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant, visualDensity: VisualDensity.compact),
              onPressed: () => app.setAllCollapsed(!app.allCollapsed),
              child: Text(context.tr(app.allCollapsed ? 'showAll' : 'hideAll')),
            ),
        ]),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: app.testing && p != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: LinearProgressIndicator(value: p.fraction, borderRadius: BorderRadius.circular(4)),
                )
              : const SizedBox(height: 0),
        ),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
          child: Icon(Icons.dns_rounded, size: 44, color: cs.onPrimaryContainer),
        ),
        const SizedBox(height: 16),
        Text(context.tr('noServers'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: Text(context.tr('import')),
          onPressed: () => showAddSheet(context),
        ),
      ]),
    );
  }
}
