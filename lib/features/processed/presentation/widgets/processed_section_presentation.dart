import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se ve cada sección de un documento procesado (F41): su ícono, su
/// nombre y cómo se cuentan sus partes.
///
/// En un solo lugar, como `SourceKindPresentation`: el mismo par ícono-nombre
/// sale en el chip de la fila, en el filtro y en el encabezado de la sección
/// del documento abierto. Los `switch` son exhaustivos a propósito: una
/// sección nueva no compila hasta decir cómo se ve.
extension ProcessedSectionPresentation on ProcessedSection {
  IconData get icon => switch (this) {
    ProcessedSection.text => Icons.notes_outlined,
    ProcessedSection.summary => Icons.short_text,
    ProcessedSection.synthesis => Icons.compress,
    ProcessedSection.keywords => Icons.key_outlined,
    ProcessedSection.notes => Icons.sticky_note_2_outlined,
    ProcessedSection.fragments => Icons.content_cut,
  };

  String label(AppLocalizations l10n) => switch (this) {
    ProcessedSection.text => l10n.processedSectionText,
    ProcessedSection.summary => l10n.processedSectionSummary,
    ProcessedSection.synthesis => l10n.processedSectionSynthesis,
    ProcessedSection.keywords => l10n.processedSectionKeywords,
    ProcessedSection.notes => l10n.processedSectionNotes,
    ProcessedSection.fragments => l10n.processedSectionFragments,
  };

  /// Cuántas partes tiene, con su nombre: «12 páginas», «8 oraciones». Una
  /// parte de las palabras clave es la oración que las lleva.
  String countLabel(AppLocalizations l10n, int count) => switch (this) {
    ProcessedSection.text => l10n.processedPageCount(count),
    ProcessedSection.summary ||
    ProcessedSection.synthesis ||
    ProcessedSection.keywords => l10n.studySentenceCount(count),
    ProcessedSection.notes => l10n.processedNoteCount(count),
    ProcessedSection.fragments => l10n.processedFragmentCount(count),
  };

  /// Si se abre desplegada. El texto entero no, si hay algo más que leer: un
  /// libro taparía todo lo demás; lo elegido —resumen, síntesis, palabras
  /// clave, notas, fragmentos— es corto y es lo que se vino a ver.
  bool startsExpanded({required bool alone}) => switch (this) {
    ProcessedSection.text => alone,
    ProcessedSection.summary ||
    ProcessedSection.synthesis ||
    ProcessedSection.keywords ||
    ProcessedSection.notes ||
    ProcessedSection.fragments => true,
  };
}
