import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';

/// Lleva [segments] —pedazos con posiciones del texto entero— a las páginas
/// `[from, until)` del lector (F39): cada uno cae en la página que lo
/// contiene, con la posición contada desde el comienzo de esa página y el
/// `sourceKey` que le da [keyOf]. Es lo que hace que lo que suena del
/// resumen, la síntesis o las palabras clave se resalte en su lugar de la
/// página que se ve.
///
/// [pages] son los rangos de `readerPageRanges`. Un pedazo que cae entre dos
/// páginas, o más allá de la última, no está en ninguna y se deja afuera; uno
/// que cruza el final de su página se corta ahí. Respeta el orden de
/// [segments].
List<ReadableSegment> readerPageSegments(
  List<ReadableSegment> segments,
  List<({int start, int end})> pages, {
  required int from,
  required int until,
  required String Function(int page) keyOf,
}) {
  final result = <ReadableSegment>[];
  for (final segment in segments) {
    final page = _pageAt(pages, segment.start);
    if (page < from || page >= until) continue;
    final range = pages[page];
    if (segment.start >= range.end) continue;
    result.add(
      ReadableSegment(
        sourceKey: keyOf(page),
        start: segment.start - range.start,
        end: (segment.end < range.end ? segment.end : range.end) - range.start,
        spoken: segment.spoken,
      ),
    );
  }
  return result;
}

/// La última página que empieza en [position] o antes; -1 si la posición es
/// anterior a la primera.
int _pageAt(List<({int start, int end})> pages, int position) {
  var low = 0;
  var high = pages.length - 1;
  var found = -1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    if (pages[middle].start <= position) {
      found = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return found;
}
