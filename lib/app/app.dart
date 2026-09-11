import 'package:cristo_es_el_salvador/app/global_error_listener.dart';
import 'package:cristo_es_el_salvador/app/router/app_router.dart';
import 'package:cristo_es_el_salvador/core/config/app_flavor.dart';
import 'package:cristo_es_el_salvador/core/config/env_config.dart';
import 'package:cristo_es_el_salvador/core/design/app_theme.dart';
import 'package:cristo_es_el_salvador/core/design/theme_mode_notifier.dart';
import 'package:cristo_es_el_salvador/core/i18n/locale_notifier.dart';
import 'package:cristo_es_el_salvador/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeNotifierProvider);
    // `null` = seguir el idioma del sistema; MaterialApp ya sabe resolver
    // eso solo contra `supportedLocales` cuando `locale` es null.
    final locale = ref.watch(localeNotifierProvider);

    return MaterialApp.router(
      title: EnvConfig.current.appName,
      debugShowCheckedModeBanner: EnvConfig.current.flavor != AppFlavor.prod,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      // Un nivel por encima del `Navigator`, donde `MaterialApp` ya montó
      // su propio `ScaffoldMessenger` — ver el docstring de
      // GlobalErrorListener sobre por qué alcanza con este `context`.
      builder: (context, child) =>
          GlobalErrorListener(child: child ?? const SizedBox.shrink()),
    );
  }
}
