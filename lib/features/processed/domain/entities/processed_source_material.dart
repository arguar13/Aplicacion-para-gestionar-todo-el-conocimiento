import 'package:freezed_annotation/freezed_annotation.dart';
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
  }) = _ProcessedSourceMaterial;

  const ProcessedSourceMaterial._();

  /// Si tiene texto que procesar.
  bool get hasText => textRenditionId != null && textCharacters > 0;
}
