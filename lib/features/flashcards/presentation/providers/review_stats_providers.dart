import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/data/repositories/review_stats_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/review_stats_repository.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';

/// Las estadísticas de repaso (F43, M17; F31, decisión 72).
final reviewStatsRepositoryProvider = Provider<ReviewStatsRepository>((ref) {
  return ReviewStatsRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
    resolver: ref.watch(studyScopeResolverProvider),
  );
});

/// Las estadísticas de un recorte, actualizándose solas —ante cambios en las
/// tarjetas, el historial o el recorte, y al empezar un día de estudio nuevo,
/// que mueve el pronóstico entero—.
final reviewStatsProvider = StreamProvider.autoDispose
    .family<ReviewStats, StudyScope>((ref, scope) {
      ref.watch(studyDayStartProvider);
      return ref.watch(reviewStatsRepositoryProvider).watch(scope: scope);
    });
