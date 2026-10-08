import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/services/typed_answer.dart';

TypedAnswerVerdict verdictOf(String typed, String correct) =>
    compareTypedAnswer(typed: typed, correct: correct).verdict;

/// Lo escrito, con lo que sobra entre `[-` y `-]`.
String typedView(TypedAnswerResult r) => r.typedSegments
    .map(
      (s) => s.kind == TypedAnswerSegmentKind.extra
          ? '[-${s.typedText}-]'
          : s.typedText,
    )
    .join();

/// Lo correcto, con lo que faltó entre `[+` y `+]`.
String expectedView(TypedAnswerResult r) => r.expectedSegments
    .map(
      (s) => s.kind == TypedAnswerSegmentKind.missing
          ? '[+${s.expectedText}+]'
          : s.expectedText,
    )
    .join();

void main() {
  group('normalizeForComparison', () {
    test('minúsculas, acentos, puntuación y espacios', () {
      expect(
        normalizeForComparison('  ¡La  FOTOSÍNTESIS,   es...  clave! '),
        'fotosintesis es clave',
      );
    });

    test('la ñ no es una n', () {
      expect(normalizeForComparison('Año'), 'año');
      expect(
        normalizeForComparison('año'),
        isNot(normalizeForComparison('ano')),
      );
    });

    test('un acento suelto (decomposed) vale como el compuesto', () {
      expect(normalizeForComparison('e\u0301poca'), 'epoca');
      expect(normalizeForComparison('n\u0303u'), 'ñu');
    });

    test('un artículo al principio no cuenta, pero uno solo sí', () {
      expect(normalizeForComparison('El Imperio romano'), 'imperio romano');
      expect(normalizeForComparison('Los'), 'los');
      expect(normalizeForComparison('The Beatles'), 'beatles');
    });

    test('los números conservan lo que los distingue', () {
      expect(normalizeForComparison('3,14'), normalizeForComparison('3.14'));
      expect(normalizeForComparison('1.000'), normalizeForComparison('1,000'));
      expect(normalizeForComparison('1.000.000'), '1000000');
      expect(normalizeForComparison('-5'), isNot(normalizeForComparison('5')));
      expect(
        normalizeForComparison('50%'),
        isNot(normalizeForComparison('50')),
      );
      expect(normalizeForComparison('C++'), isNot(normalizeForComparison('C')));
    });

    test('apóstrofes y guiones', () {
      expect(normalizeForComparison("don't"), 'dont');
      expect(normalizeForComparison('bien-estar'), 'bien estar');
      // Un guion doble no separa palabras: no hay letra a cada lado.
      expect(normalizeForComparison('bien--estar'), 'bienestar');
    });

    test('un decimal no es lo mismo que el número sin la coma', () {
      expect(
        normalizeForComparison('3,14'),
        isNot(normalizeForComparison('314')),
      );
      expect(
        normalizeForComparison('3.14'),
        isNot(normalizeForComparison('314')),
      );
    });

    test('vacío y solo signos', () {
      expect(normalizeForComparison(''), '');
      expect(normalizeForComparison('  ¿?!... '), '');
    });

    test('emoji y otros alfabetos no rompen', () {
      expect(normalizeForComparison('Hola 👋 мир'), 'hola мир');
    });
  });

  group('veredictos con ejemplos reales', () {
    // [escrito, correcto, veredicto esperado]
    const cases = <(String, String, TypedAnswerVerdict)>[
      // Coincide
      ('mitocondria', 'Mitocondria', TypedAnswerVerdict.match),
      ('fotosintesis', 'fotosíntesis', TypedAnswerVerdict.match),
      ('napoleon', 'Napoleón', TypedAnswerVerdict.match),
      ('Imperio romano', 'El Imperio Romano.', TypedAnswerVerdict.match),
      ('el imperio romano', 'Imperio romano', TypedAnswerVerdict.match),
      (
        'la capital es madrid',
        'La capital es Madrid',
        TypedAnswerVerdict.match,
      ),
      (
        '  Segunda   guerra mundial ',
        'segunda guerra mundial',
        TypedAnswerVerdict.match,
      ),
      ('bien estar', 'bien-estar', TypedAnswerVerdict.match),
      ('3.14', '3,14', TypedAnswerVerdict.match),
      ('1000000', '1.000.000', TypedAnswerVerdict.match),
      ('1492', '1492', TypedAnswerVerdict.match),
      ('sí', 'si', TypedAnswerVerdict.match),
      // Casi: un descuido de tipeo en una palabra larga
      ('mitocondira', 'mitocondria', TypedAnswerVerdict.close),
      ('mitocondria', 'mitocondrias', TypedAnswerVerdict.close),
      ('Washinton', 'Washington', TypedAnswerVerdict.close),
      ('Servantes', 'Cervantes', TypedAnswerVerdict.close),
      ('fotosintessis', 'fotosíntesis', TypedAnswerVerdict.close),
      ('Revolucion Fransesa', 'Revolución Francesa', TypedAnswerVerdict.close),
      ('Napolen', 'Napoleón', TypedAnswerVerdict.close),
      ('azucar', 'asúcar', TypedAnswerVerdict.close),
      ('sanfrancisco', 'San Francisco', TypedAnswerVerdict.close),
      ('Tenochtitlán', 'Tenochtitlan.', TypedAnswerVerdict.match),
      ('Tenochtitlam', 'Tenochtitlán', TypedAnswerVerdict.close),
      // No coincide: palabras cortas o distintas
      ('gato', 'pato', TypedAnswerVerdict.mismatch),
      ('perro', 'pero', TypedAnswerVerdict.mismatch),
      ('Roma', 'Rima', TypedAnswerVerdict.mismatch),
      ('ano', 'año', TypedAnswerVerdict.mismatch),
      ('cuatro', 'cuarto', TypedAnswerVerdict.close),
      // No coincide: falta o sobra algo importante
      ('guerra', 'Segunda Guerra Mundial', TypedAnswerVerdict.mismatch),
      ('Segunda guerra', 'Segunda Guerra Mundial', TypedAnswerVerdict.mismatch),
      (
        'Primera Guerra Mundial',
        'Segunda Guerra Mundial',
        TypedAnswerVerdict.mismatch,
      ),
      ('Napoleón Bonaparte', 'Napoleón', TypedAnswerVerdict.mismatch),
      ('Juan Carlos I', 'Juan Carlos II', TypedAnswerVerdict.mismatch),
      ('caída Bastilla', 'caída de la Bastilla', TypedAnswerVerdict.mismatch),
      ('mitocondria', 'ribosoma', TypedAnswerVerdict.mismatch),
      // Los números
      ('1493', '1492', TypedAnswerVerdict.mismatch),
      ('1942', '1492', TypedAnswerVerdict.mismatch),
      ('476', 'En el 476 d. C.', TypedAnswerVerdict.mismatch),
      ('-5', '5', TypedAnswerVerdict.mismatch),
      ('50', '50%', TypedAnswerVerdict.mismatch),
      ('C', 'C++', TypedAnswerVerdict.mismatch),
      (
        'la revolución de 1789',
        'La Revolución de 1798',
        TypedAnswerVerdict.mismatch,
      ),
      ('2,5', '2.5', TypedAnswerVerdict.match),
    ];

    for (final (typed, correct, expected) in cases) {
      test('"$typed" contra "$correct" es $expected', () {
        expect(verdictOf(typed, correct), expected);
      });
    }
  });

  group('umbrales', () {
    test('hasta 5 caracteres no se tolera nada; de 6 en adelante el 15 %', () {
      expect(tolerableEdits(0), 0);
      expect(tolerableEdits(5), 0);
      expect(tolerableEdits(6), 1);
      expect(tolerableEdits(13), 1);
      expect(tolerableEdits(14), 2);
      expect(tolerableEdits(20), 3);
      expect(tolerableEdits(1000), 8);
    });

    test('una palabra corta que sobra o falta no es un descuido', () {
      const correct = 'la batalla de las termopilas ocurrio en el verano';
      // Con 3 ediciones de 50 caracteres sería "casi", pero es un "de" que
      // no está.
      expect(
        verdictOf('la batalla las termopilas ocurrio en el verano', correct),
        TypedAnswerVerdict.mismatch,
      );
      expect(
        verdictOf(
          'la batalla de las de termopilas ocurrio en el verano',
          correct,
        ),
        TypedAnswerVerdict.mismatch,
      );
      // En cambio, un descuido dentro de una palabra larga sí.
      expect(
        verdictOf('la batalla de las termopilas ocurrio en el verno', correct),
        TypedAnswerVerdict.close,
      );
    });

    test('una transposición cuenta como un solo error', () {
      expect(verdictOf('mitocnodria', 'mitocondria'), TypedAnswerVerdict.close);
    });

    test('dos descuidos en un texto largo todavía son "casi"', () {
      expect(
        verdictOf(
          'la fotosintesis ocurre en los cloroplastos de las plantas verdes',
          'La fotosíntesis ocurre en los cloroplastos de las plantas verdes.',
        ),
        TypedAnswerVerdict.match,
      );
      expect(
        verdictOf(
          'la fotosintesis ocurre en los clorplastos de las plnatas verdes',
          'La fotosíntesis ocurre en los cloroplastos de las plantas verdes.',
        ),
        TypedAnswerVerdict.close,
      );
    });
  });

  group('alternativas y paréntesis', () {
    test('una alternativa también vale', () {
      final r = compareTypedAnswer(
        typed: 'Roma antigua',
        correct: 'Roma',
        alternatives: ['Roma antigua'],
      );
      expect(r.verdict, TypedAnswerVerdict.match);
    });

    test('un paréntesis de la respuesta es opcional', () {
      expect(
        verdictOf('mitocondria', 'Mitocondria (orgánulo)'),
        TypedAnswerVerdict.match,
      );
      expect(
        verdictOf('mitocondria organulo', 'Mitocondria (orgánulo)'),
        TypedAnswerVerdict.match,
      );
    });

    test(
      'entre dos que no coinciden, la diferencia es contra la más cercana',
      () {
        final r = compareTypedAnswer(
          typed: 'abcdefgh',
          correct: 'zzzzzzzz',
          alternatives: ['abcdzzzz'],
        );

        expect(r.verdict, TypedAnswerVerdict.mismatch);
        expect(r.distance, 4);
        expect(r.expectedSegments.first.expectedText, startsWith('abcd'));
      },
    );

    test('se queda con la alternativa más cercana', () {
      final r = compareTypedAnswer(
        typed: 'Nueva York',
        correct: 'NYC',
        alternatives: ['Nueva York', 'New York'],
      );
      expect(r.verdict, TypedAnswerVerdict.match);
    });
  });

  group('la diferencia para mostrar', () {
    test('iguales: todo es "same" y cada lado conserva lo que escribió', () {
      final r = compareTypedAnswer(
        typed: 'roma, antigua',
        correct: 'Roma Antigua',
      );

      expect(r.verdict, TypedAnswerVerdict.match);
      expect(r.segments, hasLength(1));
      expect(r.segments.single.kind, TypedAnswerSegmentKind.same);
      expect(typedView(r), 'roma, antigua');
      expect(expectedView(r), 'Roma Antigua');
    });

    test('una palabra que falta se marca en lo correcto, no en lo escrito', () {
      final r = compareTypedAnswer(
        typed: 'Segunda Guerra',
        correct: 'Segunda Guerra Mundial',
      );

      expect(r.verdict, TypedAnswerVerdict.mismatch);
      expect(typedView(r), 'Segunda Guerra');
      expect(expectedView(r), 'Segunda Guerra [+Mundial+]');
    });

    test('una palabra de más se marca en lo escrito', () {
      final r = compareTypedAnswer(
        typed: 'Napoleón Bonaparte emperador',
        correct: 'Napoleón Bonaparte',
      );

      expect(typedView(r), 'Napoleón Bonaparte [-emperador-]');
      expect(expectedView(r), 'Napoleón Bonaparte');
    });

    test('una palabra con un descuido se marca por letras', () {
      final r = compareTypedAnswer(
        typed: 'la mitocondira es clave',
        correct: 'La mitocondria es clave',
      );

      expect(r.verdict, TypedAnswerVerdict.close);
      expect(typedView(r), contains('[-'));
      expect(expectedView(r), contains('[+'));
      // Lo que no cambió queda sin marcar en los dos lados.
      expect(typedView(r), startsWith('la mitocond'));
      expect(expectedView(r), startsWith('La mitocond'));
      expect(typedView(r), endsWith('es clave'));
      expect(expectedView(r), endsWith('es clave'));
    });

    test('una letra de más y una de menos', () {
      final r = compareTypedAnswer(typed: 'Washinton', correct: 'Washington');

      expect(typedView(r), 'Washinton');
      expect(expectedView(r), 'Washin[+g+]ton');
    });

    test(
      'una letra cambiada: una sale de lo escrito y otra entra en lo correcto',
      () {
        final r = compareTypedAnswer(typed: 'Servantes', correct: 'Cervantes');

        expect(typedView(r), '[-S-]ervantes');
        expect(expectedView(r), '[+C+]ervantes');
      },
    );

    test('el artículo de más o de menos no se marca como error', () {
      final conArticulo = compareTypedAnswer(
        typed: 'el Imperio romano',
        correct: 'Imperio romano',
      );
      expect(conArticulo.verdict, TypedAnswerVerdict.match);
      expect(typedView(conArticulo), 'el Imperio romano');
      expect(expectedView(conArticulo), 'Imperio romano');
      expect(
        conArticulo.segments.any((s) => s.kind != TypedAnswerSegmentKind.same),
        isFalse,
      );

      final sinArticulo = compareTypedAnswer(
        typed: 'Imperio romano',
        correct: 'El Imperio romano',
      );
      expect(sinArticulo.verdict, TypedAnswerVerdict.match);
      expect(expectedView(sinArticulo), 'El Imperio romano');
      expect(typedView(sinArticulo), 'Imperio romano');
    });

    test('la puntuación no se marca como error', () {
      final r = compareTypedAnswer(typed: 'Madrid', correct: 'Madrid.');

      expect(r.verdict, TypedAnswerVerdict.match);
      expect(
        r.segments.every((s) => s.kind == TypedAnswerSegmentKind.same),
        isTrue,
      );
    });

    test('una palabra distinta sale entera de un lado y entra del otro', () {
      final r = compareTypedAnswer(typed: 'mitocondria', correct: 'ribosoma');

      expect(r.verdict, TypedAnswerVerdict.mismatch);
      expect(
        typedView(r).replaceAll('[-', '').replaceAll('-]', ''),
        'mitocondria',
      );
      expect(
        expectedView(r).replaceAll('[+', '').replaceAll('+]', ''),
        'ribosoma',
      );
    });

    test('los segmentos juntos reconstruyen los dos textos', () {
      const typed = 'La revolucion fransesa empezo en mil setecientos';
      const correct = 'La Revolución Francesa empezó en 1789';
      final r = compareTypedAnswer(typed: typed, correct: correct);

      expect(r.typedSegments.map((s) => s.typedText).join(), typed);
      expect(r.expectedSegments.map((s) => s.expectedText).join(), correct);
    });

    test('con tildes en lo escrito no hay marca', () {
      final r = compareTypedAnswer(typed: 'Napoleón', correct: 'napoleon');

      expect(r.verdict, TypedAnswerVerdict.match);
      expect(typedView(r), 'Napoleón');
      expect(expectedView(r), 'napoleon');
    });
  });

  group('distancia de edición', () {
    test('casos conocidos', () {
      expect(editDistance('', ''), 0);
      expect(editDistance('abc', ''), 3);
      expect(editDistance('', 'abc'), 3);
      expect(editDistance('gato', 'pato'), 1);
      expect(editDistance('abcd', 'abdc'), 1);
      expect(editDistance('kitten', 'sitting'), 3);
      expect(editDistance('🍍a', 'a'), 1);
    });

    test('la versión con franja coincide con la exacta (al azar)', () {
      final random = Random(31);
      String randomText(int length) => String.fromCharCodes(
        List.generate(length, (_) => 97 + random.nextInt(4)),
      );
      for (var round = 0; round < 400; round++) {
        final a = randomText(random.nextInt(40));
        final b = randomText(random.nextInt(40));
        final exact = editDistance(a, b);
        for (final limit in [0, 1, 2, 3, 8]) {
          expect(
            boundedEditDistance(a, b, limit),
            exact <= limit ? exact : limit + 1,
            reason: '"$a" contra "$b" con límite $limit (exacta $exact)',
          );
        }
      }
    });

    test(
      'un texto enorme con dos descuidos lejanos es "casi" sin colgarse',
      () {
        final words = List.generate(6000, (i) => 'palabra${i % 23}x');
        final correct = words.join(' ');
        final typedWords = [...words]
          ..[100] = 'palabr${100 % 23}x'
          ..[5900] = 'palabr${5900 % 23}x';
        final watch = Stopwatch()..start();
        final r = compareTypedAnswer(
          typed: typedWords.join(' '),
          correct: correct,
        );
        watch.stop();

        expect(r.verdict, TypedAnswerVerdict.close);
        expect(r.distance, 2);
        expect(watch.elapsedMilliseconds, lessThan(10000));
      },
    );

    test('en un texto enorme, 8 descuidos todavía son "casi" y 9 ya no', () {
      final words = List.generate(6000, (i) => 'palabra${i % 23}x');
      final correct = words.join(' ');
      String withTypos(int count) {
        final typed = [...words];
        for (var k = 0; k < count; k++) {
          final at = 10 + k * 700;
          typed[at] = 'palabr${at % 23}x';
        }
        return typed.join(' ');
      }

      final ocho = compareTypedAnswer(typed: withTypos(8), correct: correct);
      expect(ocho.distance, 8);
      expect(ocho.verdict, TypedAnswerVerdict.close);

      final nueve = compareTypedAnswer(typed: withTypos(9), correct: correct);
      expect(nueve.verdict, TypedAnswerVerdict.mismatch);
      expect(nueve.distance, greaterThan(8));
    });
  });

  group('bordes', () {
    test('vacío: no coincide, está en blanco y todo lo correcto falta', () {
      final r = compareTypedAnswer(typed: '', correct: 'Madrid');

      expect(r.verdict, TypedAnswerVerdict.mismatch);
      expect(r.isBlank, isTrue);
      expect(r.similarity, 0);
      expect(expectedView(r), '[+Madrid+]');
      expect(r.typedSegments, isEmpty);
    });

    test('solo blancos o signos cuenta como vacío', () {
      expect(
        compareTypedAnswer(typed: '  ?? ', correct: 'a b').isBlank,
        isTrue,
      );
      expect(compareTypedAnswer(typed: '\n\t', correct: 'x').isBlank, isTrue);
    });

    test('la respuesta correcta vacía nunca coincide con algo escrito', () {
      final r = compareTypedAnswer(typed: 'algo', correct: '');

      expect(r.verdict, TypedAnswerVerdict.mismatch);
      expect(typedView(r), '[-algo-]');
    });

    test('las dos vacías: en blanco, sin romper', () {
      final r = compareTypedAnswer(typed: '', correct: '');

      expect(r.isBlank, isTrue);
      expect(r.verdict, TypedAnswerVerdict.mismatch);
      expect(r.segments, isEmpty);
    });

    test(
      'un artículo solo, escrito o esperado, se compara como una palabra',
      () {
        expect(verdictOf('el', 'el'), TypedAnswerVerdict.match);
        expect(verdictOf('la', 'el'), TypedAnswerVerdict.mismatch);
      },
    );

    test('Unicode: emoji, ñ y alfabetos distintos no rompen ni se parten', () {
      expect(verdictOf('piña 🍍', 'Piña 🍍'), TypedAnswerVerdict.match);
      expect(verdictOf('Привет', 'привет!'), TypedAnswerVerdict.match);
      final r = compareTypedAnswer(typed: 'niño 🧒🏽', correct: 'niña 🧒🏽');
      expect(typedView(r), contains('niñ'));
    });

    test('un texto largo (500 palabras) con un descuido es "casi"', () {
      final words = List.generate(500, (i) => 'palabra${i % 17}x');
      final correct = words.join(' ');
      final typedWords = [...words]..[250] = 'palabra${250 % 17}';
      final r = compareTypedAnswer(
        typed: typedWords.join(' '),
        correct: correct,
      );

      expect(r.verdict, TypedAnswerVerdict.close);
      expect(r.distance, 1);
      expect(
        r.segments.where((s) => s.kind != TypedAnswerSegmentKind.same),
        hasLength(1),
      );
    });

    test('un texto largo con muchos cambios no se cuelga y no coincide', () {
      final correct = List.generate(3000, (i) => 'alfa$i').join(' ');
      final typed = List.generate(3000, (i) => 'beta$i').join(' ');
      final watch = Stopwatch()..start();
      final r = compareTypedAnswer(typed: typed, correct: correct);
      watch.stop();

      expect(r.verdict, TypedAnswerVerdict.mismatch);
      expect(watch.elapsedMilliseconds, lessThan(20000));
      // Aunque no se alinee palabra por palabra, el texto se reconstruye.
      expect(
        r.typedSegments.map((s) => s.typedText).join(' ').length,
        greaterThan(0),
      );
    });

    test('la similitud va de 0 a 1', () {
      final igual = compareTypedAnswer(typed: 'Roma', correct: 'roma');
      final casi = compareTypedAnswer(
        typed: 'mitocondira',
        correct: 'mitocondria',
      );
      final nada = compareTypedAnswer(typed: 'abcdef', correct: 'uvwxyz');

      expect(igual.similarity, 1);
      expect(casi.similarity, inInclusiveRange(0.7, 0.99));
      expect(nada.similarity, lessThan(0.2));
    });
  });
}
