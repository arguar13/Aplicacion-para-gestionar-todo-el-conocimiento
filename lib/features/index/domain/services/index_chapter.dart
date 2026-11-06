import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/core/util/markdown_plain_text.dart';
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

/// El pasaje para el chat del tramo [start]–[end] de [text] —el de un
/// capítulo—: **como se lee** (`readablePassage`), en una sola línea y con
/// [kIndexChapterPassageChars] letras legibles como mucho, cortado en una
/// palabra entera y con «…» si sigue. Vacío si el tramo ya no cae en el texto.
///
/// - Con [markdown] —una página web, un Word, un EPUB—, sin enlaces con su
///   dirección, sin fotos, sin `**` ni `#` y sin las llamadas a notas al pie;
///   cada bloque es una oración (F46, paso 5e).
/// - Con [title], el renglón del propio título del capítulo —con el que
///   empieza el tramo— queda afuera: el borrador del chat ya lo nombra, y
///   pegado al párrafo se leía «Siglo XX En 1905». Si el tramo no empieza con
///   él —el título de la IA de un PDF, que no es un renglón—, no se saca nada.
String indexChapterPassage(
  String text,
  int start,
  int? end, {
  required bool markdown,
  String? title,
}) {
  if (start < 0 || start >= text.length) return '';
  final stop = (end ?? text.length).clamp(start, text.length);
  var from = start;
  if (title != null) {
    final lineEnd = text.indexOf('\n', start);
    final firstEnd = lineEnd == -1 || lineEnd > stop ? stop : lineEnd;
    if (_isTitleLine(text.substring(start, firstEnd), title, markdown)) {
      from = firstEnd;
    }
  }
  return readablePassage(
    text,
    start: from,
    end: stop,
    markdown: markdown,
    maxChars: kIndexChapterPassageChars,
  );
}

/// Si [line] es el título [title]: comparados como se comparan dos títulos
/// (`headingKey`), con [line] como se lee. Un número delante —«3. Siglo XX»,
/// «1.2 Desarrollo»— no lo cambia: el Índice lo muestra aparte.
bool _isTitleLine(String line, String title, bool markdown) {
  final key = headingKey(title);
  final read = headingKey(markdown ? markdownPlainText(line) : line);
  return read == key || (read.endsWith(' $key') && _numbered.hasMatch(read));
}

/// Un título que empieza con su número: «3 siglo xx», «1 2 desarrollo».
final _numbered = RegExp(r'^\d+(?: \d+)* ');

bool _isChapter(IndexEntry entry) =>
    entry.origin != IndexEntryOrigin.image &&
    entry.origin != IndexEntryOrigin.wholeText;
