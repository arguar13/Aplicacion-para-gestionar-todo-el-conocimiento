import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/navigation/adaptive_scaffold.dart';
import 'package:sinapsis/app/router/go_router_refresh_notifier.dart';
import 'package:sinapsis/app/router/route_error_screen.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/app/router/splash_screen.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/features/ai_models/presentation/screens/language_model_screen.dart';
import 'package:sinapsis/features/ai_organize/presentation/screens/ai_activity_screen.dart';
import 'package:sinapsis/features/anki_import/presentation/screens/anki_import_screen.dart';
import 'package:sinapsis/features/atlas/presentation/screens/atlas_screen.dart';
import 'package:sinapsis/features/capture/presentation/providers/shared_content_controller.dart';
import 'package:sinapsis/features/capture/presentation/screens/capture_screen.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_model_screen.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/presentation/screens/creation_viewer_screen.dart';
import 'package:sinapsis/features/duplicates/presentation/screens/possible_duplicates_screen.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/explorer/presentation/widgets/explorer_focus.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/my_cards_route.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/my_cards_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_entry_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_stats_screen.dart';
import 'package:sinapsis/features/graph/presentation/screens/local_graph_screen.dart';
import 'package:sinapsis/features/habit/presentation/screens/review_history_screen.dart';
import 'package:sinapsis/features/health/presentation/screens/grown_notes_screen.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/keep_working/presentation/screens/keep_working_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/unsorted_items_screen.dart';
import 'package:sinapsis/features/links/presentation/screens/broken_links_screen.dart';
import 'package:sinapsis/features/map/presentation/screens/map_screen.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebook_detail_screen.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebooks_screen.dart';
import 'package:sinapsis/features/processed/presentation/processed_routes.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_original_screen.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_screen.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/features/relations/presentation/screens/embedding_backfill_screen.dart';
import 'package:sinapsis/features/relations/presentation/screens/embedding_model_screen.dart';
import 'package:sinapsis/features/relations/presentation/screens/tension_screen.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/features/suggestions/presentation/screens/property_suggestions_review_screen.dart';
import 'package:sinapsis/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:sinapsis/features/transform/presentation/screens/transcription_model_screen.dart';
import 'package:sinapsis/features/trash/presentation/screens/trash_screen.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/create_vault_screen.dart';
import 'package:sinapsis/features/vault/presentation/screens/merge_conflicts_screen.dart';
import 'package:sinapsis/features/vault/presentation/screens/unlock_vault_screen.dart';
import 'package:sinapsis/features/vault/presentation/screens/vault_backup_screen.dart';
import 'package:sinapsis/features/vault/presentation/screens/vault_compaction_screen.dart';
import 'package:sinapsis/features/vocabulary/presentation/screens/vocabulary_category_screen.dart';
import 'package:sinapsis/features/vocabulary/presentation/screens/vocabulary_screen.dart';

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

  // El `Navigator` de la raíz, donde van las pantallas que se abren encima de
  // la barra de navegación. Una llave por router: compartida entre routers
  // chocaría si el provider se reconstruye con el viejo todavía montado.
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
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
        path: RoutePaths.vaultCompaction,
        name: RouteNames.vaultCompaction,
        builder: (context, state) => const VaultCompactionScreen(),
      ),
      GoRoute(
        path: RoutePaths.duplicates,
        name: RouteNames.duplicates,
        builder: (context, state) => const PossibleDuplicatesScreen(),
      ),
      GoRoute(
        path: RoutePaths.vocabulary,
        name: RouteNames.vocabulary,
        builder: (context, state) => const VocabularyScreen(),
      ),
      GoRoute(
        path: RoutePaths.vocabularyCategoryPattern,
        name: RouteNames.vocabularyCategory,
        builder: (context, state) =>
            VocabularyCategoryScreen(definitionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePaths.brokenLinks,
        name: RouteNames.brokenLinks,
        builder: (context, state) => const BrokenLinksScreen(),
      ),
      GoRoute(
        path: RoutePaths.trash,
        name: RouteNames.trash,
        builder: (context, state) => const TrashScreen(),
      ),
      GoRoute(
        path: RoutePaths.aiActivity,
        name: RouteNames.aiActivity,
        builder: (context, state) =>
            AiActivityScreen(itemId: state.uri.queryParameters['item']),
      ),
      GoRoute(
        path: RoutePaths.conflicts,
        name: RouteNames.conflicts,
        builder: (context, state) => const MergeConflictsScreen(),
      ),
      GoRoute(
        path: RoutePaths.suggestionReview,
        name: RouteNames.suggestionReview,
        builder: (context, state) => const PropertySuggestionsReviewScreen(),
      ),
      GoRoute(
        path: RoutePaths.grownNotes,
        name: RouteNames.grownNotes,
        builder: (context, state) => const GrownNotesScreen(),
      ),
      GoRoute(
        path: RoutePaths.readingPattern,
        name: RouteNames.reading,
        builder: (context, state) {
          final start = int.tryParse(state.uri.queryParameters['start'] ?? '');
          final end = int.tryParse(state.uri.queryParameters['end'] ?? '');
          return ReadingScreen(
            itemId: state.pathParameters['id']!,
            jump: start != null && end != null
                ? (start: start, end: end)
                : null,
          );
        },
      ),
      // El material de un tema —lo procesado de un valor y sus subtemas, o de
      // un tema—, lo que abren el Atlas y el Mapa. Era un destino de la barra
      // (el Explorador) y salió en F36: repetía la Biblioteca. Ahora va
      // encima, con su flecha para volver adonde se estaba.
      GoRoute(
        path: RoutePaths.explorer,
        name: RouteNames.explorer,
        builder: (context, state) => ExplorerFocus(
          valueId: state.uri.queryParameters['value'],
          spaceId: state.uri.queryParameters['space'],
          child: const ExplorerScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.unsorted,
        name: RouteNames.unsorted,
        builder: (context, state) => const UnsortedItemsScreen(),
      ),
      GoRoute(
        path: RoutePaths.chatModel,
        name: RouteNames.chatModel,
        builder: (context, state) => const ChatModelScreen(),
      ),
      GoRoute(
        path: RoutePaths.languageModel,
        name: RouteNames.languageModel,
        builder: (context, state) => const LanguageModelScreen(),
      ),
      GoRoute(
        path: RoutePaths.embeddingModel,
        name: RouteNames.embeddingModel,
        builder: (context, state) => const EmbeddingModelScreen(),
      ),
      GoRoute(
        path: RoutePaths.keepWorking,
        name: RouteNames.keepWorking,
        builder: (context, state) => const KeepWorkingScreen(),
      ),
      GoRoute(
        path: RoutePaths.embeddingBackfill,
        name: RouteNames.embeddingBackfill,
        builder: (context, state) => const EmbeddingBackfillScreen(),
      ),
      GoRoute(
        path: RoutePaths.graphTension,
        name: RouteNames.graphTension,
        builder: (context, state) => const TensionScreen(),
      ),
      GoRoute(
        path: RoutePaths.ankiImport,
        name: RouteNames.ankiImport,
        builder: (context, state) => const AnkiImportScreen(),
      ),
      GoRoute(
        path: RoutePaths.reviewHistory,
        name: RouteNames.reviewHistory,
        builder: (context, state) => const ReviewHistoryScreen(),
      ),
      // La sesión de repaso, a pantalla completa (F31, ola 2): sin la barra de
      // navegación, con «atrás» para volver a la entrada.
      GoRoute(
        path: RoutePaths.reviewSession,
        name: RouteNames.reviewSession,
        builder: (context, state) => ReviewScreen(
          scope: _studyScopeOf(state.uri.queryParameters),
          startInPractice: state.uri.queryParameters['practice'] == '1',
        ),
      ),
      // Una creación de «Lo creado» (F43) en su visor, encima de la barra:
      // se abre desde Repasar, un documento procesado o un cuaderno.
      GoRoute(
        path: RoutePaths.creationPattern,
        name: RouteNames.creation,
        builder: (context, state) =>
            CreationViewerScreen(creationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: kRouteCards,
        name: kRouteNameCards,
        builder: (context, state) => MyCardsScreen(
          initialScope: myCardsScopeFromQuery(state.uri.queryParameters),
        ),
      ),
      GoRoute(
        path: kRouteReviewStats,
        name: kRouteNameReviewStats,
        builder: (context, state) => const ReviewStatsScreen(),
      ),
      GoRoute(
        path: RoutePaths.graphLocalPattern,
        name: RouteNames.graphLocal,
        builder: (context, state) =>
            LocalGraphScreen(itemId: state.pathParameters['id']!),
      ),
      // Los diez destinos principales, cada uno con su propio `Navigator` —
      // así cambiar de pestaña y volver conserva el scroll y los filtros de
      // cada una—, envueltos por `AdaptiveScaffold`: una barra abajo en
      // celular, un riel al costado en escritorio. Reemplaza al AppBar de
      // nueve íconos que tenía antes la biblioteca — ver la decisión 22 en
      // docs/arquitectura.md. El orden de las ramas es significativo: es el de
      // `ShellBranch`, en `nav_destinations.dart`.
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
                  //
                  // Pero se dibuja en el `Navigator` de la raíz, encima de la
                  // barra, no en el de la rama: el detalle se abre desde
                  // cualquier pantalla —el Atlas, el material de un tema, un
                  // cuaderno, la lectura…—, y varias son rutas de la raíz que
                  // están ENCIMA del shell. Empujar desde ahí una ruta que
                  // vive dentro del shell apilaba un segundo shell con la
                  // misma clave de página sobre el primero, y el detalle
                  // salía en blanco (en `debug`, con una aserción del
                  // `Navigator`). En la raíz es un solo destino que se abre
                  // igual desde todos lados.
                  //
                  // Es además el despachador de un elemento por su id: todo lo
                  // que abre «un elemento» —la búsqueda, las citas del chat,
                  // el Mapa, un enlace— pasa por acá. Un documento procesado
                  // (F41) es una nota para la base, pero no se ve como una: se
                  // redirige a su pantalla, en este solo lugar.
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: ':id',
                    name: RouteNames.itemDetail,
                    redirect: (context, state) => processedDocumentRedirect(
                      ref.read(processedRepositoryProvider),
                      state.pathParameters['id']!,
                    ),
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
                path: RoutePaths.inbox,
                name: RouteNames.inbox,
                builder: (context, state) => const InboxScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.graph,
                name: RouteNames.graph,
                builder: (context, state) => const MapScreen(),
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
                // `?scope=` elige un recorte de Procesado al llegar (F43, M6:
                // «Crear en Repasar»).
                builder: (context, state) => ReviewEntryScreen(
                  requestedScopeKey: state.uri.queryParameters['scope'],
                ),
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
          // El Atlas, al final: su posición visible es la tercera, pero
          // sumarlo al final no corrió el índice de las ramas de arriba.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.atlas,
                name: RouteNames.atlas,
                builder: (context, state) => const AtlasScreen(),
              ),
            ],
          ),
          // Los cuadernos (F16), mismo criterio que el Atlas.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.notebooks,
                name: RouteNames.notebooks,
                builder: (context, state) => const NotebooksScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    name: RouteNames.notebookDetail,
                    builder: (context, state) => NotebookDetailScreen(
                      notebookId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // La línea de tiempo (F40), mismo criterio: se ve en «Estudiar»,
          // entre los Cuadernos y el Mapa (F43). Era una ruta plana que se
          // abría encima de la barra (F9). El filtro con el que se llega —una
          // rama del Atlas, un documento— no viaja en la dirección: lo fija
          // quien navega en `timelineFilterProvider`, el único dueño del
          // filtro, porque la pantalla vive en el `IndexedStack` y no se
          // vuelve a construir al volver a ella.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.timeline,
                name: RouteNames.timeline,
                builder: (context, state) => const TimelineScreen(),
              ),
            ],
          ),
          // «Procesado» (F41), mismo criterio que el Atlas: se ve primero en
          // «Estudiar» (F43), pero va al final para no correr ninguna rama.
          // Su documento se dibuja en la raíz, como el detalle de un
          // elemento y por lo mismo: se abre desde cualquier pantalla —la
          // búsqueda, el chat, el Mapa, la Línea de tiempo—, y varias están
          // encima del shell.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.processed,
                name: RouteNames.processed,
                builder: (context, state) => const ProcessedScreen(),
                routes: [
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: ':id',
                    name: RouteNames.processedDocument,
                    builder: (context, state) => ProcessedDocumentScreen(
                      documentId: state.pathParameters['id']!,
                    ),
                    routes: [
                      // La copia del original (decisión H), encima del
                      // documento, también en la raíz.
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'original',
                        name: RouteNames.processedOriginal,
                        builder: (context, state) => ProcessedOriginalScreen(
                          documentId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
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

/// El recorte de estudio que dice la dirección: `?kind=space&id=…`. Sin
/// `kind`, o con uno que no se conoce, o sin el `id` que ese recorte necesita,
/// se estudia todo: una dirección vieja o escrita a mano no puede dejar la
/// pantalla sin tarjetas por un error de tipeo.
StudyScope _studyScopeOf(Map<String, String> query) {
  final id = query['id'];
  if (id == null || id.isEmpty) return const StudyScope.all();
  return switch (query['kind']) {
    'space' => StudyScope.space(id),
    'value' => StudyScope.value(id),
    'notebook' => StudyScope.notebook(id),
    'item' => StudyScope.item(id),
    // Un recorte de Procesado (F43): solo si se entiende.
    'processed' =>
      CreationScope.parse(id)?.studyScope ?? const StudyScope.all(),
    _ => const StudyScope.all(),
  };
}
