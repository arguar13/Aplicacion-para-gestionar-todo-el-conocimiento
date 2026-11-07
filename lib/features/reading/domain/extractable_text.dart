import 'package:sinapsis/core/domain/entities/content_block.dart';
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

/// Una nota de bloques para leer: su forma de bloques y sus bloques.
typedef ReadableBlocks = ({TextRendition rendition, List<ContentBlock> blocks});

/// La nota de bloques de [item] para leerla en el lector (F46, paso 5j,
/// decisión 2a del dueño), o `null` si no es una o no tiene nada escrito.
///
/// La nota se lee como se ve en su detalle —sus bloques, con sus títulos,
/// sus listas y sus casilleros—, pero **de solo lectura**: no se resalta, ni
/// se extrae, ni se le hacen tarjetas. Lo que se ancla a un texto guarda sus
/// posiciones, y las de una nota se corren cada vez que se edita; por eso una
/// nota de bloques no tiene [extractableRendition] (las tarjetas que la IA
/// saca de ella quedan sin fragmento).
///
/// Un JSON que no se puede leer no rompe nada: la nota no se ofrece para leer
/// (`tryDecodeContentBlocks`).
ReadableBlocks? readableBlocksOf(KnowledgeItem item) {
  final rendition = item.renditions
      .whereType<TextRendition>()
      .where((r) => r.kind == RenditionKind.blocks)
      .firstOrNull;
  if (rendition == null) return null;
  final blocks = tryDecodeContentBlocks(rendition.content);
  if (blocks == null || blocks.every((block) => block.text.trim().isEmpty)) {
    return null;
  }
  return (rendition: rendition, blocks: blocks);
}

/// Si [item] tiene algo que abra el lector: el texto de una fuente
/// ([extractableRendition]) o una nota de bloques escrita
/// ([readableBlocksOf]). «Leer» del panel de la fuente se apaga si no.
bool hasReadingText(KnowledgeItem item) =>
    extractableRendition(item) != null || readableBlocksOf(item) != null;
