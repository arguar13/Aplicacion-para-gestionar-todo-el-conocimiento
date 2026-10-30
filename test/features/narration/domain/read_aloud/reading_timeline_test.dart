import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/reading_timeline.dart';

/// Un pedazo con solo lo que se dice: las posiciones en pantalla no cuentan
/// para el tiempo.
ReadableSegment _piece(String spoken) =>
    ReadableSegment(sourceKey: 't', start: 0, end: 0, spoken: spoken);

/// A 1×, 150 palabras por minuto: una palabra son 0,4 s.
const _perWord = Duration(milliseconds: 400);

void main() {
  group('el tiempo, por las palabras y la velocidad', () {
    final timeline = ReadingTimeline.of([
      _piece('Uno dos tres.'),
      _piece('Cuatro cinco.'),
    ]);

    test('el total son las palabras al ritmo de una voz del teléfono', () {
      expect(timeline.words, 5);
      expect(timeline.durationAt(1), _perWord * 5);
    });

    test('a más velocidad dura menos, en proporción', () {
      expect(timeline.durationAt(2), _perWord * 5 ~/ 2);
      expect(timeline.durationAt(0.5), _perWord * 10);
      expect(timeline.durationAt(3), const Duration(microseconds: 666667));
    });

    test('lo transcurrido cuenta las palabras que ya empezaron', () {
      // "Uno dos tres." son 13 caracteres: "Cuatro" empieza en 13.
      expect(timeline.elapsedAt(0, 1), Duration.zero);
      expect(timeline.elapsedAt(4, 1), _perWord);
      // A mitad de "dos", "dos" ya empezó.
      expect(timeline.elapsedAt(5, 1), _perWord * 2);
      expect(timeline.elapsedAt(13, 1), _perWord * 3);
      expect(timeline.elapsedAt(timeline.length, 1), _perWord * 5);
    });

    test('lo que no se dice no suma tiempo', () {
      final withDashes = ReadingTimeline.of([_piece('Hola — mundo « » ¿sí?')]);

      expect(withDashes.words, 3);
    });

    test('un tiempo cae al comienzo de la palabra que se dice entonces', () {
      expect(timeline.positionAt(Duration.zero, 1), 0);
      expect(timeline.positionAt(_perWord * 1.5, 1), 4);
      expect(timeline.positionAt(_perWord * 3, 1), 13);
      expect(timeline.positionAt(_perWord * 9, 1), timeline.length);
      expect(timeline.positionAt(-_perWord, 1), 0);
    });

    test('un pedazo sin palabras no se lleva ninguna', () {
      final gapped = ReadingTimeline.of([
        _piece('Uno.'),
        _piece('—'),
        _piece('Dos.'),
      ]);

      // "Dos." empieza en 4 + 1 = 5.
      expect(gapped.positionAt(_perWord, 1), 5);
      expect(gapped.elapsedAt(5, 1), _perWord);
    });

    test('se arma una vez por lista', () {
      final segments = [_piece('Uno dos.')];

      expect(
        identical(ReadingTimeline.of(segments), ReadingTimeline.of(segments)),
        isTrue,
      );
      expect(
        identical(
          ReadingTimeline.of(segments),
          ReadingTimeline.of([...segments]),
        ),
        isFalse,
      );
    });

    test('ubica una posición en su pedazo', () {
      expect(timeline.locate(0), (0, 0));
      expect(timeline.locate(12), (0, 12));
      expect(timeline.locate(13), (1, 0));
      expect(timeline.locate(timeline.length), (1, 13));
      expect(timeline.startOf(1), 13);
    });

    test('vacía, todo es cero', () {
      final empty = ReadingTimeline.of(const []);

      expect(empty.length, 0);
      expect(empty.durationAt(1), Duration.zero);
      expect(empty.locate(0), (0, 0));
      expect(empty.skip(0, const Duration(seconds: 10), 1), 0);
      expect(empty.skip(0, const Duration(seconds: -10), 1), 0);
    });
  });

  group('±10 s salta a la oración más cercana', () {
    /// Diez oraciones de diez palabras —4 s cada una a 1×—, dos por línea:
    /// "P00 P01 … P09. P10 …". Cada palabra son 3 caracteres, cada oración
    /// 40 con su punto, y cada línea 81, con el espacio entre las dos.
    final timeline = ReadingTimeline.of([
      for (var line = 0; line < 5; line++)
        _piece(
          [
            for (var s = line * 2; s < line * 2 + 2; s++)
              '${[for (var w = 0; w < 10; w++) 'P$s$w'].join(' ')}.',
          ].join(' '),
        ),
    ]);

    /// Dónde empieza la oración [s].
    int sentence(int s) => (s ~/ 2) * 81 + (s.isOdd ? 41 : 0);

    test('10 s para adelante desde el comienzo: 25 palabras, a la misma '
        'distancia de la oración 2 y de la 3 —queda la primera—', () {
      expect(timeline.skip(0, const Duration(seconds: 10), 1), sentence(2));
    });

    test('cruza líneas y cae en la oración de adentro de una línea', () {
      // Desde la oración 2 (8 s), a los 18 s: la palabra 45, la oración 4
      // empieza en la 40 y la 5 en la 50.
      expect(
        timeline.skip(sentence(2), const Duration(seconds: 10), 1),
        sentence(4),
      );
      // A mitad de la oración 2 (palabra 23, 9,2 s): a los 19,2 s, la
      // palabra 48, más cerca de la oración 5.
      expect(
        timeline.skip(sentence(2) + 12, const Duration(seconds: 10), 1),
        sentence(5),
      );
    });

    test('para atrás, la más cercana a ese tiempo', () {
      // Desde la oración 5 (20 s), a los 10 s: entre la 2 y la 3, la 2.
      expect(
        timeline.skip(sentence(5), const Duration(seconds: -10), 1),
        sentence(2),
      );
    });

    test('la velocidad cambia cuánto texto son 10 s', () {
      // A 2×, 10 s son 50 palabras: la oración 5.
      expect(timeline.skip(0, const Duration(seconds: 10), 2), sentence(5));
      // A 0,5×, 12,5 palabras: entre la 1 (10) y la 2 (20), la 1.
      expect(timeline.skip(0, const Duration(seconds: 10), 0.5), sentence(1));
    });

    test('siempre mueve: un salto corto va a la oración de al lado', () {
      expect(
        timeline.skip(sentence(3), const Duration(milliseconds: 100), 1),
        sentence(4),
      );
      expect(
        timeline.skip(sentence(3), const Duration(milliseconds: -100), 1),
        sentence(2),
      );
    });

    test('para atrás desde adentro de una oración vuelve a empezarla', () {
      expect(
        timeline.skip(sentence(3) + 8, const Duration(milliseconds: -100), 1),
        sentence(3),
      );
    });

    test('pasado el final, el final; antes del principio, el principio', () {
      expect(
        timeline.skip(sentence(9), const Duration(seconds: 10), 1),
        timeline.length,
      );
      expect(timeline.skip(0, const Duration(seconds: -10), 1), 0);
      expect(
        timeline.skip(sentence(1), const Duration(seconds: -10), 1),
        sentence(0),
      );
    });

    test('para adelante en la última oración, sin otra después: el final', () {
      final one = ReadingTimeline.of([
        _piece(List.filled(60, 'palabra').join(' ')),
      ]);

      // 60 palabras son 24 s: 10 s caen adentro, pero no hay otra oración.
      expect(one.skip(0, const Duration(seconds: 10), 1), one.length);
    });

    test('los signos que cierran una oración: . ! ? y …', () {
      final marks = ReadingTimeline.of([_piece('Uno! Dos? Tres… Cuatro.')]);

      expect(marks.skip(0, const Duration(milliseconds: 100), 1), 5);
      expect(marks.skip(5, const Duration(milliseconds: 100), 1), 10);
      expect(marks.skip(10, const Duration(milliseconds: 100), 1), 16);
    });
  });
}
