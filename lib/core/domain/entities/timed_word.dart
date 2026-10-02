import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Una palabra tal cual la escribió el motor —con su puntuación pegada—, y
/// cuándo empieza a decirse, en milisegundos desde el principio del audio.
/// `null`: no se sabe (F23).
@immutable
class TimedWord {
  const TimedWord(this.text, this.startMs);

  final String text;
  final int? startMs;

  @override
  bool operator ==(Object other) =>
      other is TimedWord && other.text == text && other.startMs == startMs;

  @override
  int get hashCode => Object.hash(text, startMs);

  @override
  String toString() => '$text@$startMs';
}

/// Para guardar los tiempos de una transcripción en la base (F23): dos
/// listas paralelas —las palabras y su momento en milisegundos—, que pesan
/// menos que una lista de pares. `null` si no hay ninguno medido.
String? encodeWordTimings(List<TimedWord> words) {
  final timed = [
    for (final w in words)
      if (w.startMs != null) w,
  ];
  if (timed.isEmpty) return null;
  return jsonEncode({
    'w': [for (final w in timed) w.text],
    'ms': [for (final w in timed) w.startMs],
  });
}

/// Lo guardado por [encodeWordTimings]. Algo que no se puede leer —una base
/// tocada a mano— es "sin tiempos", no un error: el texto sigue intacto.
List<TimedWord> decodeWordTimings(String? stored) {
  if (stored == null || stored.isEmpty) return const [];
  try {
    final json = jsonDecode(stored) as Map<String, Object?>;
    final words = (json['w']! as List).cast<String>();
    final starts = (json['ms']! as List).cast<int>();
    if (words.length != starts.length) return const [];
    return [
      for (var i = 0; i < words.length; i++) TimedWord(words[i], starts[i]),
    ];
  } on Object {
    return const [];
  }
}
