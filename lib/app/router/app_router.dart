import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/go_router_refresh_notifier.dart';
import 'package:sinapsis/app/router/route_error_screen.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/app/router/splash_screen.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/create_vault_screen.dart';
import 'package:sinapsis/features/vault/presentation/screens/unlock_vault_screen.dart';

/// Router centralizado (deep linking + URLs amigables en web). Cada feature
/// añade sus `GoRoute` aquí, o expone una lista de rutas que este archivo
/// agrega con el operador spread (`...featureXRoutes`).
///
/// Route guard: `redirect` se reevalúa cada vez que cambia
/// [vaultSessionControllerProvider] (vía [GoRouterRefreshNotifier]), así que
/// ningún widget necesita navegar manualmente al crear o abrir la bóveda —
/// cambian el estado y el router hace el resto.
final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = GoRouterRefreshNotifier(
    ref,
    vaultSessionControllerProvider,
  );
  ref.onDispose(refreshNotifier.dispose);

  final router = GoRouter(
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: EnvConfig.current.flavor == AppFlavor.dev,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final session = ref.read(vaultSessionControllerProvider);
      return _redirect(session: session, location: state.matchedLocation);
    },
    routes: [
      GoRoute(
        path: RoutePaths.splash,
        name: RouteNames.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RoutePaths.vaultCreate,
        name: RouteNames.vaultCreate,
        builder: (context, state) => const CreateVaultScreen(),
      ),
      GoRoute(
        path: RoutePaths.vaultUnlock,
        name: RouteNames.vaultUnlock,
        builder: (context, state) => const UnlockVaultScreen(),
      ),
      GoRoute(
        path: RoutePaths.dashboard,
        name: RouteNames.dashboard,
        builder: (context, state) => const DashboardScreen(),
      ),
    ],
    errorBuilder: (context, state) => RouteErrorScreen(uri: state.uri),
  );

  return router;
});

/// Adónde mandar al usuario según el estado de la bóveda.
///
/// La forma es la misma que tenía el guard de sesiones remotas, con una
/// diferencia que importa: ahora hay dos puertas de entrada distintas en
/// vez de una. Con un backend, "no tengo sesión" y "no tengo cuenta" se
/// resolvían en la misma pantalla de login; acá, que no exista bóveda
/// significa que el dispositivo se está estrenando y hay que crearla, un
/// camino separado del de abrir una que ya está.
String? _redirect({required VaultSession session, required String location}) {
  final onSplash = location == RoutePaths.splash;
  final onCreate = location == RoutePaths.vaultCreate;
  final onUnlock = location == RoutePaths.vaultUnlock;

  return switch (session) {
    // Todavía no se leyó el almacenamiento: solo se permite el splash.
    VaultUnknown() => onSplash ? null : RoutePaths.splash,
    // Dispositivo nuevo: lo único que se puede hacer es crear la bóveda.
    VaultAbsent() => onCreate ? null : RoutePaths.vaultCreate,
    // Hay bóveda y está cerrada: cualquier destino pasa primero por el
    // desbloqueo.
    VaultLocked() => onUnlock ? null : RoutePaths.vaultUnlock,
    // Abierta: las tres pantallas de acceso ya no tienen sentido.
    VaultUnlocked() =>
      (onSplash || onCreate || onUnlock) ? RoutePaths.dashboard : null,
  };
}
