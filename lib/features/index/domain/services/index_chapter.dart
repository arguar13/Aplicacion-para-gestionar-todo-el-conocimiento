import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/processed/domain/services/headings/heading_text.dart';

// Lo que hace falta de un capítulo para lo que se hace con él (F46, paso 4):
// su texto —para «Preguntar al chat»— y qué título es entre los iguales
// —para «Abrir en el original» en una página web—. Puro.

/// Lo más largo que viaja del texto de un capítulo al chat: alcanza para que
/// la conversación sepa de qué se habla, sin llenarle la ventana al modelo con
/// un capítulo de un libro.
const kIndexChapterPassageChars = 2000;

/// El tramo `[start, end)` del texto propio que es el capítulo [entry] de
/// [entries] (las de su documento, en su orden): desde su título hasta el
/// título siguiente de su nivel o de uno más alto —sus subcapítulos son
/// suyos—, o hasta el final. «Texto completo», el texto entero. `null` en una
/// imagen o en un capítulo sin lugar en el texto.
({int start, int? end})? indexChapterSpan(
  List<IndexEntry> entries,
  IndexEntry entry,
) {
  if (entry.isImage) return null;
  if (entry.isWholeText) return (start: 0, end: null);
  final start = entry.textStart;
  if (start == null) return null;
  final at = entries.indexWhere((e) => e.key == entry.key);
  for (var i = at + 1; at >= 0 && i < entries.length; i++) {
    final next = entries[i];
    if (!_isChapter(next) || next.level > entry.level) continue;
    final end = next.textStart;
    if (end != null && end > start) return (start: start, end: end);
  }
  return (start: start, end: null);
}

/// Cuántos capítulos de [entries] con el mismo título que [entry] —comparado
/// como se comparan dos títulos (`headingKey`)— van antes que él: el segundo
/// «Referencias» de un documento es el segundo de su página web.
int indexHeadingOccurrence(List<IndexEntry> entries, IndexEntry entry) {
  final key = headingKey(entry.title);
  var count = 0;
  for (final other in entries) {
    if (other.key == entry.key) return count;
    if (_isChapter(other) && headingKey(other.title) == key) count++;
  }
  return 0;
}

/// [text] entre [start] y [end] —el tramo de un capítulo—, en una sola línea
/// y con [kIndexChapterPassageChars] como mucho, cortado en una palabra entera
/// y con «…» si sigue. Vacío si el tramo ya no cae en el texto.
String indexChapterPassage(String text, int start, int? end) {
  if (start < 0 || start >= text.length) return '';
  final stop = (end ?? text.length).clamp(start, text.length);
  final piece = text
      .substring(start, stop)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (piece.length <= kIndexChapterPassageChars) return piece;
  final cut = piece.substring(0, kIndexChapterPassageChars);
  final space = cut.lastIndexOf(' ');
  final kept = space > kIndexChapterPassageChars * 0.8
      ? cut.substring(0, space)
      : cut;
  return '${kept.trimRight()}…';
}

bool _isChapter(IndexEntry entry) =>
    entry.origin != IndexEntryOrigin.image &&
    entry.origin != IndexEntryOrigin.wholeText;
