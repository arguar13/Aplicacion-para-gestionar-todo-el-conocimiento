import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

part 'processed_document.freezed.dart';

/// Un documento procesado tal como se lista en «Procesado» (F41): lo que hace
/// falta para una fila —título, ícono del origen, qué partes tiene, cuándo se
/// actualizó— y nada que mida lo que mide el texto. Un libro de millones de
/// caracteres cuesta en la lista lo mismo que una nota.
@freezed
sealed class ProcessedDocumentSummary with _$ProcessedDocumentSummary {
  const factory ProcessedDocumentSummary({
    /// El id del elemento procesado (`item.id`): sale de la fuente
    /// (`processedDocumentIdFor`).
    required String id,
    required String title,

    /// De qué tipo era la fuente: el ícono de la fila.
    required SourceKind sourceKind,
    required DateTime createdAt,

    /// Cuándo se tocó por última vez su contenido o su título: el orden de la
    /// lista.
    required DateTime updatedAt,

    /// La versión de su fila (`item.rev`): sube con cada cambio, aunque caiga
    /// en el mismo segundo que el anterior. Es lo que hay que mirar para saber
    /// si cambió: [updatedAt] se guarda en segundos y dos cambios seguidos
    /// pueden dar la misma hora.
    required int rev,

    /// Cuántas partes tiene cada sección. Una sección sin partes no está.
    required Map<ProcessedSection, int> partCounts,

    /// La fuente de la que salió, para «Ver el original en la Biblioteca».
    /// `null` si la fuente se borró de verdad.
    String? sourceItemId,

    /// Sus temas (F37), como los de cualquier elemento.
    @Default(<String>{}) Set<String> spaceIds,

    /// Si tiene la copia del original (decisión H): el chip «Original».
    @Default(false) bool hasOriginal,
  }) = _ProcessedDocumentSummary;

  const ProcessedDocumentSummary._();

  /// Las secciones que tiene, en el orden en que se leen: los chips de la fila.
  List<ProcessedSection> get sections => [
    for (final section in ProcessedSection.values)
      if ((partCounts[section] ?? 0) > 0) section,
  ];

  /// Si no le queda nada: ni partes ni la copia del original.
  bool get isEmpty => sections.isEmpty && !hasOriginal;
}

/// Cuánto hay en una sección de un documento procesado.
@freezed
sealed class ProcessedSectionStats with _$ProcessedSectionStats {
  const factory ProcessedSectionStats({
    /// Cuántas partes: páginas del texto, oraciones, notas o fragmentos.
    required int parts,

    /// Cuántos caracteres suman.
    required int characters,

    /// Cuántas partes copiadas editó la persona.
    required int edited,
  }) = _ProcessedSectionStats;
}

/// La fuente de un documento procesado, para su enlace.
@freezed
sealed class ProcessedSourceLink with _$ProcessedSourceLink {
  const factory ProcessedSourceLink({
    required String itemId,
    required String title,

    /// Si la fuente está en la papelera: el enlace la abre igual, avisando.
    required bool inTrash,
  }) = _ProcessedSourceLink;
}

/// Un documento procesado abierto (F41): su fila más lo que cuesta un poco más
/// saber —cuánto texto tiene cada sección, cómo se llama su fuente—. Sus partes
/// se piden aparte, sección por sección y, las del texto, de a páginas
/// (`ProcessedRepository.watchParts`): nunca viaja el libro entero.
@freezed
sealed class ProcessedDocument with _$ProcessedDocument {
  const factory ProcessedDocument({
    required ProcessedDocumentSummary summary,
    required Map<ProcessedSection, ProcessedSectionStats> stats,

    /// Si el procesado está en la papelera.
    required bool inTrash,

    /// La fuente, si todavía existe.
    ProcessedSourceLink? source,
  }) = _ProcessedDocument;

  const ProcessedDocument._();

  String get id => summary.id;
  String get title => summary.title;
}
