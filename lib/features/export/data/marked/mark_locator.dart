import 'dart:typed_data';

import 'package:sinapsis/core/util/word_folding.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';

/// Dónde cae un tramo marcado en el texto de un archivo: de `start` a `end`
/// (sin incluir), en posiciones de ese texto.
typedef MarkSpan = ({int start, int end});

/// Ubica cada tramo de [marks] —que tiene sus posiciones en el texto
/// extraído [extracted]— en [haystack], el texto tal como lo tiene el archivo
/// que se va a marcar (F38): lo que los `w:t` de un Word concatenados, o el
/// Markdown original.
///
/// Devuelve un lugar por tramo, o `null` si no se encontró: un tramo que no
/// se encuentra se saltea y no rompe nada.
///
/// **Por qué comparando solo letras y números.** El texto extraído de un
/// Word no es el texto del Word: es Markdown —`#`, `**`, `|`, `- `— con la
/// numeración de las listas, los encabezados, las notas al pie y los
/// comentarios agregados en otros lugares (F22). Reconstruir el recorrido
/// exacto del lector para mapear una posición a un párrafo y un renglón se
/// rompería con cualquier detalle que cambie en él. En cambio, lo que sí
/// coincide siempre es el texto mismo, letra por letra; lo que difiere es
/// la puntuación, los espacios y los saltos, que acá no cuentan (es lo mismo
/// que hace `archived_page_study.dart` con las páginas web, con
/// `foldWordChar`: sin mayúsculas, sin acentos).
///
/// **Cuál de las repeticiones.** Un texto repite frases. Se prueba en este
/// orden, de lo más a lo menos específico, y se toma la primera forma que
/// aparezca en [haystack]:
///
/// 1. el tramo con las 32 letras que lo preceden en el texto extraído;
/// 2. el tramo con las 12 que lo preceden;
/// 3. el tramo solo.
///
/// Si aun así aparece más de una vez, se toma **la misma repetición que en
/// el texto extraído**: si el tramo es la tercera vez que aparece ahí, es la
/// tercera allá (o la última, si allá hay menos). El contexto sirve para
/// que los encabezados o las notas que el texto extraído suma no corran la
/// cuenta.
///
/// Con [markdownUrls], el texto extraído y los tramos son Markdown con sus
/// enlaces e imágenes —`[texto](dirección)`, `![alt](dirección)`—, y la
/// dirección no está en [haystack] (la página o el capítulo la tiene en un
/// atributo): las direcciones, y el texto alternativo de las imágenes, no
/// cuentan como letras (F38: la página web y el EPUB). Sin esto, un tramo que
/// cruza un enlace nunca se encontraría.
///
/// Cuando [haystack] es **igual** a [extracted] —un Markdown, que se
/// extrae tal cual—, un tramo cuyo texto está donde dice se toma sin buscar.
///
/// El lugar que se devuelve empieza en la primera letra o número del tramo
/// y termina en la última: sin los espacios ni la puntuación de los bordes.
List<MarkSpan?> locateMarks({
  required String haystack,
  required String extracted,
  required List<DocumentMark> marks,
  bool markdownUrls = false,
}) {
  if (marks.isEmpty) return const [];
  final sameText = haystack == extracted;
  final hay = _Folded.of(haystack, withBefore: sameText);
  final ext = sameText
      ? hay
      : _Folded.of(extracted, withBefore: true, markdownUrls: markdownUrls);

  return [
    for (final mark in marks)
      _locate(
        mark,
        hay: hay,
        ext: ext,
        sameText: sameText,
        markdownUrls: markdownUrls,
      ),
  ];
}

/// Las pistas de contexto, en letras de antes del tramo, de más a menos.
const _contexts = [32, 12, 0];

MarkSpan? _locate(
  DocumentMark mark, {
  required _Folded hay,
  required _Folded ext,
  required bool sameText,
  required bool markdownUrls,
}) {
  final needle = _Folded.of(mark.excerpt, markdownUrls: markdownUrls).text;
  if (needle.isEmpty) return null;

  // En qué letra del texto extraído empieza el tramo.
  final extractedLength = ext.before.length - 1;
  final from = mark.start < 0
      ? 0
      : (mark.start > extractedLength ? extractedLength : mark.start);
  final foldedStart = ext.before[from];

  if (sameText && ext.text.startsWith(needle, foldedStart)) {
    return _spanOf(hay, foldedStart, needle.length);
  }

  for (final context in _contexts) {
    final take = context < foldedStart ? context : foldedStart;
    final pattern =
        ext.text.substring(foldedStart - take, foldedStart) + needle;
    final limit = foldedStart - take;

    // Cuántas veces apareció ya en el texto extraído, antes de este lugar.
    var ordinal = 0;
    for (
      var at = ext.text.indexOf(pattern);
      at >= 0 && at < limit;
      at = ext.text.indexOf(pattern, at + 1)
    ) {
      ordinal++;
    }

    int? found;
    var seen = 0;
    for (
      var at = hay.text.indexOf(pattern);
      at >= 0;
      at = hay.text.indexOf(pattern, at + 1)
    ) {
      found = at;
      if (seen++ == ordinal) break;
    }
    if (found != null) return _spanOf(hay, found + take, needle.length);
  }
  return null;
}

MarkSpan _spanOf(_Folded hay, int foldedStart, int length) => (
  start: hay.origin[foldedStart],
  end: hay.origin[foldedStart + length - 1] + 1,
);

/// Un texto plegado a sus letras y números, sin mayúsculas ni acentos, y por
/// dónde volver al original.
class _Folded {
  _Folded._(this.text, this.origin, this.before);

  factory _Folded.of(
    String source, {
    bool withBefore = false,
    bool markdownUrls = false,
  }) {
    final units = <int>[];
    final origin = <int>[];
    final before = withBefore ? Int32List(source.length + 1) : null;
    final skip = markdownUrls ? _urlRanges(source).iterator : null;
    var hasSkip = skip?.moveNext() ?? false;
    for (var i = 0; i < source.length; i++) {
      before?[i] = units.length;
      while (hasSkip && skip!.current.end <= i) {
        hasSkip = skip.moveNext();
      }
      if (hasSkip && i >= skip!.current.start) continue;
      final folded = foldWordChar(source.codeUnitAt(i));
      if (folded == null) continue;
      // Una mayúscula rara puede dar dos letras al pasar a minúscula; con la
      // primera alcanza para comparar, y mantiene una letra por carácter.
      units.add(folded.codeUnitAt(0));
      origin.add(i);
    }
    before?[source.length] = units.length;
    return _Folded._(
      String.fromCharCodes(units),
      Int32List.fromList(origin),
      before ?? Int32List(0),
    );
  }

  /// Las letras y números, plegados.
  final String text;

  /// Para cada letra de [text], dónde estaba en el original.
  final Int32List origin;

  /// Para cada posición del original, cuántas letras de [text] hay antes.
  /// Vacío si no se pidió.
  final Int32List before;
}

/// Un enlace de Markdown: la dirección no está en la página, solo el texto.
/// Una imagen entera tampoco —su texto alternativo es un atributo—.
final _markdownUrls = RegExp(r'!\[[^\]]*\]\([^)]*\)|\]\([^)]*\)');

/// Lo que de un Markdown no es texto que se lea: las imágenes enteras y las
/// direcciones de los enlaces, en orden.
Iterable<MarkSpan> _urlRanges(String source) =>
    _markdownUrls.allMatches(source).map((m) => (start: m.start, end: m.end));
