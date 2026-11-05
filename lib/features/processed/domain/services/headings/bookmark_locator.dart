import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/processed/domain/services/headings/heading_text.dart';
import 'package:sinapsis/features/viewer/domain/services/pdf_study_pages.dart';

/// Dónde está cada uno de [bookmarks] —los marcadores de un PDF, en su orden—
/// en [text], el texto procesado de ese PDF (F46, decisión B): el tramo de
/// su título, o `null` si no se encontró. Va en el mismo orden que
/// [bookmarks].
///
/// **Qué cuenta como encontrado.** El título del marcador escrito en el texto
/// como renglones enteros —uno, o hasta [kBookmarkTitleMaxLines] seguidos,
/// porque un título largo se corta en la página— y comparado sin mayúsculas,
/// acentos
/// ni puntuación (`headingKey`): «Capítulo 1: El origen» se encuentra como
/// «CAPÍTULO 1⏎El origen». Una mención en medio de un párrafo no cuenta, ni
/// un renglón del índice del libro con su página al lado.
///
/// **En qué página se busca.** Con [pageSlices] —dónde cae cada página del
/// PDF en el texto (`pdfPageSlicesBySeparator`)—, el marcador se busca en
/// su página y solo ahí: el índice del propio libro, que está en otra, no lo
/// confunde. Sin ellas —el texto ya no tiene una raya por página— o para un
/// marcador sin página, se busca entre los marcadores vecinos que ya se
/// ubicaron, de atrás para adelante: cada uno, en el último lugar antes del
/// que sigue. Así el índice del libro, que lista todos los títulos antes que
/// el cuerpo, no se lleva ninguno.
///
/// Lineal en el largo del texto: se arma una sola vez dónde está cada
/// renglón que es el título de algún marcador, y cada marcador se busca ahí
/// en tiempo logarítmico.
List<TextSlice?> locateBookmarks(
  String text,
  List<PdfBookmark> bookmarks, {
  List<TextSlice>? pageSlices,
}) {
  final keys = [for (final bookmark in bookmarks) headingKey(bookmark.title)];
  final places = _titlePlaces(text, keys.where((key) => key.isNotEmpty));
  final located = List<TextSlice?>.filled(bookmarks.length, null);

  // En su página, si se sabe dónde cae cada una. Lo que no está en la suya
  // no se busca en otra: sería el índice del libro, o una mención.
  final onItsPage = List<bool>.filled(bookmarks.length, false);
  if (pageSlices != null) {
    for (var i = 0; i < bookmarks.length; i++) {
      final page = bookmarks[i].page;
      if (page == null || page < 1 || page > pageSlices.length) continue;
      onItsPage[i] = true;
      final candidates = places[keys[i]];
      if (candidates == null) continue;
      final slice = pageSlices[page - 1];
      final at = _firstFrom(candidates, slice.start);
      if (at < candidates.length && candidates[at].start < slice.end) {
        located[i] = candidates[at];
      }
    }
  }

  // Los demás, entre sus vecinos ya ubicados, de atrás para adelante.
  final lowerBounds = List<int>.filled(bookmarks.length, 0);
  var lower = 0;
  for (var i = 0; i < bookmarks.length; i++) {
    lowerBounds[i] = lower;
    if (located[i] case final place?) lower = place.start;
  }
  var upper = text.length;
  for (var i = bookmarks.length - 1; i >= 0; i--) {
    if (located[i] case final place?) {
      upper = place.start;
      continue;
    }
    if (onItsPage[i]) continue;
    final candidates = places[keys[i]];
    if (candidates == null) continue;
    final at = _firstFrom(candidates, upper + 1) - 1;
    if (at >= 0 && candidates[at].start >= lowerBounds[i]) {
      located[i] = candidates[at];
      upper = candidates[at].start;
    }
  }
  return located;
}

/// Cuántos renglones seguidos puede ocupar un título en el texto.
const kBookmarkTitleMaxLines = 3;

/// Hasta cuántos caracteres mide lo que se compara con un título: uno más
/// largo es un párrafo.
const _maxTitleChars = 400;

/// Dónde está, en [text], cada título de [keys]: los tramos de renglones
/// enteros —uno o hasta [kBookmarkTitleMaxLines] seguidos— que dan esa
/// clave, en el orden del texto.
Map<String, List<TextSlice>> _titlePlaces(String text, Iterable<String> keys) {
  final wanted = keys.toSet();
  final places = <String, List<TextSlice>>{};
  if (wanted.isEmpty) return places;
  // Cada renglón con texto: su tramo sin espacios en las puntas y su clave.
  final lines = <({int start, int end, String key})>[];
  var lineStart = 0;
  while (lineStart <= text.length) {
    final newline = text.indexOf('\n', lineStart);
    final lineEnd = newline < 0 ? text.length : newline;
    var first = lineStart;
    var last = lineEnd;
    while (first < last && text[first].trim().isEmpty) {
      first++;
    }
    while (last > first && text[last - 1].trim().isEmpty) {
      last--;
    }
    final key = first < last && last - first <= _maxTitleChars
        ? headingKey(text.substring(first, last))
        : '';
    lines.add((start: first, end: last, key: key));
    if (newline < 0) break;
    lineStart = newline + 1;
  }
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].key.isEmpty) continue;
    var key = '';
    for (var j = i; j < lines.length && j < i + kBookmarkTitleMaxLines; j++) {
      final line = lines[j];
      if (line.key.isEmpty) break;
      if (line.end - lines[i].start > _maxTitleChars) break;
      key = key.isEmpty ? line.key : '$key ${line.key}';
      if (wanted.contains(key)) {
        (places[key] ??= []).add((start: lines[i].start, end: line.end));
      }
    }
  }
  return places;
}

/// El primero de [places] —en orden— que empieza en [offset] o después; su
/// largo si no hay ninguno.
int _firstFrom(List<TextSlice> places, int offset) {
  var low = 0;
  var high = places.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (places[middle].start < offset) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}
