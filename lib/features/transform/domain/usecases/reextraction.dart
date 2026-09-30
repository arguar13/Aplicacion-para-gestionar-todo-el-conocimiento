import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';

/// La forma de texto principal de [item]: la marcada como principal, o si no
/// la primera de texto. `null` si no tiene texto.
TextRendition? primaryTextOf(KnowledgeItem item) {
  final texts = item.renditions.whereType<TextRendition>();
  return texts.where((r) => r.isPrimary).firstOrNull ?? texts.firstOrNull;
}

/// Lo que queda de [original] después de volver a extraerle el texto, con
/// lo que trajo el transformador en [enriched] (F22).
///
/// El texto nuevo toma el LUGAR del viejo: la misma forma —el mismo
/// identificador—, con el contenido nuevo. Así los subrayados, que cuelgan
/// de la forma y se borran con ella, no se pierden: se reubican después
/// (ver `TextAnchorRelocator`). El resto de las formas del elemento —la
/// segunda forma de texto de dos duplicados fusionados, por ejemplo— quedan
/// como estaban.
///
/// Si el transformador no trajo texto —el motor no oyó nada, la página ya no
/// está—, el texto viejo queda: volver a extraer nunca deja un elemento con
/// menos de lo que tenía.
KnowledgeItem replaceExtractedText({
  required KnowledgeItem original,
  required KnowledgeItem enriched,
}) {
  final oldPrimary = primaryTextOf(original);
  final oldIds = {for (final r in original.renditions) r.id};
  final fresh = enriched.renditions
      .whereType<TextRendition>()
      .where((r) => !oldIds.contains(r.id))
      .toList();
  final newPrimary =
      fresh.where((r) => r.isPrimary).firstOrNull ?? fresh.firstOrNull;

  if (newPrimary == null || newPrimary.content.trim().isEmpty) {
    return enriched.copyWith(renditions: original.renditions);
  }
  if (oldPrimary == null) {
    return enriched.copyWith(
      renditions: [...original.renditions, newPrimary],
    );
  }
  return enriched.copyWith(
    renditions: [
      for (final r in original.renditions)
        if (r.id == oldPrimary.id)
          newPrimary.copyWith(
            id: oldPrimary.id,
            isPrimary: oldPrimary.isPrimary,
            createdAt: oldPrimary.createdAt,
          )
        else
          r,
    ],
  );
}

/// Un subrayado que no se encontró en el texto nuevo: lo que el usuario
/// había marcado y lo que le había anotado.
typedef LostHighlight = ({String excerpt, String? note});

/// [notes] —las notas libres del elemento— con los subrayados que no se
/// encontraron en el texto nuevo agregados al final, citados, con su nota
/// (F22). Así no se pierde nada de lo que el usuario había marcado: queda a
/// la vista, en el elemento, aunque ya no tenga dónde pintarse.
String notesWithLostHighlights(String? notes, List<LostHighlight> lost) {
  if (lost.isEmpty) return notes ?? '';
  final block = StringBuffer(
    'Subrayados que no se encontraron en el texto nuevo:',
  );
  for (final highlight in lost) {
    block.write('\n\n> ${highlight.excerpt.replaceAll('\n', '\n> ')}');
    final note = highlight.note?.trim();
    if (note != null && note.isNotEmpty) block.write('\n\n$note');
  }
  final before = notes?.trimRight() ?? '';
  return before.isEmpty ? block.toString() : '$before\n\n$block';
}
