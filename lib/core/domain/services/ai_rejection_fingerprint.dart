import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';

/// Cómo se reconoce que algo que la IA propone es lo MISMO que la persona ya
/// dijo que «no era» (F27). Es la clave de `ai_rejections`: un elemento, una
/// clase de cosa y esta huella.
///
/// Funciones puras, sin base, para que quien recuerda y quien consulta —el
/// repositorio que borra, el generador que propone, la fusión de bóvedas—
/// decidan exactamente igual.

/// La clave de un vínculo: el par sin orden y el tipo.
///
/// Sin orden a propósito: si «A continúa a B» no era, «B continúa a A»
/// tampoco es algo que la IA deba ofrecer sola —la persona dijo que esos dos
/// no se unen así—. `itemId` es el menor de los dos ids y `fingerprint` lleva
/// el mayor y el tipo: así cabe en la clave única de la tabla y una fusión la
/// arma igual en SQL (`MIN`/`MAX` de SQLite comparan los ids —UUID en
/// ASCII— en el mismo orden que `compareTo`).
({String itemId, String otherItemId, String fingerprint}) relationRejectionKey({
  required String fromItemId,
  required String toItemId,
  required RelationKind kind,
}) {
  final fromFirst = fromItemId.compareTo(toItemId) <= 0;
  final low = fromFirst ? fromItemId : toItemId;
  final high = fromFirst ? toItemId : fromItemId;
  return (
    itemId: low,
    otherItemId: high,
    fingerprint: relationRejectionFingerprint(
      otherItemId: high,
      kind: kind.name,
    ),
  );
}

/// La huella de un vínculo, ya con el extremo mayor: `<id>:<tipo>`. Es la
/// misma expresión que arma la fusión en SQL.
String relationRejectionFingerprint({
  required String otherItemId,
  required String kind,
}) => '$otherItemId:$kind';

/// La huella de una propiedad en un elemento: la categoría y el valor, por su
/// nombre y sin distinguir mayúsculas ni acentos —el mismo criterio con que el
/// vocabulario decide que dos textos son el mismo valor—.
///
/// Por el nombre y no por el id: los ids de una categoría o un valor cambian
/// al fusionar bóvedas (cada bóveda siembra su «Tema»), el nombre no.
String propertyRejectionFingerprint({
  required String definitionName,
  required String value,
}) =>
    '${normalizeVocabularyLabel(definitionName)}\u001f'
    '${normalizeVocabularyLabel(value)}';

/// La huella de una tarjeta: su pregunta, sin mayúsculas, acentos, signos de
/// pregunta o exclamación ni la puntuación del final. «¿Qué es la entropía?» y
/// «que es la entropia» son la misma pregunta; dos preguntas que difieren en
/// una palabra, no.
String flashcardRejectionFingerprint(String question) {
  final normalized = normalizeVocabularyLabel(
    question.replaceAll(_questionMarks, ' '),
  );
  return normalized.replaceAll(_trailingPunctuation, '');
}

final _questionMarks = RegExp('[¿?¡!]');
final _trailingPunctuation = RegExp(r'[\s.,;:…]+$');
