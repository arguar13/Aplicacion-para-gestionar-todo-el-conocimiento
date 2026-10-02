import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/timed_word.dart';

export 'package:sinapsis/core/domain/entities/timed_word.dart';

/// Un texto palabra por palabra, cada una con su momento (F23). El texto es
/// las palabras separadas por un espacio: lo que separa palabras —espacios,
/// saltos de línea— no se conserva, y en lo que escribe el motor no hay
/// otra cosa que espacios simples.
@immutable
class TimedText {
  const TimedText(this.words);

  /// Un texto sin tiempos: cada palabra con `startMs` en `null`.
  factory TimedText.plain(String text) =>
      TimedText([for (final word in splitWords(text)) TimedWord(word, null)]);

  /// Lo guardado por [encode]; un texto suelto —guardado antes de F23, o
  /// sin tiempos— vuelve sin tiempos.
  factory TimedText.decode(String stored) {
    if (!stored.startsWith(_timedPrefix)) return TimedText.plain(stored);
    final json =
        jsonDecode(stored.substring(_timedPrefix.length))
            as Map<String, Object?>;
    final texts = (json['w']! as List).cast<String>();
    final starts = (json['ms']! as List).cast<int>();
    return TimedText([
      for (var i = 0; i < texts.length; i++) TimedWord(texts[i], starts[i]),
    ]);
  }

  static const empty = TimedText([]);

  final List<TimedWord> words;

  String get text => words.map((w) => w.text).join(' ');

  bool get isEmpty => words.isEmpty;

  /// Si todas las palabras tienen su momento.
  bool get isTimed => words.every((w) => w.startMs != null);

  /// Las mismas palabras, [ms] más tarde: lo que se transcribió de un
  /// pedazo, puesto en su lugar dentro del audio entero.
  TimedText shifted(int ms) => TimedText([
    for (final w in words)
      TimedWord(w.text, w.startMs == null ? null : w.startMs! + ms),
  ]);

  TimedText sublist(int start, [int? end]) =>
      TimedText(words.sublist(start, end));

  /// Para guardar un tramo ya transcrito y retomarlo después (F21). Un
  /// texto sin tiempos se guarda tal cual, como antes de F23: así lo
  /// guardado por una versión anterior se sigue leyendo —ver
  /// [TimedText.decode]—.
  String encode() {
    if (isEmpty || !isTimed) return text;
    return '$_timedPrefix${jsonEncode({
      'w': [for (final w in words) w.text],
      'ms': [for (final w in words) w.startMs],
    })}';
  }

  /// Un carácter de control que ningún texto transcrito trae: distingue lo
  /// guardado con tiempos de un texto suelto.
  static const _timedPrefix = '\u0001tt:';

  @override
  bool operator ==(Object other) =>
      other is TimedText && listEquals(other.words, words);

  @override
  int get hashCode => Object.hashAll(words);

  @override
  String toString() => 'TimedText($words)';
}

final _whitespace = RegExp(r'\s+');

/// Las palabras de [text], separadas por cualquier espacio.
List<String> splitWords(String text) =>
    text.split(_whitespace).where((w) => w.isNotEmpty).toList();

/// Lo que devuelve una transcripción entera: el texto como se guarda —con
/// su marca de tiempo por renglón, "[3:15] …"— y cada palabra de lo dicho
/// con su momento, en orden, **sin** las marcas de tiempo (F23).
@immutable
class Transcript {
  const Transcript(this.text, [this.words = const []]);

  final String text;
  final List<TimedWord> words;
}
