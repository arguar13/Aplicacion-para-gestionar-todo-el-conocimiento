import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';

part 'section_edit.freezed.dart';

/// Qué hacer con una sección al procesar o volver a triar (F41, paso 4 del
/// plan: «por cada parte se elige»).
enum ProcessedChange {
  /// Suma lo nuevo sin repetir lo que ya está: el mismo tramo de la fuente o el
  /// mismo texto no entran dos veces.
  add,

  /// Trae la versión de ahora de la fuente —su texto, su resumen, su síntesis—
  /// y conserva lo editado a mano donde no choca: ver
  /// `planSectionChange` para la regla exacta.
  update,

  /// Pisa la sección entera con lo nuevo.
  replace,

  /// Saca la sección entera.
  remove,
}

/// De dónde sale lo nuevo de una sección (F41).
@freezed
sealed class SectionInput with _$SectionInput {
  /// La versión de ahora en la fuente: el texto entero, o todas las oraciones
  /// de su resumen, de su síntesis o con palabras clave. Solo para esas
  /// cuatro secciones.
  const factory SectionInput.fromSource() = FromSource;

  /// Algunas oraciones del resumen o de la síntesis, por el id de su marca de
  /// estudio (`study_marks`): lo que la persona eligió en la hoja. En las
  /// palabras clave, los ids son los de las palabras elegidas: entra cada
  /// oración que tiene alguna, con solo esas.
  const factory SectionInput.sentences(Set<String> studyMarkIds) =
      FromSentences;

  /// Lo que la persona puso: notas (escritas o extraídas) y fragmentos
  /// (cortados).
  const factory SectionInput.drafts(List<ProcessedDraft> drafts) = FromDrafts;

  /// Las imágenes de la fuente que se eligieron (decisión L): todas, o solo
  /// algunas.
  const factory SectionInput.images(ImageChoice choice) = FromImages;
}

/// Lo que se le pide a una sección: un cambio y, si hace falta, de dónde sale
/// lo nuevo.
@freezed
sealed class SectionEdit with _$SectionEdit {
  const factory SectionEdit({
    required ProcessedChange change,
    SectionInput? input,
  }) = _SectionEdit;

  const SectionEdit._();

  /// Agregar [input] sin repetir.
  factory SectionEdit.add(SectionInput input) =>
      SectionEdit(change: ProcessedChange.add, input: input);

  /// Reemplazar la sección entera por [input].
  factory SectionEdit.replace(SectionInput input) =>
      SectionEdit(change: ProcessedChange.replace, input: input);

  /// Traer la versión de ahora de la fuente, conservando lo editado.
  factory SectionEdit.update() => const SectionEdit(
    change: ProcessedChange.update,
    input: SectionInput.fromSource(),
  );

  /// Sacar la sección.
  factory SectionEdit.remove() =>
      const SectionEdit(change: ProcessedChange.remove);

  /// Lo que falla para pedírselo a [section], o `null` si se puede.
  String? problemFor(ProcessedSection section) {
    final input = this.input;
    switch (change) {
      case ProcessedChange.remove:
        return input == null ? null : 'Quitar una sección no lleva nada nuevo.';
      case ProcessedChange.update:
        if (!section.canUpdate) {
          return 'La sección ${section.name} no tiene una versión en la '
              'fuente que traer.';
        }
        return input is FromSource
            ? null
            : 'Actualizar trae la versión de la fuente.';
      case ProcessedChange.add:
      case ProcessedChange.replace:
        if (input == null) return 'Falta qué poner en la sección.';
    }
    return switch ((section, input)) {
      (ProcessedSection.text, FromSource()) => null,
      (_, FromSource()) when section.isStudy => null,
      (_, FromSentences(:final studyMarkIds)) when section.isStudy =>
        studyMarkIds.isEmpty ? 'No se eligió ninguna oración.' : null,
      (ProcessedSection.notes, FromDrafts(:final drafts)) => _draftsProblem(
        drafts,
        cutsOnly: false,
      ),
      (ProcessedSection.fragments, FromDrafts(:final drafts)) => _draftsProblem(
        drafts,
        cutsOnly: true,
      ),
      (ProcessedSection.images, FromImages(:final choice)) =>
        choice == ImageChoice.none ? 'No se eligió ninguna imagen.' : null,
      _ => 'La sección ${section.name} no admite eso.',
    };
  }

  static String? _draftsProblem(
    List<ProcessedDraft> drafts, {
    required bool cutsOnly,
  }) {
    if (drafts.isEmpty) return 'No hay nada que poner.';
    for (final draft in drafts) {
      final problem = switch (draft) {
        ProcessedCut(:final anchor) => anchor.problem,
        ProcessedWritten() when cutsOnly =>
          'Un fragmento se corta del original: no se escribe.',
        ProcessedWritten(:final content, :final anchor) =>
          content.trim().isEmpty
              ? 'Una nota vacía no se guarda.'
              : anchor?.problem,
      };
      if (problem != null) return problem;
    }
    return null;
  }
}
