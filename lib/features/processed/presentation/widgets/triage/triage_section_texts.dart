import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

// Cómo se nombra y se cuenta cada sección en la hoja «¿Qué va a Procesado?»
// (F41). Cada `switch` va sin caso por defecto a propósito: una sección nueva
// —las palabras clave, el original— no compila hasta decir acá cómo se llama,
// con qué ícono y cómo se cuentan sus partes, y con eso la hoja ya la muestra.

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
  ProcessedSection.notes => l10n.processedTriageSectionNotes,
  ProcessedSection.fragments => l10n.processedTriageSectionFragments,
};

/// El ícono de [section]: los de estudiar para el resumen y la síntesis, los
/// de la barrita para lo cortado y lo extraído.
IconData triageSectionIcon(ProcessedSection section) => switch (section) {
  ProcessedSection.text => Icons.notes,
  ProcessedSection.summary => Icons.notes_outlined,
  ProcessedSection.synthesis => Icons.filter_center_focus_outlined,
  ProcessedSection.notes => Icons.sticky_note_2_outlined,
  ProcessedSection.fragments => Icons.format_quote_outlined,
};

/// Cuántas partes son [count], dicho como se cuentan en [section]: páginas
/// del texto, oraciones, notas o fragmentos.
String triagePartsText(
  AppLocalizations l10n,
  ProcessedSection section,
  int count,
) => switch (section) {
  ProcessedSection.text => l10n.processedTriagePageCount(count),
  ProcessedSection.summary ||
  ProcessedSection.synthesis => l10n.processedTriageSentenceCount(count),
  ProcessedSection.notes => l10n.processedTriageNoteCount(count),
  ProcessedSection.fragments => l10n.processedTriageFragmentCount(count),
};

/// Lo que se estudia de la fuente para armar [section], si lo arma estudiar
/// (F36): el resumen y la síntesis. Para esas, la hoja ofrece «Resumir con
/// el modelo» o «Elegir a mano» mientras no hay nada.
StudyMarkKind? triageStudyKindOf(ProcessedSection section) => switch (section) {
  ProcessedSection.summary => StudyMarkKind.summary,
  ProcessedSection.synthesis => StudyMarkKind.synthesis,
  ProcessedSection.text ||
  ProcessedSection.notes ||
  ProcessedSection.fragments => null,
};

/// El nombre de [change], para elegirlo al volver a triar (paso 4).
String triageChangeLabel(AppLocalizations l10n, ProcessedChange change) =>
    switch (change) {
      ProcessedChange.add => l10n.processedTriageChangeAdd,
      ProcessedChange.update => l10n.processedTriageChangeUpdate,
      ProcessedChange.replace => l10n.processedTriageChangeReplace,
      ProcessedChange.remove => l10n.processedTriageChangeRemove,
    };
