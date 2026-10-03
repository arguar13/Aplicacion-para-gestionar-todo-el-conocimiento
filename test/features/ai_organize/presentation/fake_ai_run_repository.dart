import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';

/// Las pasadas de la IA de mentira, para las pantallas de F27: lo que
/// importa ahí es cómo se muestran, se paginan y se deshacen, no la consulta
/// —esa la prueba `ai_run_repository_impl_test.dart` con la base real—.
///
/// Deshacer se comporta como el de verdad: lo que quedaba de la IA se va, la
/// pasada queda marcada y deshacerla dos veces no borra nada la segunda.
class FakeAiRunRepository implements AiRunRepository {
  FakeAiRunRepository([List<AiRun> runs = const []]) : _runs = [...runs];

  /// De la más nueva a la más vieja, como las devuelve el repositorio.
  final List<AiRun> _runs;

  /// Cada página pedida, para comprobar la paginación.
  final pages = <({String? itemId, int limit, int offset})>[];
  final undoneRuns = <String>[];
  final undoneItems = <String>[];

  /// Si está, la próxima lectura falla con esto.
  Failure? nextListFailure;

  static final undoneAt = DateTime(2026, 9, 11, 10, 30);

  List<AiRun> get runs => List.unmodifiable(_runs);

  /// Una pasada nueva, como si la cola acabara de cerrarla: queda primera.
  void add(AiRun run) => _runs.insert(0, run);

  @override
  Future<Either<Failure, List<AiRun>>> listRuns({
    String? itemId,
    int limit = 50,
    int offset = 0,
  }) async {
    pages.add((itemId: itemId, limit: limit, offset: offset));
    final failure = nextListFailure;
    if (failure != null) {
      nextListFailure = null;
      return left(failure);
    }
    return right(
      _runs
          .where((run) => itemId == null || run.itemId == itemId)
          .skip(offset)
          .take(limit)
          .toList(),
    );
  }

  @override
  Future<Either<Failure, AiRunTally>> undoRun(String runId) async {
    undoneRuns.add(runId);
    return right(_undo((run) => run.id == runId));
  }

  @override
  Future<Either<Failure, AiRunTally>> undoItem(String itemId) async {
    undoneItems.add(itemId);
    return right(_undo((run) => run.itemId == itemId));
  }

  AiRunTally _undo(bool Function(AiRun run) matches) {
    var removed = const AiRunTally();
    for (var i = 0; i < _runs.length; i++) {
      final run = _runs[i];
      if (!matches(run) || run.isUndone) continue;
      removed += run.remaining;
      _runs[i] = run.copyWith(
        undoneAt: undoneAt,
        remaining: const AiRunTally(),
      );
    }
    return removed;
  }

  @override
  Future<Either<Failure, String>> startRun(String itemId, {String? model}) =>
      throw UnimplementedError('Las pantallas no abren pasadas.');

  @override
  Future<Either<Failure, AiRunTally>> finishRun(String runId) =>
      throw UnimplementedError('Las pantallas no cierran pasadas.');

  @override
  Future<Either<Failure, bool>> isRelationRejected({
    required String fromItemId,
    required String toItemId,
    required RelationKind kind,
  }) => throw UnimplementedError('Lo consulta la cola, no las pantallas.');

  @override
  Future<Either<Failure, bool>> isPropertyRejected({
    required String itemId,
    required String definitionName,
    required String value,
  }) => throw UnimplementedError('Lo consulta la cola, no las pantallas.');

  @override
  Future<Either<Failure, bool>> isFlashcardRejected({
    required String itemId,
    required String question,
  }) => throw UnimplementedError('Lo consulta la cola, no las pantallas.');
}

/// Una pasada para las pruebas: por defecto, terminada, con dos vínculos y
/// una tarjeta que siguen siendo de la IA.
AiRun fakeRun(
  String id, {
  required String itemId,
  String? itemTitle,
  DateTime? startedAt,
  AiRunTally remaining = const AiRunTally(relations: 2, flashcards: 1),
  AiRunTally? created,
  bool finished = true,
  bool undone = false,
}) {
  final started = startedAt ?? DateTime(2026, 9, 11, 9);
  return AiRun(
    id: id,
    itemId: itemId,
    itemTitle: itemTitle ?? 'Elemento $itemId',
    startedAt: started,
    finishedAt: finished ? started.add(const Duration(minutes: 1)) : null,
    undoneAt: undone ? FakeAiRunRepository.undoneAt : null,
    model: 'gemma',
    created: created ?? remaining,
    remaining: undone ? const AiRunTally() : remaining,
  );
}
