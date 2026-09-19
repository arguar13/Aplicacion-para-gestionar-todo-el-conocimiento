import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/vocabulary/data/repositories/vocabulary_repository_impl.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_operation.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';
import 'package:sinapsis/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:sinapsis/features/vocabulary/domain/services/merge_candidates.dart';

final vocabularyRepositoryProvider = Provider<VocabularyRepository>((ref) {
  return VocabularyRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});

final vocabularyValueStatsProvider =
    StreamProvider.autoDispose<List<VocabularyValueStat>>((ref) {
      return ref.watch(vocabularyRepositoryProvider).watchValueStats();
    });

final vocabularyCategoryStatsProvider =
    StreamProvider.autoDispose<List<VocabularyCategoryStat>>((ref) {
      return ref.watch(vocabularyRepositoryProvider).watchCategoryStats();
    });

/// Los grupos de valores que quizá sean el mismo. Se calcula fuera del hilo de
/// la interfaz: con un vocabulario grande el cálculo se nota, y no debe
/// congelar la pantalla.
///
/// Los tests de widget lo sobrescriben con el cálculo síncrono: el isolate de
/// `compute` no corre bajo el reloj simulado de `testWidgets`. Que el cálculo
/// sea correcto y rápido lo prueban los tests de `merge_candidates`.
final mergeCandidateGroupsProvider =
    FutureProvider.autoDispose<List<MergeCandidateGroup>>((ref) async {
      final stats = await ref.watch(vocabularyValueStatsProvider.future);
      final candidates = await findMergeCandidatesOffMainThread(stats);
      return groupMergeCandidates(candidates);
    });

/// Los valores que están puestos en un único elemento.
final singleUseValuesProvider =
    Provider.autoDispose<AsyncValue<List<VocabularyValueStat>>>((ref) {
      return ref
          .watch(vocabularyValueStatsProvider)
          .whenData(
            (stats) => [
              for (final s in stats)
                if (s.usage == 1) s,
            ],
          );
    });

/// Los valores que ningún elemento tiene puesto.
final unusedValuesProvider =
    Provider.autoDispose<AsyncValue<List<VocabularyValueStat>>>((ref) {
      return ref
          .watch(vocabularyValueStatsProvider)
          .whenData(
            (stats) => [
              for (final s in stats)
                if (s.usage == 0) s,
            ],
          );
    });

/// Las categorías que el usuario creó y quedaron sin ningún valor.
final orphanCategoriesProvider =
    Provider.autoDispose<AsyncValue<List<VocabularyCategoryStat>>>((ref) {
      return ref
          .watch(vocabularyCategoryStatsProvider)
          .whenData(
            (stats) => [
              for (final c in stats)
                if (c.isOrphan) c,
            ],
          );
    });

/// Las operaciones de mantenimiento, y la ÚLTIMA que se hizo: el estado es esa
/// operación —o `null` si todavía no hay ninguna o ya se deshizo—, que es lo
/// único que se puede deshacer. Solo en memoria: cerrar la app la olvida.
///
/// Vive en un notifier y no en el repositorio porque es estado de la sesión de
/// la pantalla, no del vocabulario: el repositorio no guarda nada entre
/// llamadas.
class VocabularyController extends Notifier<VocabularyOperation?> {
  @override
  VocabularyOperation? build() => null;

  VocabularyRepository get _repository =>
      ref.read(vocabularyRepositoryProvider);

  Future<Either<Failure, VocabularyOperation>> merge({
    required String keepId,
    required List<String> discardIds,
  }) =>
      _record(_repository.mergeValues(keepId: keepId, discardIds: discardIds));

  Future<Either<Failure, VocabularyOperation>> rename({
    required String id,
    required String label,
  }) => _record(_repository.renameValue(id: id, label: label));

  Future<Either<Failure, VocabularyOperation>> deleteUnused(List<String> ids) =>
      _record(_repository.deleteUnusedValues(ids));

  Future<Either<Failure, VocabularyOperation>> deleteCategories(
    List<String> ids,
  ) => _record(_repository.deleteEmptyCategories(ids));

  Future<Either<Failure, VocabularyOperation>> addAlias({
    required String valueId,
    required String alias,
  }) => _record(_repository.addAlias(valueId: valueId, alias: alias));

  Future<Either<Failure, VocabularyOperation>> removeAlias(String aliasId) =>
      _record(_repository.removeAlias(aliasId));

  /// Deshace la última operación. Se olvida de ella tenga éxito o no: si se
  /// negó porque el vocabulario cambió, reintentar no va a cambiar la
  /// respuesta.
  Future<Either<Failure, Unit>> undo() async {
    final operation = state;
    if (operation == null) return right(unit);
    final result = await _repository.undo(operation);
    state = null;
    return result;
  }

  Future<Either<Failure, VocabularyOperation>> _record(
    Future<Either<Failure, VocabularyOperation>> call,
  ) async {
    final result = await call;
    result.fold((_) {}, (operation) => state = operation);
    return result;
  }
}

final vocabularyControllerProvider =
    NotifierProvider<VocabularyController, VocabularyOperation?>(
      VocabularyController.new,
    );
