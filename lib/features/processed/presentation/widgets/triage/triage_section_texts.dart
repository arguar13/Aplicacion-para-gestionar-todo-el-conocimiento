import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

// Cómo se nombra y se cuenta cada sección en la hoja «¿Qué va a Procesado?»
// (F41). Cada `switch` va sin caso por defecto a propósito: una sección nueva
// no compila hasta decir acá cómo se llama, con qué ícono y cómo se cuentan
// sus partes, y con eso la hoja ya la muestra.

/// El nombre de [section]. En un audio o un video, el texto es su
/// transcripción ([transcript]).
String triageSectionLabel(
  AppLocalizations l10n,
  ProcessedSection section, {
  bool transcript = false,
}) => switch (section) {
  ProcessedSection.text =>
    transcript
        ? l10n.processedTriageSectionTranscript
        : l10n.processedTriageSectionText,
  ProcessedSection.summary => l10n.processedTriageSectionSummary,
  ProcessedSection.synthesis => l10n.processedTriageSectionSynthesis,
  ProcessedSection.keywords => l10n.processedTriageSectionKeywords,
  ProcessedSection.notes => l10n.processedTriageSectionNotes,
  ProcessedSection.fragments => l10n.processedTriageSectionFragments,
  ProcessedSection.images => l10n.processedSectionImages,
};

/// El ícono de [section]: los de estudiar para el resumen, la síntesis y las
/// palabras clave, los de la barrita para lo cortado y lo extraído.
IconData triageSectionIcon(ProcessedSection section) => switch (section) {
  ProcessedSection.text => Icons.notes,
  ProcessedSection.summary => Icons.notes_outlined,
  ProcessedSection.synthesis => Icons.filter_center_focus_outlined,
  ProcessedSection.keywords => Icons.key_outlined,
  ProcessedSection.notes => Icons.sticky_note_2_outlined,
  ProcessedSection.fragments => Icons.format_quote_outlined,
  ProcessedSection.images => Icons.photo_library_outlined,
};

/// Cuántas partes son [count], dicho como se cuentan en [section]: páginas
/// del texto, oraciones —también las de las palabras clave: cada parte es la
/// oración que las lleva—, notas, fragmentos o imágenes.
String triagePartsText(
  AppLocalizations l10n,
  ProcessedSection section,
  int count,
) => switch (section) {
  ProcessedSection.text => l10n.processedTriagePageCount(count),
  ProcessedSection.summary ||
  ProcessedSection.synthesis ||
  ProcessedSection.keywords => l10n.processedTriageSentenceCount(count),
  ProcessedSection.notes => l10n.processedTriageNoteCount(count),
  ProcessedSection.fragments => l10n.processedTriageFragmentCount(count),
  ProcessedSection.images => l10n.processedImageCount(count),
};

/// Lo que se estudia de la fuente para armar [section], si lo arma estudiar
/// (F36, F39): el resumen, la síntesis y las palabras clave. Para esas, la
/// hoja ofrece «Resumir con el modelo» o «Elegir a mano» mientras no hay
/// nada.
StudyMarkKind? triageStudyKindOf(ProcessedSection section) => switch (section) {
  ProcessedSection.summary => StudyMarkKind.summary,
  ProcessedSection.synthesis => StudyMarkKind.synthesis,
  ProcessedSection.keywords => StudyMarkKind.keyword,
  ProcessedSection.text ||
  ProcessedSection.notes ||
  ProcessedSection.fragments ||
  ProcessedSection.images => null,
};

/// Cuánto trae hoy la fuente de lo que se estudia para [section]
/// ([triageStudyKindOf]), contado como lo cuenta estudiar: oraciones del
/// resumen o de la síntesis, palabras clave.
String triageStudiedCountText(
  AppLocalizations l10n,
  ProcessedSection section,
  int count,
) => triageStudyKindOf(section) == StudyMarkKind.keyword
    ? l10n.studyKeywordCount(count)
    : l10n.processedTriageSentenceCount(count);

/// El nombre de [change], para elegirlo al volver a triar (paso 4).
String triageChangeLabel(AppLocalizations l10n, ProcessedChange change) =>
    switch (change) {
      ProcessedChange.add => l10n.processedTriageChangeAdd,
      ProcessedChange.update => l10n.processedTriageChangeUpdate,
      ProcessedChange.replace => l10n.processedTriageChangeReplace,
      ProcessedChange.remove => l10n.processedTriageChangeRemove,
    };
