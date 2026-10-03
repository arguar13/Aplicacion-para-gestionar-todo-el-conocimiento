import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_atlas.dart';

/// Lo que el Atlas de la IA (F27) lee y escribe: el árbol de temas, las notas
/// mapa y las propuestas de madurez.
///
/// El Atlas mismo (F13) sigue siendo de solo lectura y se calcula de las
/// propiedades y las notas: lo que hace la IA es escribir en esas mismas
/// fuentes —el padre de un tema, una nota mapa con su tema— y el Atlas lo
/// muestra solo, como si lo hubiera hecho la persona.
///
/// Sin esquema nuevo. Lo que la IA ubica en el árbol queda registrado como
/// una sugerencia `topicParent` aceptada, con su pasada (`atlas_suggestions`):
/// el lugar de un tema es una columna del vocabulario y no tiene `ai_run_id`.
/// Una nota mapa de la IA es una nota generada (`generated_by_model`, como los
/// derivados de F16) con su propia pasada, que anota que la creó entera:
/// deshacerla la manda a la papelera.
abstract interface class AiAtlasRepository {
  /// El árbol de la categoría «Tema».
  Future<Either<Failure, AtlasTopicTree>> topicTree();

  /// Si la IA ya decidió algo sobre el lugar del tema [valueId] —lo ubicó, lo
  /// propuso, se descartó o se deshizo—: entonces no lo vuelve a tocar sola.
  Future<Either<Failure, bool>> hasPlacementRecord(String valueId);

  /// Ubica sola el tema [valueId] bajo [parentId], en la pasada [runId] sobre
  /// [itemId], y lo registra para poder deshacerlo. `right(false)`, sin tocar
  /// nada, si el tema dejó de estar suelto mientras el modelo pensaba —la
  /// persona lo ubicó o le colgó un subtema— o si ese lugar no es posible.
  Future<Either<Failure, bool>> applyTopicPlacement({
    required String itemId,
    required String runId,
    required String valueId,
    required String parentId,
  });

  /// Deja en «Para revisar» poner [valueId] bajo [parentId], agrupado con
  /// [itemId].
  Future<Either<Failure, Unit>> proposeTopicPlacement({
    required String itemId,
    required String valueId,
    required String parentId,
  });

  /// «No era» una ubicación que la IA aplicó sola —la sugerencia
  /// [suggestionId]—: el tema vuelve a la raíz si sigue donde ella lo puso, y
  /// la IA no lo vuelve a ubicar. `right(false)` si la persona ya lo había
  /// movido: queda donde ella lo puso.
  Future<Either<Failure, bool>> undoTopicPlacement(String suggestionId);

  /// Lo que junta la rama [branchValueIds] —un tema y sus subtemas—: los
  /// elementos vivos que tienen puesto alguno, sin las notas mapa.
  Future<Either<Failure, List<TopicMaterial>>> topicMaterial(
    Set<String> branchValueIds,
  );

  /// El comienzo del texto de cada uno de [itemIds], de hasta [chars]
  /// caracteres, para que el modelo sepa de qué trata. Uno sin texto no está.
  Future<Either<Failure, Map<String, String>>> excerptsOf(
    List<String> itemIds, {
    required int chars,
  });

  /// Las notas mapa vivas del tema [valueId], de la más vieja a la más nueva.
  Future<Either<Failure, List<TopicMapNote>>> mapNotesOf(String valueId);

  /// Si la persona ya le sacó al tema [valueId] una nota mapa: hay una en la
  /// papelera con ese tema, la IA ya le creó una que hoy no es su nota mapa
  /// viva —le deshicieron la pasada, la borraron, le sacaron el tema, aunque
  /// después la hayan recuperado—, o dijo que el tema «no era» en una nota
  /// mapa de la IA. Entonces la IA no crea otra.
  Future<Either<Failure, bool>> mapNoteDeclined(String valueId);

  /// Crea la nota mapa de la IA del tema [valueId]: una nota de tipo mapa
  /// con [title] y [blocks], marcada como generada por [model], con el tema
  /// puesto por la IA en su propia pasada, que anota que la creó. Todo junto,
  /// o nada. `right(null)`, sin crear nada, si el tema ya tiene una nota mapa
  /// —alguien la hizo mientras el modelo escribía—.
  Future<Either<Failure, String?>> createMapNote({
    required String valueId,
    required String title,
    required List<ContentBlock> blocks,
    required String model,
  });

  /// Reemplaza el contenido de la nota mapa de la IA [noteId] por [blocks],
  /// solo si sigue siendo la que la IA escribió: su contenido es todavía
  /// [expectedContent] y nadie la editó ni se la sacó a la IA. `right(false)`,
  /// sin tocar nada, si no.
  Future<Either<Failure, bool>> updateMapNote({
    required String noteId,
    required String? expectedContent,
    required List<ContentBlock> blocks,
  });

  /// Cuánto creció la nota [itemId]; `right(null)` si no es una nota viva de
  /// la bóveda.
  Future<Either<Failure, NoteGrowth?>> noteGrowth(String itemId);

  /// Deja en «Para revisar» subir la madurez de la nota [itemId] de [from] a
  /// [to]. Nunca la cambia.
  Future<Either<Failure, Unit>> proposeMaturity({
    required String itemId,
    required NoteMaturity from,
    required NoteMaturity to,
  });
}
