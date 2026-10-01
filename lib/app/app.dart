import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/app/global_error_listener.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/back_navigation.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/i18n/locale_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

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
      // Sin esto, cerrar un diálogo adentro de un elemento dejaba a Android
      // creyendo que "atrás" no lo maneja la app, y lo minimizaba: ver
      // `reportBackHandling`.
      onNavigationNotification: (notification) =>
          reportBackHandling(router, notification),
      // Un nivel por encima del `Navigator`, donde `MaterialApp` ya montó
      // su propio `ScaffoldMessenger` — ver el docstring de
      // GlobalErrorListener sobre por qué alcanza con este `context`.
      builder: (context, child) =>
          GlobalErrorListener(child: child ?? const SizedBox.shrink()),
    );
  }
}
