import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';

part 'processed_source_material.freezed.dart';

/// Una oración del resumen o de la síntesis de una fuente (F36), lista para
/// elegirla: su marca de estudio, dónde está y qué dice.
@freezed
sealed class ProcessedSentence with _$ProcessedSentence {
  const factory ProcessedSentence({
    /// El id de su marca de estudio (`study_marks`): lo que se pasa en
    /// `SectionInput.sentences`.
    required String studyMarkId,
    required ProcessedAnchor anchor,
    required String content,
  }) = _ProcessedSentence;
}

/// Una palabra clave de una fuente (F36, F39): su marca de estudio y dónde está
/// en el texto entero.
@freezed
sealed class ProcessedKeyword with _$ProcessedKeyword {
  const factory ProcessedKeyword({
    /// El id de su marca de estudio: lo que se pasa en
    /// `SectionInput.sentences` para elegir esta palabra.
    required String studyMarkId,
    required int start,
    required int end,
    required String word,
  }) = _ProcessedKeyword;
}

/// Una oración de una fuente con sus palabras clave (v46): la oración, como la
/// corta `splitStudySentences`, y las palabras que tiene adentro, en orden.
@freezed
sealed class ProcessedKeywordSentence with _$ProcessedKeywordSentence {
  const factory ProcessedKeywordSentence({
    required ProcessedAnchor anchor,
    required String content,
    required List<ProcessedKeyword> keywords,
  }) = _ProcessedKeywordSentence;
}

/// El original de una fuente, si se puede copiar a Procesado (decisión H): el
/// archivo de un documento de texto —PDF, Word, EPUB, texto— o la página web
/// archivada.
@freezed
sealed class ProcessedOriginalOffer with _$ProcessedOriginalOffer {
  const factory ProcessedOriginalOffer({
    /// Dónde está el archivo de la fuente.
    required String relativePath,

    /// Cuánto ocupa la copia: lo que avisa la hoja.
    required int sizeBytes,

    /// Qué forma va a ser la copia: `pdf`, `document` o `html`.
    required RenditionKind kind,
  }) = _ProcessedOriginalOffer;
}

/// Lo que una fuente ofrece para procesar (F41), leído sin tocarla: lo que
/// necesita la hoja «¿Qué va a Procesado?» para mostrar cada opción con su
/// vista previa —cuántas oraciones y palabras—.
///
/// No trae el texto entero: un libro de millones de caracteres no viaja a la
/// interfaz para mostrar su largo.
@freezed
sealed class ProcessedSourceMaterial with _$ProcessedSourceMaterial {
  const factory ProcessedSourceMaterial({
    required String sourceItemId,
    required String title,
    required SourceKind sourceKind,

    /// La forma de texto de la que sale todo —la principal, o la más vieja—;
    /// `null` si todavía no tiene texto (se está transcribiendo o leyendo).
    String? textRenditionId,

    /// Cuántos caracteres y palabras tiene ese texto.
    @Default(0) int textCharacters,
    @Default(0) int textWords,

    /// Las oraciones de su resumen y de su síntesis, en el orden del texto.
    /// Vacías si todavía no se resumió.
    @Default(<ProcessedSentence>[]) List<ProcessedSentence> summary,
    @Default(<ProcessedSentence>[]) List<ProcessedSentence> synthesis,

    /// Las oraciones que tienen palabras clave, en el orden del texto, cada una
    /// con las suyas. Vacías si todavía no se marcó ninguna.
    @Default(<ProcessedKeywordSentence>[])
    List<ProcessedKeywordSentence> keywords,

    /// El original que se puede copiar, o `null` si la fuente no lo ofrece: no
    /// es un documento de texto ni una página web, o su archivo ya no está.
    ProcessedOriginalOffer? original,
  }) = _ProcessedSourceMaterial;

  const ProcessedSourceMaterial._();

  /// Si tiene texto que procesar.
  bool get hasText => textRenditionId != null && textCharacters > 0;
}
