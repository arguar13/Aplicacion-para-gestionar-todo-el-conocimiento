/// Cómo se guardan las respuestas alternativas de una tarjeta «Escribí la
/// respuesta» (F31, decisión 73).
///
/// La tabla de tarjetas no tiene una columna para ellas (el esquema v39 está
/// cerrado), así que viajan en `back`, una por renglón: **la primera línea es
/// LA respuesta** —la que se muestra y la que se exporta como correcta— y las
/// siguientes son otras que también valen (`Roma` y, debajo, `Roma antigua`).
/// Una tarjeta sin alternativas guarda en `back` una sola línea, exactamente
/// como antes: nada de lo ya guardado cambia.
///
/// Quien compara lo escrito (`compareTypedAnswer`) recibe
/// [TypedAnswerSpec.answer] como lo correcto y [TypedAnswerSpec.alternatives]
/// como `alternatives`.
library;

import 'package:meta/meta.dart';

/// La respuesta de una tarjeta de «escribí la respuesta» con sus alternativas.
@immutable
class TypedAnswerSpec {
  const TypedAnswerSpec(this.answer, [this.alternatives = const []]);

  /// Lee el `back` de una tarjeta: la primera línea no vacía es la
  /// respuesta, el resto son alternativas. Quita los blancos de cada línea,
  /// las líneas vacías y las alternativas que repiten la respuesta o a otra
  /// alternativa (sin distinguir mayúsculas).
  factory TypedAnswerSpec.parse(String back) {
    final lines = [
      for (final line in back.split(RegExp(r'\r?\n')))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (lines.isEmpty) return const TypedAnswerSpec('');
    return TypedAnswerSpec.of(lines.first, lines.skip(1));
  }

  /// Arma la respuesta con sus alternativas, limpias: sin blancos, sin vacías
  /// y sin repetir la respuesta ni a otra alternativa (sin distinguir
  /// mayúsculas).
  factory TypedAnswerSpec.of(String answer, Iterable<String> alternatives) {
    final main = answer.trim();
    final seen = {main.toLowerCase()};
    return TypedAnswerSpec(main, [
      for (final alt in alternatives)
        if (alt.trim().isNotEmpty && seen.add(alt.trim().toLowerCase()))
          alt.trim(),
    ]);
  }

  /// La respuesta principal.
  final String answer;

  /// Otras respuestas que también valen (puede no haber).
  final List<String> alternatives;

  /// Lo que se guarda en `back`: la respuesta y debajo cada alternativa.
  String get encoded => [answer, ...alternatives].join('\n');
}
