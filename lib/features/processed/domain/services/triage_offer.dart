import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_source_material.dart';

/// Las secciones que la fuente de [material] ofrece en la hoja «¿Qué va a
/// Procesado?» (F41), en el orden en que se leen.
///
/// - Lo que se copia de la fuente —el texto, el resumen, la síntesis— y lo que
///   se corta de ella —los fragmentos— necesita su texto: sin él no hay de
///   dónde.
/// - Las notas, no: una nota escrita a mano entra aunque la fuente todavía no
///   tenga texto propio (una publicación con el texto solo en su
///   «Contenido»).
///
/// Un `switch` sin caso por defecto a propósito: una sección nueva no compila
/// hasta decir acá cuándo se ofrece, y con eso la hoja ya la muestra.
List<ProcessedSection> triageSectionsOffered(
  ProcessedSourceMaterial material,
) => [
  for (final section in ProcessedSection.values)
    if (switch (section) {
      ProcessedSection.text ||
      ProcessedSection.summary ||
      ProcessedSection.synthesis ||
      ProcessedSection.fragments => material.hasText,
      ProcessedSection.notes => true,
    })
      section,
];
