import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/navigation/adaptive_scaffold.dart';
import 'package:sinapsis/app/router/go_router_refresh_notifier.dart';
import 'package:sinapsis/app/router/route_error_screen.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/app/router/splash_screen.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/features/capture/presentation/providers/shared_content_controller.dart';
import 'package:sinapsis/features/capture/presentation/screens/capture_screen.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_model_screen.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/graph/presentation/screens/graph_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/features/transform/presentation/screens/transcription_model_screen.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/create_vault_screen.dart';
import 'package:sinapsis/features/vault/presentation/screens/unlock_vault_screen.dart';
import 'package:sinapsis/features/vault/presentation/screens/vault_backup_screen.dart';

/// Router centralizado (deep linking + URLs amigables en web). Cada feature
/// añade sus `GoRoute` aquí, o expone una lista de rutas que este archivo
/// agrega con el operador spread (`...featureXRoutes`).
///
/// Route guard: `redirect` se reevalúa cada vez que cambia
/// [vaultSessionControllerProvider] o [sharedContentControllerProvider] (vía
/// [GoRouterRefreshNotifier]), así que ningún widget necesita navegar
/// manualmente al crear o abrir la bóveda, ni cuando llega algo compartido
/// desde otra app — cambia el estado correspondiente y el router hace el
/// resto.
final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = GoRouterRefreshNotifier(ref, [
    vaultSessionControllerProvider,
    sharedContentControllerProvider,
  ]);
  ref.onDispose(refreshNotifier.dispose);

  final router = GoRouter(
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: EnvConfig.current.flavor == AppFlavor.dev,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final session = ref.read(vaultSessionControllerProvider);
      final hasPendingShare = ref
          .read(sharedContentControllerProvider)
          .isNotEmpty;
      return _redirect(
        session: session,
        location: state.matchedLocation,
        hasPendingShare: hasPendingShare,
      );
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
        path: RoutePaths.capture,
        name: RouteNames.capture,
        builder: (context, state) => const CaptureScreen(),
      ),
      GoRoute(
        path: RoutePaths.transcriptionModel,
        name: RouteNames.transcriptionModel,
        builder: (context, state) => const TranscriptionModelScreen(),
      ),
      GoRoute(
        path: RoutePaths.vaultBackup,
        name: RouteNames.vaultBackup,
        builder: (context, state) => const VaultBackupScreen(),
      ),
      GoRoute(
        path: RoutePaths.chatModel,
        name: RouteNames.chatModel,
        builder: (context, state) => const ChatModelScreen(),
      ),
      // Los cinco destinos principales, cada uno con su propio `Navigator` —
      // así cambiar de pestaña y volver conserva el scroll y los filtros de
      // cada una—, envueltos por `AdaptiveScaffold`: una barra abajo en
      // celular, un riel al costado en escritorio. Reemplaza al AppBar de
      // nueve íconos que tenía antes la biblioteca — ver la decisión 22 en
      // docs/arquitectura.md. El orden de las ramas es significativo: tiene
      // que coincidir con `NavDestinationSpec.branchIndex` en
      // `nav_destinations.dart`.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdaptiveScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.library,
                name: RouteNames.library,
                builder: (context, state) => const LibraryScreen(),
                routes: [
                  // Anidada bajo la biblioteca: el detalle de un elemento no
                  // existe por fuera de ella, y así "volver" lleva siempre a
                  // la lista — incluso cuando se llega por un enlace
                  // directo en web.
                  GoRoute(
                    path: ':id',
                    name: RouteNames.itemDetail,
                    builder: (context, state) =>
                        ItemDetailScreen(itemId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.graph,
                name: RouteNames.graph,
                builder: (context, state) => const GraphScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.chat,
                name: RouteNames.chat,
                builder: (context, state) => const ChatScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.review,
                name: RouteNames.review,
                builder: (context, state) => const ReviewScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.settings,
                name: RouteNames.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => RouteErrorScreen(uri: state.uri),
  );

  return router;
});

/// Adónde mandar al usuario según el estado de la bóveda y si hay algo
/// compartido desde otra app esperando revisión.
///
/// La forma de la bóveda es la misma que tenía el guard de sesiones
/// remotas, con una diferencia que importa: ahora hay dos puertas de
/// entrada distintas en vez de una. Con un backend, "no tengo sesión" y "no
/// tengo cuenta" se resolvían en la misma pantalla de login; acá, que no
/// exista bóveda significa que el dispositivo se está estrenando y hay que
/// crearla, un camino separado del de abrir una que ya está.
///
/// [hasPendingShare] solo importa con la bóveda abierta: mientras está
/// cerrada, nadie debería ver ni un indicio de que hay algo esperando, y en
/// cuanto se abre el guard ya manda a revisarlo sin que el usuario tenga que
/// ir a buscarlo. No se redirige si ya está en la captura, para no pisar lo
/// que esté escribiendo si el contenido llegó mientras la tenía abierta.
String? _redirect({
  required VaultSession session,
  required String location,
  required bool hasPendingShare,
}) {
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
    VaultUnlocked() when onSplash || onCreate || onUnlock => RoutePaths.library,
    VaultUnlocked() when hasPendingShare && location != RoutePaths.capture =>
      RoutePaths.capture,
    VaultUnlocked() => null,
  };
}
