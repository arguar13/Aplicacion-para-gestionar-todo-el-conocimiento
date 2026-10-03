import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_organize/domain/services/content_change.dart';

/// «Cambió mucho» de verdad (F27): la huella del contenido, no el largo.
void main() {
  const vocabulary = [
    'roma', 'senado', 'imperio', 'república', 'cónsul', 'guerra', 'pueblo', //
    'ley', 'ciudad', 'historia', 'poder', 'ejército', 'tribuno', 'plebe',
    'patricio', 'césar', 'augusto', 'provincia', 'comercio', 'mar', 'tierra',
    'agua', 'pan', 'vino', 'aceite', 'templo', 'dios', 'rito', 'familia',
    'padre', 'hijo', 'esclavo', 'libre', 'derecho', 'juicio', 'foro',
  ];

  /// [words] palabras al azar, siempre las mismas para cada [seed].
  String textOf(int words, int seed) {
    final random = Random(seed);
    return [
      for (var i = 0; i < words; i++)
        vocabulary[random.nextInt(vocabulary.length)],
    ].join(' ');
  }

  bool changed(String before, String now) =>
      contentChangedMuch(contentSimhashOf(before), contentSimhashOf(now));

  test('otro contenido del mismo largo sí cambió mucho', () {
    for (var seed = 0; seed < 20; seed++) {
      for (final words in [40, 300, 2000]) {
        final before = textOf(words, seed);
        final now = textOf(words, seed + 1000);
        expect(changed(before, now), isTrue, reason: '$words, semilla $seed');
      }
    }
  });

  test('un retoque no: una coma, una mayúscula, una palabra', () {
    for (var seed = 0; seed < 20; seed++) {
      for (final words in [40, 300, 2000]) {
        final before = textOf(words, seed);
        final parts = before.split(' ');
        parts[Random(seed).nextInt(words)] = 'cartago';
        final retouched = '${parts.join(' ')}.';
        expect(
          changed(before, retouched),
          isFalse,
          reason: '$words, semilla $seed',
        );
        expect(changed(before, before.toUpperCase()), isFalse);
      }
    }
  });

  test('duplicarla con lo nuevo sí; un párrafo suelto no', () {
    final before = textOf(600, 7);
    expect(changed(before, '$before ${textOf(1200, 8)}'), isTrue);
    expect(changed(before, '$before ${textOf(30, 9)}'), isFalse);
  });
}
