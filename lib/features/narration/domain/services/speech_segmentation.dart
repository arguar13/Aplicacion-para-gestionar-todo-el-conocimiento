/// Cuánto puede medir un fragmento antes de cortarse a la fuerza —ver
/// [_hardSplit]—. Un motor de voz sintetiza de a poco de todos modos, pero
/// `NarrationPlayer` necesita fragmentos cortos para que "retroceder" y
/// "adelantar" (ver `TextToSpeechService`) se sientan como controles de
/// verdad y no como saltos de varios minutos.
const _kMaxSegmentLength = 400;

/// Separa oraciones seguidas de un espacio o un salto de línea. El
/// `lookbehind` deja la puntuación pegada a la oración que cierra, en vez
/// de que cada fragmento empiece con un `.` o un `?` sueltos.
final _sentenceBoundary = RegExp(r'(?<=[.!?…])\s+');

/// Corta [text] en fragmentos cortos para leerlos en voz alta de a uno,
/// pensados para `TextToSpeechService.speak`.
///
/// Por oración y no por párrafo —a diferencia de `splitIntoReaderPages`,
/// que arma páginas para leer con los ojos—: una oración es la unidad más
/// chica que todavía tiene sentido leída sola, y es lo bastante corta como
/// para que "retroceder un fragmento" se sienta inmediato. Un párrafo
/// entero tardaría fácil un minuto entero en leerse, y "retroceder" ahí
/// volvería a un lugar demasiado lejano para servir de control.
List<String> splitIntoSpeechSegments(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];

  final segments = <String>[];
  for (final rawSentence in trimmed.split(_sentenceBoundary)) {
    final sentence = rawSentence.trim();
    if (sentence.isEmpty) continue;

    if (sentence.length <= _kMaxSegmentLength) {
      segments.add(sentence);
    } else {
      segments.addAll(_hardSplit(sentence));
    }
  }
  return segments;
}

/// Mismo criterio que `_hardSplit` en `reader_pagination.dart`: corta en el
/// espacio más cercano hacia atrás para no partir una palabra al medio,
/// salvo que el tramo no tenga ningún espacio.
List<String> _hardSplit(String sentence) {
  final parts = <String>[];
  var start = 0;

  while (start < sentence.length) {
    var end = (start + _kMaxSegmentLength).clamp(0, sentence.length);
    if (end < sentence.length) {
      final lastSpace = sentence.lastIndexOf(' ', end);
      if (lastSpace > start) end = lastSpace;
    }
    parts.add(sentence.substring(start, end).trim());
    start = end;
    while (start < sentence.length && sentence[start] == ' ') {
      start++;
    }
  }

  return parts;
}
