import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/map/data/repositories/board_facts_source_impl.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/services/board_facts.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';

/// De dónde lee el Resumen del Mapa lo que cuenta además del grafo de temas
/// (F44, paso 3).
final boardFactsSourceProvider = Provider<BoardFactsSource>((ref) {
  return BoardFactsSourceImpl(
    database: ref.watch(appDatabaseProvider),
    library: ref.watch(libraryRepositoryProvider),
  );
});

/// Los documentos y los vínculos del Resumen para un pedido del Mapa.
///
/// Como el tablero (`mapDashboardProvider`), se vuelve a leer cuando el mapa
/// se recalcula y no por su cuenta: comparte la espera por lotes del motor, así
/// que una importación grande no lo lee mil veces.
final boardFactsProvider = FutureProvider.autoDispose
    .family<BoardFacts, MapRequest>((ref, request) {
      ref.watch(
        knowledgeMapProvider(request).select(
          (state) => switch (state) {
            AsyncData(value: MapReady(:final snapshot)) => snapshot.sequence,
            _ => -1,
          },
        ),
      );
      return ref
          .watch(boardFactsSourceProvider)
          .readFacts(request.definitionId, filter: request.filter);
    });

/// Las tarjetas de cada documento procesado, que se actualizan solas: repasar
/// una tarjeta en Repasar baja «para hoy» en el Resumen sin esperar a que el
/// mapa —que no mira las tarjetas— se recalcule.
///
/// Es una lectura agrupada por documento que crece con los documentos que
/// tienen tarjetas, no con lo que hay en la bóveda; `watchReads` la encola, así
/// que una sesión de repaso nunca la corre dos veces a la vez.
///
/// `autoDispose`: mantiene una suscripción a los cambios de la base.
final boardCardsProvider =
    StreamProvider.autoDispose<Map<String, BoardCardFact>>((ref) {
      final source = ref.watch(boardFactsSourceProvider);
      final clock = ref.watch(clockProvider);
      return watchReads(
        changes: source.cardChanges,
        read: () => source.readCards(clock()),
        telemetry: ref.watch(telemetryServiceProvider),
        hint: 'boardCardsProvider',
      );
    });
