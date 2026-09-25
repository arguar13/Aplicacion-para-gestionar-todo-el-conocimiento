import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// Cuánto del contenido de un elemento entra en la cita, por defecto. Un
/// fragmento, no el elemento entero: lo que se le pasa al modelo de
/// lenguaje después tiene que caber en su ventana de contexto, y lo que se
/// le muestra a la persona tiene que leerse de un vistazo.
const kChatSourceExcerptLength = 400;

/// Arma el [ChatSource] de [item]: extraído de `LibraryVaultRetriever`
/// (F16, D2) para que un caso de uso que ya sabe qué elementos usar —sin
/// pasar por una búsqueda— no duplique esta lógica (F16, D5/12b): el
/// generador de derivados necesita exactamente el mismo offset real, no
/// una copia que pueda desviarse con el tiempo.
ChatSource buildChatSource(
  KnowledgeItem item, {
  int excerptLength = kChatSourceExcerptLength,
}) {
  final excerpt = _excerptOf(item, excerptLength);
  return ChatSource(
    itemId: item.id,
    itemTitle: item.title,
    excerpt: excerpt.text,
    sourceCharStart: excerpt.start,
    sourceCharEnd: excerpt.end,
  );
}

/// El fragmento a mostrar y, si la fuente tiene chunks de verdad (F16,
/// D2), dónde arranca y termina dentro de su texto principal —para que un
/// derivado (16.2) pueda citarlo con `RelationKind.extractedFrom` en vez
/// de con un fragmento suelto sin origen—.
///
/// El offset sale del texto principal de [item] —la misma forma de la que
/// salen sus chunks, no `item.searchableText` (que junta TODAS sus formas
/// de texto): un elemento con más de una forma de texto tendría, si no,
/// coordenadas que no corresponden a ningún chunk real—. Sin esa forma
/// —una nota manual, que nunca se fragmenta, o algo que no terminó de
/// procesarse—, el fragmento se arma igual, como siempre
/// (`item.searchableText`), solo que sin nada a lo que anclarlo.
({String text, int? start, int? end}) _excerptOf(
  KnowledgeItem item,
  int excerptLength,
) {
  final rendition = _sourceTextOf(item);
  if (rendition == null) {
    return (
      text: _truncate(item, item.searchableText, excerptLength),
      start: null,
      end: null,
    );
  }

  final raw = rendition.content;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return (text: item.subtitle ?? '', start: null, end: null);
  }

  // `trim()` puede sacar espacio de más al principio: el offset real es
  // dónde arranca lo recortado DENTRO del texto sin recortar, no 0 a
  // secas.
  final start = raw.indexOf(trimmed);
  final sliced = trimmed.length <= excerptLength
      ? trimmed
      : trimmed.substring(0, excerptLength);
  final text = sliced.length < trimmed.length ? '$sliced…' : sliced;
  return (text: text, start: start, end: start + sliced.length);
}

String _truncate(KnowledgeItem item, String rawText, int excerptLength) {
  final text = rawText.trim();
  if (text.isEmpty) return item.subtitle ?? '';
  if (text.length <= excerptLength) return text;
  return '${text.substring(0, excerptLength)}…';
}

/// La forma de texto de la que salen los chunks de [item] —misma regla que
/// `sourceTextRendition`/`_pickPrimaryOrOldest` (F10): la principal, o si
/// ninguna lo es, la más vieja—, replicada acá sobre un [item] que ya se
/// trajo cargado, sin una consulta aparte.
///
/// `null` para una nota manual —`_syncChunks` nunca la fragmenta— o para
/// algo que todavía no tiene ninguna forma de texto.
TextRendition? _sourceTextOf(KnowledgeItem item) {
  if (item.source.kind == SourceKind.manualNote) return null;
  final texts = item.renditions.whereType<TextRendition>().toList();
  if (texts.isEmpty) return null;
  for (final rendition in texts) {
    if (rendition.isPrimary) return rendition;
  }
  return (texts..sort((a, b) => a.createdAt.compareTo(b.createdAt))).first;
}
