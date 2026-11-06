import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/util/markdown_inline.dart';

/// Un tramo de un texto largo, con dónde empieza en el texto entero.
@immutable
class TextPart {
  const TextPart({required this.start, required this.text});

  /// Dónde empieza [text] dentro del texto entero: lo que lleva una cita
  /// encontrada en el tramo a su lugar en la fuente.
  final int start;
  final String text;

  int get end => start + text.length;

  @override
  bool operator ==(Object other) =>
      other is TextPart && other.start == start && other.text == text;

  @override
  int get hashCode => Object.hash(start, text);
}

/// Corta [text] en tramos de hasta [maxChars] caracteres (F27), para que el
/// modelo de lenguaje nunca reciba el texto entero de una vez: tiene una
/// ventana de 2048 tokens para todo —instrucciones, texto y respuesta—, y un
/// libro o la transcripción de un video de horas no entran.
///
/// Corta donde menos rompe: al final de un párrafo; si no hay ninguno en la
/// segunda mitad del tramo, al final de una oración; si tampoco, en un
/// espacio; y solo si no hay nada de eso, justo en [maxChars]. Buscar en la
/// segunda mitad, y no en todo el tramo, evita tramos diminutos cuando el
/// único párrafo está al principio.
///
/// Los tramos, uno detrás del otro, son el texto entero, sin perder ni
/// repetir nada: es lo que permite que una cita encontrada en un tramo
/// señale el lugar exacto de la fuente (`TextPart.start`).
///
/// **Con [markdown] (F46, paso 5b), ningún corte parte una construcción en
/// línea** —un enlace, una imagen, un énfasis, un código—: entre los cortes
/// de cada clase se elige el último que cae afuera de todas, y si no hay
/// ninguno, justo antes de la construcción que tapa el tope o, si esa
/// empieza donde empieza el tramo, justo después (ver `markdownSafeCut`).
/// Es para lo que después se muestra o se trabaja tramo por tramo —las
/// páginas de «Texto» de un documento procesado—, y tiene un precio: un
/// tramo puede pasarse de [maxChars] lo que mida una construcción más larga
/// que él. Por eso no es lo de siempre: a un modelo de lenguaje, con su
/// ventana fija, no se le puede dar un tramo más largo de lo pedido.
List<TextPart> splitIntoParts(
  String text, {
  required int maxChars,
  bool markdown = false,
}) {
  assert(maxChars > 1, 'Un tramo tiene que poder tener más de un carácter.');
  final parts = <TextPart>[];
  var start = 0;
  while (start < text.length) {
    if (text.length - start <= maxChars) {
      parts.add(TextPart(start: start, text: text.substring(start)));
      break;
    }
    final end = markdown
        ? _markdownCutPoint(text, start, start + maxChars)
        : _cutPoint(text, start, start + maxChars);
    parts.add(TextPart(start: start, text: text.substring(start, end)));
    start = end;
  }
  return parts;
}

final _sentenceEnd = RegExp(r'[.!?…]["»”)]?\s');

/// Dónde cortar el tramo que empieza en [start] y no puede pasar de [limit]:
/// justo después del separador elegido.
int _cutPoint(String text, int start, int limit) {
  final window = text.substring(start, limit);
  final half = window.length ~/ 2;

  final paragraph = window.lastIndexOf('\n\n');
  if (paragraph >= half) return start + paragraph + 2;

  var sentence = -1;
  for (final match in _sentenceEnd.allMatches(window)) {
    if (match.end >= half) sentence = match.end;
  }
  if (sentence > 0) return start + sentence;

  final space = window.lastIndexOf(RegExp(r'\s'));
  if (space >= half) return start + space + 1;

  return limit;
}

/// Lo mismo que [_cutPoint], sin partir ninguna construcción en línea de
/// Markdown: ver [splitIntoParts].
///
/// Un fin de párrafo nunca parte nada —ninguna construcción cruza un
/// renglón—. Una oración o un espacio, sí: «[Dr. Who](…)», «[bacterias
/// purpúreas](…)». Las construcciones del tramo se buscan una sola vez, desde
/// [start] —un corte anterior, donde nada quedó abierto—.
int _markdownCutPoint(String text, int start, int limit) {
  final window = text.substring(start, limit);
  final half = window.length ~/ 2;

  final paragraph = window.lastIndexOf('\n\n');
  if (paragraph >= half) return start + paragraph + 2;

  // Las construcciones que empiezan antes del tope, en orden y sin
  // solaparse; la última puede terminar después.
  final spans = <MarkdownSpan>[];
  for (final match in markdownInlinePattern.allMatches(text, start)) {
    if (match.start >= limit) break;
    spans.add((start: match.start, end: match.end));
  }

  var sentence = -1;
  for (final match in _sentenceEnd.allMatches(window)) {
    if (match.end >= half && _spanCutBy(spans, start + match.end) == null) {
      sentence = match.end;
    }
  }
  if (sentence > 0) return start + sentence;

  // De atrás para adelante, el último espacio que no cae adentro de nada:
  // si uno cae adentro, se sigue desde antes de la construcción.
  var i = window.length - 1;
  while (i >= half) {
    if (_isSpace(window.codeUnitAt(i))) {
      final span = _spanCutBy(spans, start + i + 1);
      if (span == null) return start + i + 1;
      i = span.start - start - 1;
    } else {
      i--;
    }
  }

  return markdownSafeCut(text, limit, from: start);
}

/// La de [spans] —en orden y sin solaparse— que cortar en [at] parte, o
/// `null`.
MarkdownSpan? _spanCutBy(List<MarkdownSpan> spans, int at) {
  var low = 0;
  var high = spans.length;
  // La primera que termina después de [at].
  while (low < high) {
    final mid = (low + high) >> 1;
    if (spans[mid].end <= at) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  if (low == spans.length) return null;
  final span = spans[low];
  return span.start < at ? span : null;
}

/// Un espacio, una tabulación, un salto de renglón o un espacio que no se
/// corta: lo que separa palabras en estos textos (como `processedWordCount`).
bool _isSpace(int unit) =>
    unit == 0x20 || (unit >= 0x09 && unit <= 0x0D) || unit == 0xA0;

/// [count] posiciones repartidas parejo entre `0` y `total - 1`, sin
/// repetir: qué tramos de un texto largo se leen cuando no se pueden leer
/// todos. Con [count] mayor o igual a [total], todas.
List<int> spreadIndices(int total, int count) {
  if (total <= 0 || count <= 0) return const [];
  if (count >= total) return [for (var i = 0; i < total; i++) i];
  // El centro de cada uno de `count` tramos iguales: así no se lee siempre el
  // principio y el final, que en un libro son el índice y la bibliografía.
  return [for (var i = 0; i < count; i++) ((i + 0.5) * total / count).floor()];
}
