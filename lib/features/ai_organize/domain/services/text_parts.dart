import 'package:flutter/foundation.dart';

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
List<TextPart> splitIntoParts(String text, {required int maxChars}) {
  assert(maxChars > 1, 'Un tramo tiene que poder tener más de un carácter.');
  final parts = <TextPart>[];
  var start = 0;
  while (start < text.length) {
    if (text.length - start <= maxChars) {
      parts.add(TextPart(start: start, text: text.substring(start)));
      break;
    }
    final end = _cutPoint(text, start, start + maxChars);
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
