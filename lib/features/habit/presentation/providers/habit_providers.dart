import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/database/habit_event_recorder.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/habit/data/repositories/review_history_repository_impl.dart';
import 'package:sinapsis/features/habit/data/repositories/streak_repository_impl.dart';
import 'package:sinapsis/features/habit/domain/entities/review_history.dart';
import 'package:sinapsis/features/habit/domain/entities/streak.dart';
import 'package:sinapsis/features/habit/domain/repositories/review_history_repository.dart';
import 'package:sinapsis/features/habit/domain/repositories/streak_repository.dart';

/// Ningún repositorio nuevo lo necesita hoy —cada uno que ya lo usaba lo
/// arma con un getter privado propio, ver `HabitEventRecorder`—; este es
/// para quien lo necesite desde la presentación, como la sesión suelta de
/// quiz (F20, commit 8), sin repetir el cableado.
final habitEventRecorderProvider = Provider<HabitEventRecorder>((ref) {
  return HabitEventRecorder(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});

final streakRepositoryProvider = Provider<StreakRepository>((ref) {
  return StreakRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
  );
});

/// La racha de hoy (F17, D6/commit 8): se actualiza sola con cada acción
/// que cuenta.
final currentStreakProvider = StreamProvider.autoDispose<Streak>((ref) {
  return ref.watch(streakRepositoryProvider).watch();
});

final reviewHistoryRepositoryProvider = Provider<ReviewHistoryRepository>((
  ref,
) {
  return ReviewHistoryRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
    resolver: ref.watch(studyScopeResolverProvider),
  );
});

/// El historial de repasos de un recorte (F17, D8; F43, M16): se actualiza
/// solo con cada repaso nuevo y al empezar un día de estudio nuevo, que mueve
/// las semanas y el calendario.
final reviewHistoryProvider = StreamProvider.autoDispose
    .family<ReviewHistory, StudyScope>((ref, scope) {
      ref.watch(studyDayStartProvider);
      return ref.watch(reviewHistoryRepositoryProvider).watch(scope);
    });
