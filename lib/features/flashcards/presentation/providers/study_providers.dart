import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/data/repositories/study_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_counts.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_scope_resolver.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';

/// Qué elementos componen un recorte de estudio.
final studyScopeResolverProvider = Provider<StudyScopeResolver>((ref) {
  return StudyScopeResolver(
    library: ref.watch(libraryRepositoryProvider),
    notebooks: ref.watch(notebookRepositoryProvider),
  );
});

/// La cola de estudio: qué tarjeta toca y cuánto hay para hoy.
final studyRepositoryProvider = Provider<StudyRepository>((ref) {
  return StudyRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
    resolver: ref.watch(studyScopeResolverProvider),
  );
});

/// Cuándo empezó el día de estudio de ahora (F31). Lo cambia `StudyDayWatcher`
/// al llegar las 4:00; los conteos dependen de esto para volver a leerse con
/// los límites del día nuevo.
final studyDayStartProvider = StateProvider<DateTime>(
  (ref) => const StudyDay().startOf(ref.read(clockProvider)()),
);

/// Cuánto hay para estudiar hoy en un recorte —nuevas, aprendiendo, por
/// repasar—, con los límites de hoy aplicados y actualizándose solo: ante
/// cambios en la base y al empezar un día de estudio nuevo.
final studyCountsProvider = StreamProvider.autoDispose
    .family<StudyCounts, StudyScope>((ref, scope) {
      ref.watch(studyDayStartProvider);
      return ref
          .watch(studyRepositoryProvider)
          .watchCounts(scope, limits: ref.watch(studyLimitsProvider));
    });

/// Lo que hay para estudiar hoy en TODA la bóveda: el número de la insignia de
/// Repasar en la navegación.
final studyDueTodayCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  return ref
      .watch(studyCountsProvider(const StudyScope.all()))
      .whenData((counts) => counts.total);
});
