import 'dart:typed_data';

import 'package:sinapsis/core/util/word_folding.dart';

/// Un tramo `[start, end)` de un texto.
typedef PageRange = ({int start, int end});

/// Cómo se corresponden el texto corrido de una página web archivada y el
/// texto extraído de ella (F38): de una selección sobre la página, qué tramo
/// del texto extraído es, y de un resaltado guardado en el texto extraído,
/// qué tramos de la página pintar.
///
/// **El texto de la página.** Es el de todos sus textos en el orden del
/// documento, sin lo que no se lee —`<script>`, `<style>`, desplegables…; ver
/// `showableArchivedPage`—, pegados sin nada en el medio. Es lo único que la
/// página, que corre en el navegador, sabe contar sin ayuda: el programa de
/// la app (ver `archivedPageMarksScript`) cuenta así, letra a letra, y manda
/// posiciones de ese texto. Partir un texto en pedazos —para envolver una
/// oración en un `<mark>`, para pintar un resaltado— no lo cambia.
///
/// **Cómo se corresponden.** El texto extraído es el artículo en Markdown y
/// la página tiene además su menú, sus etiquetas y sus espacios: se comparan
/// solo las letras y los números, sin mayúsculas ni acentos (ver
/// `foldWordChar`), y por pedazos —un renglón del extraído a la vez—. Lo que
/// el extraído tiene y la página no (las direcciones de los enlaces, una nota
/// al pie) queda sin corresponder, y la selección que lo cruza no se acepta.
///
/// Se arma una vez por página, fuera del hilo de la pantalla, junto con la
/// copia que se muestra (ver `showArchivedPage`).
class ArchivedPageAlignment {
  ArchivedPageAlignment({
    required this.content,
    required this.pageText,
    required this.letterPosition,
    required this.pageToContent,
    required this.contentToPage,
    required this.contentPosition,
  });

  /// El texto extraído.
  final String content;

  /// El texto corrido de la página.
  final String pageText;

  /// De cada letra de la página —plegada, contada de corrido—, su posición
  /// en [pageText].
  final Int32List letterPosition;

  /// De cada letra de la página, la letra del extraído que es, o -1.
  final Int32List pageToContent;

  /// De cada letra del extraído, la letra de la página que es, o -1.
  final Int32List contentToPage;

  /// De cada letra del extraído —plegada, contada de corrido—, su posición
  /// en [content].
  final Int32List contentPosition;

  /// Si [text] —lo que el navegador dice que está seleccionado— son las
  /// letras de `[start, end)` del texto de la página: la prueba de que la
  /// página que ve el navegador y la que se contó acá son la misma. El
  /// navegador deja afuera lo que no se ve (un texto escondido en el medio)
  /// y no inventa nada: alcanza con que lo que dijo esté, en ese orden, y sea
  /// casi todo lo contado.
  bool agrees(int start, int end, String text) {
    final from = start.clamp(0, pageText.length);
    final to = end.clamp(from, pageText.length);
    final counted = foldedLetters(pageText.substring(from, to));
    final said = foldedLetters(text);
    if (said.isEmpty || counted.isEmpty) return false;
    return said.length * 10 >= counted.length * 7 &&
        _isSubsequence(said, counted);
  }

  /// El tramo del texto extraído que es lo seleccionado en la página
  /// —`[start, end)` de su texto corrido—, o `null` si no se puede saber:
  /// la selección no está en el artículo —el menú, una etiqueta—, o lo cruza
  /// y se salta partes.
  ///
  /// Empieza en la primera letra elegida y termina en la última; los signos
  /// pegados a ellas que la persona eligió —las comillas, el punto— entran
  /// si el extraído los tiene en ese lugar.
  PageRange? contentRangeOf(int start, int end) {
    final from = start.clamp(0, pageText.length);
    final to = end.clamp(from, pageText.length);
    var first = _lowerBound(letterPosition, from);
    var last = _lowerBound(letterPosition, to) - 1;
    if (first > last) return null;

    final total = last - first + 1;
    var aligned = 0;
    for (var j = first; j <= last; j++) {
      if (pageToContent[j] >= 0) aligned++;
    }
    if (aligned * 10 < total * 6) return null;
    while (pageToContent[first] < 0) {
      first++;
    }
    while (pageToContent[last] < 0) {
      last--;
    }
    final firstLetter = pageToContent[first];
    final lastLetter = pageToContent[last];
    // Al revés, o mucho más larga que lo elegido: el extraído y la página no
    // cuentan esto en el mismo orden.
    if (lastLetter < firstLetter ||
        lastLetter - firstLetter + 1 > total * 2 + 40) {
      return null;
    }

    var rangeStart = contentPosition[firstLetter];
    var rangeEnd = contentPosition[lastLetter] + 1;
    final selected = pageText.substring(from, to);
    final head = _edgeMarks(selected, atStart: true);
    for (var i = head.length - 1; i >= 0; i--) {
      if (rangeStart > 0 && content.codeUnitAt(rangeStart - 1) == head[i]) {
        rangeStart--;
      } else {
        break;
      }
    }
    final tail = _edgeMarks(selected, atStart: false);
    for (var i = 0; i < tail.length; i++) {
      if (rangeEnd < content.length &&
          content.codeUnitAt(rangeEnd) == tail[i]) {
        rangeEnd++;
      } else {
        break;
      }
    }
    return (start: rangeStart, end: rangeEnd);
  }

