import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';

/// El texto de [item] del que se pueden sacar notas, o `null` si no tiene.
///
/// Es la forma de texto que no sea de bloques —los bloques son de las notas—, y
/// la principal si sirve. La Bandeja y la vista de lectura tienen que estar de
/// acuerdo en cuál es: las posiciones que se guardan al extraer son de este
/// texto, y volver al fragmento solo funciona sobre el mismo.
TextRendition? extractableRendition(KnowledgeItem item) {
  final texts = item.renditions
      .whereType<TextRendition>()
      .where((r) => r.kind != RenditionKind.blocks)
      .toList();
  if (texts.isEmpty) return null;

  final primary = item.primaryRendition;
  if (primary is TextRendition && primary.kind != RenditionKind.blocks) {
    return primary;
  }
  return texts.first;
}
