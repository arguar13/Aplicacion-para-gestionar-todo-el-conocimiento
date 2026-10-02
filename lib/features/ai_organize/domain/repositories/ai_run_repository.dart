import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';

/// Lo que la IA hizo sola y lo que no tiene que volver a hacer (F27).
///
/// Una pasada se abre con [startRun] antes de aplicar nada; cada vínculo,
/// tarjeta o propiedad que la IA crea lleva su id (`AiProvenance`), y por eso
/// se puede deshacer entera ([undoRun]) o todo lo de un elemento
/// ([undoItem]). Deshacer se lleva solo lo que sigue siendo de la IA: lo que
/// la persona editó ya es suyo y no se toca.
///
/// La memoria de lo que «no era» la escriben los repositorios que borran
/// —`OrganizeRepository.rejectAiRelation`, `FlashcardRepository.
/// rejectAiFlashcard`…—; acá se consulta antes de proponer nada.
abstract interface class AiRunRepository {
  /// Abre una pasada de la IA sobre [itemId] y devuelve su id. [model] es el
  /// modelo que trabaja, si se sabe.
  Future<Either<Failure, String>> startRun(String itemId, {String? model});

  /// Cierra la pasada [runId]: cuenta lo que creó —lo que lleva su id y sigue
  /// siendo de la IA— y lo deja como su historia. Devuelve esa cuenta.
  Future<Either<Failure, AiRunTally>> finishRun(String runId);

  /// Las pasadas, de la más nueva a la más vieja, de a [limit] desde
  /// [offset], con lo que cada una creó y lo que todavía es de la IA. Con
  /// [itemId], solo las de ese elemento. Las de un elemento en la papelera no
  /// se listan.
  Future<Either<Failure, List<AiRun>>> listRuns({
    String? itemId,
    int limit = 50,
    int offset = 0,
  });

  /// Deshace la pasada [runId]: borra, en una sola transacción, todo lo que
  /// lleva su id y sigue siendo de la IA, y la marca como deshecha. Lo que la
  /// persona adoptó queda. Devuelve cuánto se borró; deshacer dos veces no
  /// borra nada la segunda.
  ///
  /// Deshacer no es «no era»: no recuerda nada, porque la persona no dijo que
  /// esté mal, dijo que no lo quiere ahora. La pasada deshecha queda, y es la
  /// que le dice a la cola que no vuelva a organizar sola ese elemento.
  Future<Either<Failure, AiRunTally>> undoRun(String runId);

  /// Deshace todas las pasadas de [itemId] que siguen en pie, en una sola
  /// transacción. Devuelve cuánto se borró en total.
  Future<Either<Failure, AiRunTally>> undoItem(String itemId);

  /// Si la persona dijo que «no era» un vínculo de [kind] entre estos dos
  /// elementos, en cualquier sentido.
  Future<Either<Failure, bool>> isRelationRejected({
    required String fromItemId,
    required String toItemId,
    required RelationKind kind,
  });

  /// Si la persona dijo que «no era» el valor [value] de la categoría
  /// [definitionName] en [itemId] —sin distinguir mayúsculas ni acentos—.
  Future<Either<Failure, bool>> isPropertyRejected({
    required String itemId,
    required String definitionName,
    required String value,
  });

  /// Si la persona dijo que «no era» una tarjeta con esta pregunta en
  /// [itemId] —sin distinguir mayúsculas, acentos ni signos—.
  Future<Either<Failure, bool>> isFlashcardRejected({
    required String itemId,
    required String question,
  });
}
