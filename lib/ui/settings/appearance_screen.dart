import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/fit_segmented.dart';

/// Theme & colours: mode, Material You, 12 seed colours + custom hue,
/// AMOLED black, gradient background, compact list — with a live preview.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ui = app.ui;
    final cs = Theme.of(context).colorScheme;
    final dynamicSupported = Platform.isAndroid || Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar.large(title: Text(context.tr('themeAndColors'))),
        SliverList.list(children: [
          const _Preview(),
          _title(context, context.tr('themeMode')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FitSegmented<ThemeMode>(
              segments: const [
                FitSegment(ThemeMode.system, 'Авто', icon: Icons.brightness_auto_rounded),
                FitSegment(ThemeMode.light, 'Светлая', icon: Icons.light_mode_rounded),
                FitSegment(ThemeMode.dark, 'Тёмная', icon: Icons.dark_mode_rounded),
              ],
              selected: ui.themeMode,
              onChanged: (v) => app.updateUi(ui.copyWith(themeMode: v)),
            ),
          ),
          _title(context, context.tr('accentColor')),
          if (dynamicSupported)
            SwitchListTile(
              secondary: const Icon(Icons.wallpaper_rounded),
              title: const Text('Material You'),
              subtitle: Text(context.tr('dynamicColorDesc')),
              value: ui.dynamicColor,
              onChanged: (v) => app.updateUi(ui.copyWith(dynamicColor: v)),
            ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: ui.dynamicColor ? 0.4 : 1,
            child: IgnorePointer(
              ignoring: ui.dynamicColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final (col, name) in AppTheme.palette)
                    _Swatch(color: Color(col), name: name, selected: ui.accent == col, onTap: () => app.updateUi(ui.copyWith(accent: col))),
                  _Swatch(
                    color: AppTheme.palette.any((p) => p.$1 == ui.accent) ? cs.surfaceContainerHighest : Color(ui.accent),
                    name: context.tr('customColor'),
                    selected: !AppTheme.palette.any((p) => p.$1 == ui.accent),
                    icon: Icons.colorize_rounded,
                    onTap: () => _pickHue(context, app),
                  ),
                ]),
              ),
            ),
          ),
          _title(context, context.tr('appearance')),
          SwitchListTile(
            secondary: const Icon(Icons.contrast_rounded),
            title: Text(context.tr('amoled')),
            subtitle: Text(context.tr('amoledDesc')),
            value: ui.amoled,
            onChanged: (v) => app.updateUi(ui.copyWith(amoled: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.gradient_rounded),
            title: Text(context.tr('gradientBg')),
            value: ui.gradientBackground,
            onChanged: (v) => app.updateUi(ui.copyWith(gradientBackground: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.density_small_rounded),
            title: Text(context.tr('compactList')),
            value: ui.compactList,
            onChanged: (v) => app.updateUi(ui.copyWith(compactList: v)),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(context.tr('reset')),
              onPressed: () => app.updateUi(ui.copyWith(
                themeMode: ThemeMode.system,
                accent: const UiSettings().accent,
                dynamicColor: false,
                amoled: false,
                gradientBackground: true,
                compactList: false,
              )),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      ]),
    );
  }

  Widget _title(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  Future<void> _pickHue(BuildContext context, AppState app) async {
    var hue = HSVColor.fromColor(Color(app.ui.accent)).hue;
    final picked = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final color = HSVColor.fromAHSV(1, hue, 0.65, 0.85).toColor();
          return AlertDialog(
            title: Text(ctx.tr('customColor')),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 32, backgroundColor: color),
              const SizedBox(height: 16),
              Container(
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(colors: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 0.65, 0.85).toColor()]),
                ),
              ),
              Slider(min: 0, max: 360, value: hue, activeColor: color, onChanged: (v) => set(() => hue = v)),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, hue), child: Text(ctx.tr('apply'))),
            ],
          );
        },
      ),
    );
    if (picked != null) {
      final argb = HSVColor.fromAHSV(1, picked, 0.65, 0.85).toColor().toARGB32();
      await app.updateUi(app.ui.copyWith(accent: argb));
    }
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final String name;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;
  const _Swatch({required this.color, required this.name, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: color, brightness: Theme.of(context).brightness);
    return Tooltip(
      message: name,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 52,
          height: 52,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 3),
          ),
          child: ClipOval(
            child: icon != null
                ? ColoredBox(color: color, child: Icon(icon, size: 20))
                : Column(children: [
                    Expanded(child: ColoredBox(color: scheme.primary, child: const SizedBox.expand())),
                    Expanded(
                      child: Row(children: [
                        Expanded(child: ColoredBox(color: scheme.secondaryContainer, child: const SizedBox.expand())),
                        Expanded(child: ColoredBox(color: scheme.tertiary, child: const SizedBox.expand())),
                      ]),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// Mini home screen rendered with the current theme.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gradient = context.select<AppState, bool>((a) => a.ui.gradientBackground);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 170,
        clipBehavior: Clip.antiAlias,
        decoration: AppTheme.background(cs, enabled: gradient).copyWith(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(children: [
          const SizedBox(width: 24),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.alphaBlend(cs.primary.withValues(alpha: 0.1), cs.surfaceContainerLow),
              border: Border.all(color: cs.primary.withValues(alpha: 0.5), width: 2),
            ),
            child: Icon(Icons.power_settings_new_rounded, size: 40, color: cs.primary),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (flag, name, ping, sel) in const [('🇩🇪', 'Frankfurt', '42ms', true), ('🇳🇱', 'Amsterdam', '58ms', false), ('🇫🇮', 'Helsinki', '71ms', false)])
                Container(
                  margin: const EdgeInsets.only(bottom: 6, right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? cs.primary.withValues(alpha: 0.12) : cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Text(flag),
                    const SizedBox(width: 6),
                    Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
                    Text(ping, style: const TextStyle(fontSize: 11, color: Color(0xFF2EB872), fontWeight: FontWeight.w600)),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
