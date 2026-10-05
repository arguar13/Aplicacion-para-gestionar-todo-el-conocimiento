import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';

/// Lo que la IA hizo sola y lo que no tiene que volver a hacer (F27).
///
/// Una pasada se abre con [startRun] antes de aplicar nada; cada vínculo,
/// tarjeta o propiedad que la IA crea lleva su id (`AiProvenance`), y el tema
/// y los datos de la referencia que completa quedan anotados con ella
/// ([applySpace], [completeReference]). Por eso se puede deshacer entera
/// ([undoRun]) o todo lo de un elemento ([undoItem]). Deshacer se lleva solo
/// lo que sigue siendo de la IA: lo que la persona editó ya es suyo y no se
/// toca.
///
/// La memoria de lo que «no era» la escriben los repositorios que borran
/// —`OrganizeRepository.rejectAiRelation`, `FlashcardRepository.
/// rejectAiFlashcard`…—; acá se consulta antes de proponer nada.
abstract interface class AiRunRepository {
  /// Abre una pasada de la IA sobre [itemId] y devuelve su id. [model] es el
  /// modelo que trabaja, si se sabe; [contentSimhash], la huella del texto que
  /// la pasada va a ver (`simhashOf`), con la que después se sabe si cambió.
  ///
  /// Con [scope] en [AiRunScope.flashcards], es un pedido de solo tarjetas
  /// (F30, el ✨ de Repasar): se deshace y se lista como cualquier pasada,
  /// pero no cuenta como organizar el elemento —sigue pendiente para la
  /// cola, con sus vínculos, temas y etiquetas por hacer— ni como su última
  /// pasada a la hora de saber si se deshizo ([undoneItemsAmong]).
  Future<Either<Failure, String>> startRun(
    String itemId, {
    String? model,
    String? contentSimhash,
    AiRunScope scope = AiRunScope.organize,
  });

  /// Pone a [itemId] en el tema [spaceId] dentro de la pasada [runId], si
  /// todavía no tiene ninguno —lo que eligió la persona, también mientras el
  /// modelo pensaba, no se toca—. Devuelve si lo puso. Deshacer la pasada lo
  /// saca, si sigue en ese tema.
  Future<Either<Failure, bool>> applySpace({
    required String runId,
    required String itemId,
    required String spaceId,
  });

  /// Completa, dentro de la pasada [runId], **solo los datos vacíos** de la
  /// referencia de [itemId] con [extracted] —nunca pisa lo que escribió la
  /// persona— y da por aceptada la sugerencia de datos que estuviera
  /// pendiente. Devuelve cuántos datos completó. Deshacer la pasada vacía de
  /// nuevo los que siguen con lo que puso la IA.
  Future<Either<Failure, int>> completeReference({
    required String runId,
    required String itemId,
    required ExtractedMetadata extracted,
  });

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
  /// lleva su id y sigue siendo de la IA, devuelve el tema y los datos de la
  /// referencia que completó a como estaban —si siguen con lo que puso la
  /// IA—, devuelve a la raíz los temas que ubicó en el árbol —si siguen
  /// donde ella los puso— y la marca como deshecha. Lo que la persona adoptó
  /// o cambió queda.
  /// Devuelve cuánto se deshizo; deshacer dos veces no toca nada la segunda.
  ///
  /// Deshacer no es «no era»: no recuerda nada, porque la persona no dijo que
  /// esté mal, dijo que no lo quiere ahora. La pasada deshecha queda, y es la
  /// que le dice a la cola que no vuelva a organizar sola ese elemento.
  Future<Either<Failure, AiRunTally>> undoRun(String runId);

  /// Deshace todas las pasadas de [itemId] que siguen en pie, en una sola
  /// transacción. Devuelve cuánto se borró en total.
  Future<Either<Failure, AiRunTally>> undoItem(String itemId);

  /// De [itemIds], los que tienen deshecha su última pasada: la persona no
  /// quiere lo que la IA hizo con ellos, y la IA no vuelve a tocarlos sola
  /// —ni para organizarlos, ni para vincularlos desde otro elemento—, hasta
  /// que alguien pida organizarlos de nuevo.
  Future<Either<Failure, Set<String>>> undoneItemsAmong(
    Iterable<String> itemIds,
  );

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
