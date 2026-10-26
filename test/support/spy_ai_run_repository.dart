import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';

/// Las pasadas de la IA de verdad, con un registro del orden en que se las
/// usa (F39, paso 6): abrir, sumar lo que costó y cerrar. Para comprobar que
/// «Lo que hizo la IA», que vuelve a leer cuando una tarea termina, encuentra
/// la pasada ya cerrada y con su costo.
///
/// Lo que no sea abrir, sumar, cerrar o listar no lo usa nadie en esas
/// pruebas, y falla.
class SpyAiRunRepository implements AiRunRepository {
  SpyAiRunRepository(this._inner, this.log);

  final AiRunRepository _inner;

  /// Lo que pasó, en orden: se comparte con quien anota otros hechos.
  final List<String> log;

  @override
  Future<Either<Failure, String>> startRun(
    String itemId, {
    String? model,
    String? contentSimhash,
    AiRunScope scope = AiRunScope.organize,
  }) {
    log.add('abre');
    return _inner.startRun(
      itemId,
      model: model,
      contentSimhash: contentSimhash,
      scope: scope,
    );
  }

  @override
  Future<Either<Failure, Unit>> addUsage(String runId, AiTaskUsage usage) {
    log.add('suma costo');
    return _inner.addUsage(runId, usage);
  }

  @override
  Future<Either<Failure, AiRunTally>> finishRun(String runId) {
    log.add('cierra');
    return _inner.finishRun(runId);
  }

  @override
  Future<Either<Failure, List<AiRun>>> listRuns({
    String? itemId,
    int limit = 50,
    int offset = 0,
  }) => _inner.listRuns(itemId: itemId, limit: limit, offset: offset);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no se usa acá.');
}
