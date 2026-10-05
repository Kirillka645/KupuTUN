import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import '../../app/app_state.dart';

/// Material 3 theme built from one seed colour (or the system's dynamic
/// palette). Everything visual derives from the ColorScheme, so changing the
/// accent restyles the whole app consistently, Happ-style dark purple included.
class AppTheme {
  /// Curated seeds; first one is the default "Happ-like" indigo.
  static const palette = <(int, String)>[
    (0xFF5B5BD6, 'Индиго'),
    (0xFF2E7DFF, 'Синий'),
    (0xFF00A3BF, 'Бирюзовый'),
    (0xFF00A884, 'Изумрудный'),
    (0xFF4CAF50, 'Зелёный'),
    (0xFF9E9D24, 'Оливковый'),
    (0xFFFFA000, 'Янтарный'),
    (0xFFFF6D00, 'Оранжевый'),
    (0xFFE53935, 'Красный'),
    (0xFFE91E63, 'Розовый'),
    (0xFF9C27B0, 'Фиолетовый'),
    (0xFF607D8B, 'Графит'),
  ];

  static ThemeData build(UiSettings ui, Brightness b, {ColorScheme? dynamicScheme}) {
    var cs = (ui.dynamicColor && dynamicScheme != null)
        ? dynamicScheme.harmonized()
        : ColorScheme.fromSeed(seedColor: Color(ui.accent), brightness: b);
    if (b == Brightness.dark && ui.amoled) {
      cs = cs.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0C),
        surfaceContainer: const Color(0xFF121216),
        surfaceContainerHigh: const Color(0xFF1A1A20),
        surfaceContainerHighest: const Color(0xFF222229),
      );
    }
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      brightness: b,
      visualDensity: Platform.isWindows || Platform.isLinux || Platform.isMacOS ? VisualDensity.compact : VisualDensity.standard,
      fontFamilyFallback: const ['Noto Sans', 'Noto Sans Arabic', 'Noto Sans SC', 'Noto Color Emoji'],
      scaffoldBackgroundColor: cs.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: cs.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: cs.surfaceContainerLow,
        shape: shape,
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: cs.surfaceContainerLow,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      segmentedButtonTheme: const SegmentedButtonThemeData(style: ButtonStyle(visualDensity: VisualDensity.compact)),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }

  /// Soft two-tone gradient behind the home screen (Happ look), derived
  /// from the scheme so it follows the accent and light/dark mode.
  static BoxDecoration background(ColorScheme cs, {required bool enabled}) {
    if (!enabled) return BoxDecoration(color: cs.surface);
    final dark = cs.brightness == Brightness.dark;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(cs.primary.withValues(alpha: dark ? 0.22 : 0.07), cs.surface),
          cs.surface,
          Color.alphaBlend(cs.tertiary.withValues(alpha: dark ? 0.14 : 0.05), cs.surface),
        ],
        stops: const [0, 0.55, 1],
      ),
    );
  }
}
