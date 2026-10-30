import 'package:meta/meta.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';

/// De qué texto es una nota (F45, mejora 19, decisión I): cada texto, por su
/// clave (decisión H). Nada de uno aparece en otro: la Biblioteca y Procesado
/// no se mezclan, y tampoco la copia del original con el texto procesado.
///
/// - [SourceOriginalNotes]: el original de una fuente de la Biblioteca. Sus
///   notas se escriben sobre su texto extraído, y con ellas se leen las notas
///   de los resaltados de antes (F38).
/// - [ProcessedOriginalNotes]: la copia del original de un documento
///   procesado, con las posiciones del texto de la fuente con que se
///   corresponde, como lo elegido del procesado.
/// - [ProcessedTextNotes]: el texto propio de un documento procesado, y lo que
///   se lee de él —el resumen y la síntesis son sus oraciones, en sus
///   posiciones—: una nota puesta leyendo el resumen está también en el texto
///   completo, en el mismo lugar.
/// - [CreationNotes]: lo creado en Repasar (un informe, una presentación…).
@immutable
sealed class TextNoteTarget {
  /// El original de la fuente [sourceId] de la Biblioteca, cuyo texto
  /// extraído es la forma [renditionId].
  const factory TextNoteTarget.sourceOriginal({
    required String sourceId,
    required String renditionId,
  }) = SourceOriginalNotes;

  /// La copia del original del documento procesado [documentId].
  const factory TextNoteTarget.processedOriginal(String documentId) =
      ProcessedOriginalNotes;

  /// El texto propio del documento procesado [documentId].
  const factory TextNoteTarget.processedText(String documentId) =
      ProcessedTextNotes;

  /// La creación [creationId] de Repasar.
  const factory TextNoteTarget.creation(String creationId) = CreationNotes;

  const TextNoteTarget._();

  /// Cómo se guarda la clase en `text_notes.target`. Estable: no se renombra.
  String get storageKey;

  /// El elemento de la nota —la fuente o el documento procesado—, o `null` en
  /// una creación.
  String? get itemId;

  /// La forma de texto sobre la que se escriben las notas nuevas, solo en el
  /// original de la Biblioteca.
  String? get renditionId => null;

  /// La creación de la nota, o `null` si no es de una.
  String? get creationId => null;
}

/// El original de una fuente de la Biblioteca: ver [TextNoteTarget].
final class SourceOriginalNotes extends TextNoteTarget {
  const SourceOriginalNotes({required this.sourceId, required this.renditionId})
    : super._();

  final String sourceId;

  @override
  final String renditionId;

  @override
  String get storageKey => kSourceOriginalNotes;

  @override
  String get itemId => sourceId;

  @override
  bool operator ==(Object other) =>
      other is SourceOriginalNotes &&
      other.sourceId == sourceId &&
      other.renditionId == renditionId;

  @override
  int get hashCode => Object.hash(storageKey, sourceId, renditionId);

  @override
  String toString() => 'TextNoteTarget.sourceOriginal($sourceId, $renditionId)';
}

/// La copia del original de un documento procesado: ver [TextNoteTarget].
final class ProcessedOriginalNotes extends TextNoteTarget {
  const ProcessedOriginalNotes(this.documentId) : super._();

  final String documentId;

  @override
  String get storageKey => kProcessedOriginalNotes;

  @override
  String get itemId => documentId;

  @override
  bool operator ==(Object other) =>
      other is ProcessedOriginalNotes && other.documentId == documentId;

  @override
  int get hashCode => Object.hash(storageKey, documentId);

  @override
  String toString() => 'TextNoteTarget.processedOriginal($documentId)';
}

/// El texto propio de un documento procesado: ver [TextNoteTarget].
final class ProcessedTextNotes extends TextNoteTarget {
  const ProcessedTextNotes(this.documentId) : super._();

  final String documentId;

  @override
  String get storageKey => kProcessedTextNotes;

  @override
  String get itemId => documentId;

  @override
  bool operator ==(Object other) =>
      other is ProcessedTextNotes && other.documentId == documentId;

  @override
  int get hashCode => Object.hash(storageKey, documentId);

  @override
  String toString() => 'TextNoteTarget.processedText($documentId)';
}

/// Lo creado en Repasar: ver [TextNoteTarget].
final class CreationNotes extends TextNoteTarget {
  const CreationNotes(this.id) : super._();

  final String id;

  @override
  String get storageKey => kCreationNotes;

  @override
  String? get itemId => null;

  @override
  String get creationId => id;

  @override
  bool operator ==(Object other) => other is CreationNotes && other.id == id;

  @override
  int get hashCode => Object.hash(storageKey, id);

  @override
  String toString() => 'TextNoteTarget.creation($id)';
}

/// Las claves de [TextNoteTarget.storageKey]: las mismas que permite la
/// restricción de `text_notes.target`.
const kSourceOriginalNotes = 'source_original';
const kProcessedOriginalNotes = 'processed_original';
const kProcessedTextNotes = 'processed_text';
const kCreationNotes = 'creation';

/// De qué texto son las notas de lo que el lector muestra como [text]: la
/// misma clave con que se miran sus marcas (`StudyText.renditionId`) dice cuál
/// es.
///
/// - la de la copia del original de un procesado (`procesado-original:…`), la
///   copia;
/// - la del texto propio de un procesado (`procesado:…`), su texto —también
///   cuando se lee su resumen o su síntesis—;
/// - cualquier otra es la forma de texto de una fuente: su original de la
///   Biblioteca.
///
/// Lo creado no se lee como un `StudyText`: su lector usa
/// [TextNoteTarget.creation].
TextNoteTarget textNoteTargetOf(StudyText text) {
  final key = text.renditionId;
  if (processedDocumentOfOriginalStudyKey(key) case final documentId?) {
    return TextNoteTarget.processedOriginal(documentId);
  }
  if (processedDocumentOfStudyKey(key) case final documentId?) {
    return TextNoteTarget.processedText(documentId);
  }
  return TextNoteTarget.sourceOriginal(sourceId: text.itemId, renditionId: key);
}
