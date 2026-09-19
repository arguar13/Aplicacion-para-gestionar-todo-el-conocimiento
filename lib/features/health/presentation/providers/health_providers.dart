import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/health/data/repositories/health_repository_impl.dart';
import 'package:sinapsis/features/health/domain/entities/grown_note.dart';
import 'package:sinapsis/features/health/domain/entities/health_thresholds.dart';
import 'package:sinapsis/features/health/domain/entities/note_composition.dart';
import 'package:sinapsis/features/health/domain/repositories/health_repository.dart';

/// Cascada de inyección del feature. La capa de presentación depende de este
/// repositorio; nunca de la base de datos directamente.
final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  return HealthRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  );
});

/// De qué está hecha la bóveda de notas, por subtipo y por madurez.
///
/// `autoDispose` en todos: cada stream mantiene abierta una suscripción a los
/// cambios de la base, y sin esto seguiría recomponiéndose aunque ninguna
/// pantalla lo esté mirando.
final noteCompositionProvider = StreamProvider.autoDispose<NoteComposition>(
  (ref) => ref.watch(healthRepositoryProvider).watchNoteComposition(),
);

/// Las contradicciones que faltan por revisar.
final unreviewedContradictionCountProvider = StreamProvider.autoDispose<int>(
  (ref) =>
      ref.watch(healthRepositoryProvider).watchUnreviewedContradictionCount(),
);

/// Los títulos entre `[[ ]]` que todavía no tienen nota.
final brokenLinkCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(healthRepositoryProvider).watchBrokenLinkCount(),
);

/// Las notas vivas que crecieron esta semana.
///
/// La semana se cuenta hacia atrás desde el momento en que se abre la vista:
/// mientras esté abierta, la ventana no se corre sola.
final grownNotesProvider = StreamProvider.autoDispose<List<GrownNote>>((ref) {
  final since = ref.read(clockProvider)().subtract(kGrowthWindow);
  return ref.watch(healthRepositoryProvider).watchGrownNotes(since: since);
});
