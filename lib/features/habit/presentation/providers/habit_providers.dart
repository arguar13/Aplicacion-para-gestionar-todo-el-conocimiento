import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/habit/data/repositories/streak_repository_impl.dart';
import 'package:sinapsis/features/habit/domain/entities/streak.dart';
import 'package:sinapsis/features/habit/domain/repositories/streak_repository.dart';

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
