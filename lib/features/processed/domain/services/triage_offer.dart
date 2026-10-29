import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_source_material.dart';

/// Las secciones que la fuente de [material] ofrece en la hoja «¿Qué va a
/// Procesado?» (F41), en el orden en que se leen.
///
/// - Lo que se copia de la fuente —el texto— y lo que se corta de ella —los
///   fragmentos— necesita su texto: sin él no hay de dónde.
/// - El resumen, la síntesis y las palabras clave no se ofrecen (F43,
///   decisión J): se marcan en el original del documento procesado, con la IA
///   o a mano, y se extraen en Repasar. Lo que un documento ya trajo como
///   sección se queda, y «Volver a triar» no lo toca: no hay edición que
///   pedirle.
/// - Las notas, no: una nota escrita a mano entra aunque la fuente todavía no
///   tenga texto propio (una publicación con el texto solo en su
///   «Contenido»).
/// - Las imágenes, si la fuente trae alguna (decisión L): una foto sin letras
///   no tiene texto y sí tiene qué llevar.
///
/// Un `switch` sin caso por defecto a propósito: una sección nueva no compila
/// hasta decir acá cuándo se ofrece, y con eso la hoja ya la muestra.
List<ProcessedSection> triageSectionsOffered(
  ProcessedSourceMaterial material,
) => [
  for (final section in ProcessedSection.values)
    if (switch (section) {
      ProcessedSection.text || ProcessedSection.fragments => material.hasText,
      ProcessedSection.summary ||
      ProcessedSection.synthesis ||
      ProcessedSection.keywords => false,
      ProcessedSection.notes => true,
      ProcessedSection.images => material.images.count > 0,
    })
      section,
];
