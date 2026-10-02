import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/services/pcm16_samples.dart';
import 'package:sinapsis/features/transform/domain/entities/timed_text.dart';

void main() {
  group('de las piezas de Whisper a palabras con su momento (F23)', () {
    test('cada palabra lleva el momento de la pieza que la empieza, con la '
        'puntuación pegada como en el texto', () {
      // Lo que devuelve sherpa-onnx: piezas y el segundo en que empieza
      // cada una (medido sobre la voz de referencia).
      final timed = timedTextFromTokens(
        [' Buenos', ' días', ' a', ' todos', '.', ' contar', 'les', ' algo'],
        [0.10, 0.44, 0.74, 0.80, 1.20, 2.15, 2.40, 2.70],
        fallback: 'Buenos días a todos. contarles algo',
      );

      expect(timed.words, const [
        TimedWord('Buenos', 100),
        TimedWord('días', 440),
        TimedWord('a', 740),
        TimedWord('todos.', 800),
        TimedWord('contarles', 2150),
        TimedWord('algo', 2700),
      ]);
      expect(timed.text, 'Buenos días a todos. contarles algo');
    });

    test('sin tiempos —un modelo que no los calcula—, el texto sin '
        'tiempos: nunca uno inventado', () {
      final timed = timedTextFromTokens(
        [' Hola', ' mundo'],
        const [],
        fallback: 'Hola mundo',
      );

      expect(timed.text, 'Hola mundo');
      expect(timed.words.every((w) => w.startMs == null), isTrue);
    });

    test('si las piezas no forman el texto, tampoco se atribuyen tiempos', () {
      final timed = timedTextFromTokens(
        [' Hola'],
        [0.5],
        fallback: 'Hola mundo',
      );

      expect(timed.text, 'Hola mundo');
      expect(timed.isTimed, isFalse);
    });
  });

  group('guardar y retomar un tramo', () {
    test('con tiempos, vuelve igual', () {
      const timed = TimedText([
        TimedWord('Hola,', 120),
        TimedWord('mundo', 480),
      ]);

      expect(TimedText.decode(timed.encode()), timed);
    });

    test('sin tiempos se guarda el texto tal cual, como antes de F23: lo '
        'guardado por una versión anterior se retoma sin tiempos', () {
      expect(TimedText.plain('dos palabras').encode(), 'dos palabras');
      expect(TimedText.decode('lo de antes'), TimedText.plain('lo de antes'));
      expect(TimedText.decode(''), TimedText.empty);
    });
  });

  test('correr un texto lo lleva a su lugar en el audio entero', () {
    const timed = TimedText([TimedWord('a', 0), TimedWord('b', 300)]);

    expect(timed.shifted(14500).words, const [
      TimedWord('a', 14500),
      TimedWord('b', 14800),
    ]);
  });
}
