import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/go_router_refresh_notifier.dart';
import 'package:sinapsis/app/router/placeholder_screen.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/app/router/splash_screen.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/session/session_providers.dart';
import 'package:sinapsis/core/session/session_state.dart';
import 'package:sinapsis/features/auth/presentation/screens/login_screen.dart';
import 'package:sinapsis/features/dashboard/presentation/screens/dashboard_screen.dart';

/// Router centralizado (deep linking + URLs amigables en web). Cada feature
/// añade sus `GoRoute` aquí, o expone una lista de rutas que este archivo
/// agrega con el operador spread (`...featureXRoutes`).
///
/// Route guard: `redirect` se reevalúa cada vez que cambia
/// `sessionControllerProvider` (vía [GoRouterRefreshNotifier]), así que
/// ningún widget necesita navegar manualmente al hacer login/logout — ver
/// `AuthNotifier.login` y `SessionController.logout`.
final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = GoRouterRefreshNotifier(
    ref,
    sessionControllerProvider,
  );
  ref.onDispose(refreshNotifier.dispose);

  final router = GoRouter(
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: EnvConfig.current.flavor == AppFlavor.dev,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      return _redirect(session: session, location: state.matchedLocation);
    },
    routes: [
      GoRoute(
        path: RoutePaths.splash,
        name: RouteNames.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RoutePaths.login,
        name: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.dashboard,
        name: RouteNames.dashboard,
        builder: (context, state) => const DashboardScreen(),
      ),
    ],
    errorBuilder: (context, state) =>
        PlaceholderScreen(title: 'Ruta no encontrada: ${state.uri}'),
  );

  return router;
});

String? _redirect({required SessionState session, required String location}) {
  final onSplash = location == RoutePaths.splash;
  final onLogin = location == RoutePaths.login;

  return switch (session) {
    // Aún no sabemos si hay sesión: solo se permite quedarse en el splash.
    SessionUnknown() => onSplash ? null : RoutePaths.splash,
    // No hay sesión: cualquier ruta privada expulsa a /login.
    SessionUnauthenticated() => onLogin ? null : RoutePaths.login,
    // Hay sesión: /splash y /login ya no tienen sentido, van al dashboard.
    SessionAuthenticated() =>
      (onSplash || onLogin) ? RoutePaths.dashboard : null,
  };
}
