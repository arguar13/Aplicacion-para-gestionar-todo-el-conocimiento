import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/app/global_error_listener.dart';
import 'package:sinapsis/app/resume_model_downloads.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/back_navigation.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/i18n/locale_notifier.dart';
import 'package:sinapsis/features/keep_working/presentation/widgets/keep_working_offer_listener.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_overlay.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  /// Al volver al frente, el servicio del trabajo largo vuelve si Android lo
  /// había cortado (el tope de horas de Android 15): con la app al frente
  /// lo deja prender, y desde segundo plano no. Ver `LongWorkCoordinator`.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(longWorkCoordinatorProvider).appResumed(),
    );
    // Las descargas de modelos que siguieron con la app cerrada (F29)
    // vuelven a verse. Una vez por arranque de Dart: si la app se cerró y el
    // motor siguió vivo, al volver a abrirla esto no se repite, y las
    // descargas siguen seguidas desde antes. Si no se puede mirar alguna, el
    // error llega a la telemetría por la zona de `bootstrap`.
    unawaited(resumeModelDownloads(ref.read));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      // GlobalErrorListener sobre por qué alcanza con este `context`. Ahí
      // mismo, por encima de toda pantalla, el lector flotante (F25): sigue
      // leyendo aunque se cambie de pestaña.
      //
      // Y la oferta, una sola vez, de la ayuda para que el trabajo siga con
      // la app cerrada (F29), con el mismo navegador.
      builder: (context, child) => KeepWorkingOfferListener(
        navigatorKey: router.routerDelegate.navigatorKey,
        onOpenHelp: () => unawaited(router.push(RoutePaths.keepWorking)),
        child: ReadAloudOverlay(
          router: router,
          child: GlobalErrorListener(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
