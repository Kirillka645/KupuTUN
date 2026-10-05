import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import 'home/home_screen.dart';
import 'l10n.dart';
import 'theme/app_theme.dart';

/// Single-screen layout like Happ: everything (power button + subscription
/// groups with servers) lives on Home; settings open from the ⚙ icon.
class KupuTunApp extends StatelessWidget {
  const KupuTunApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ui = context.select<AppState, UiSettings>((a) => a.ui);
    return DynamicColorBuilder(
      builder: (light, dark) => MaterialApp(
        title: 'KupuTUN',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(ui, Brightness.light, dynamicScheme: light),
        darkTheme: AppTheme.build(ui, Brightness.dark, dynamicScheme: dark),
        themeMode: ui.themeMode,
        themeAnimationDuration: const Duration(milliseconds: 300),
        locale: ui.locale == null ? null : Locale(ui.locale!),
        supportedLocales: L10n.supported,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeScreen(),
      ),
    );
  }
}