  /// Los tramos del texto corrido de la página que son `[start, end)` del
  /// texto extraído: uno por cada pedazo seguido, que se corta donde el
  /// extraído tiene algo que la página no. Ninguno si nada de eso está en la
  /// página.
  List<PageRange> pageRangesOf(int start, int end) {
    final from = _lowerBound(contentPosition, start);
    final to = _lowerBound(contentPosition, end);
    final ranges = <PageRange>[];
    int? runFirst;
    var runLast = -1;
    void close() {
      final first = runFirst;
      if (first != null) {
        ranges.add((
          start: letterPosition[first],
          end: letterPosition[runLast] + 1,
        ));
      }
      runFirst = null;
    }

    for (var k = from; k < to; k++) {
      final j = contentToPage[k];
      if (j < 0) {
        close();
      } else if (runFirst != null && j == runLast + 1) {
        runLast = j;
      } else {
        close();
        runFirst = j;
        runLast = j;
      }
    }
    close();
    if (ranges.isEmpty) return ranges;

    // Los signos pegados al principio y al final del resaltado, como entran
    // al elegirlos.
    final slice = content.substring(
      start.clamp(0, content.length),
      end.clamp(0, content.length),
    );
    final head = _edgeMarks(slice, atStart: true);
    var first = ranges.first.start;
    for (var i = head.length - 1; i >= 0; i--) {
      if (first > 0 && pageText.codeUnitAt(first - 1) == head[i]) {
        first--;
      } else {
        break;
      }
    }
    final tail = _edgeMarks(slice, atStart: false);
    var last = ranges.last.end;
    for (var i = 0; i < tail.length; i++) {
      if (last < pageText.length && pageText.codeUnitAt(last) == tail[i]) {
        last++;
      } else {
        break;
      }
    }
    ranges[0] = (start: first, end: ranges.first.end);
    ranges[ranges.length - 1] = (start: ranges.last.start, end: last);
    return ranges;
  }
}

/// Las letras y números de [text], plegados (ver `foldWordChar`): con lo que
/// se compara un texto con otro.
String foldedLetters(String text) {
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final folded = foldWordChar(text.codeUnitAt(i));
    if (folded != null) buffer.write(folded);
  }
  return buffer.toString();
}

/// Si las letras de [part] están en [whole], en ese orden, con o sin otras
/// en el medio.
bool _isSubsequence(String part, String whole) {
  var at = 0;
  for (var i = 0; i < whole.length && at < part.length; i++) {
    if (whole.codeUnitAt(i) == part.codeUnitAt(at)) at++;
  }
  return at == part.length;
}

/// Los signos que hay antes de la primera letra de [text] ([atStart]) o
/// después de la última, sin espacios y sin las marcas del Markdown que la
/// página no tiene (`*`, `_`, `~`, `` ` ``): las comillas, el punto.
List<int> _edgeMarks(String text, {required bool atStart}) {
  final marks = <int>[];
  final units = text.codeUnits;
  final indices = atStart
      ? Iterable<int>.generate(units.length)
      : Iterable<int>.generate(units.length, (i) => units.length - 1 - i);
  for (final i in indices) {
    final unit = units[i];
    if (foldWordChar(unit) != null) break;
    if (_isSpace(unit) || _markdownMarks.contains(unit)) continue;
    marks.add(unit);
  }
  return atStart ? marks : marks.reversed.toList();
}

final _markdownMarks = '*_~`'.codeUnits.toSet();

bool _isSpace(int unit) =>
    unit == 0x20 || (unit >= 0x09 && unit <= 0x0D) || unit == 0xA0;

/// El primer lugar de [sorted] con un valor de [value] o más.
int _lowerBound(Int32List sorted, int value) {
  var low = 0;
  var high = sorted.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (sorted[mid] < value) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}
