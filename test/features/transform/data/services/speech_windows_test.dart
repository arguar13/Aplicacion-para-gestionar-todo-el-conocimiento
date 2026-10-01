import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/services/speech_windows.dart';

const _sr = speechSampleRate;

/// Un audio de [seconds] con "voz" —un tono de amplitud [level]— salvo en
/// las [pauses] (inicio, fin, en segundos), que quedan en silencio.
Float32List _audio(
  double seconds, {
  List<(double, double)> pauses = const [],
  double level = 0.3,
}) {
  final samples = Float32List((seconds * _sr).round());
  for (var i = 0; i < samples.length; i++) {
    final t = i / _sr;
    final paused = pauses.any((p) => t >= p.$1 && t < p.$2);
    samples[i] = paused ? 0 : level * math.sin(2 * math.pi * 220 * t);
  }
  return samples;
}

double _seconds(int sample) => sample / _sr;

void main() {
  group('planWindows', () {
    test('corta en la pausa, no en el segundo exacto', () {
      // Pausas de 200 ms a los 12,8 s y a los 26 s: los dos cortes tienen
      // que caer adentro de ellas, no a los 14,5 s ni a los 29 s.
      final windows = planWindows(
        EnergyProfile.of(_audio(40, pauses: [(12.8, 13.0), (26.0, 26.2)])),
      );

      expect(_seconds(windows[0].end), inInclusiveRange(12.8, 13.0));
      expect(_seconds(windows[1].end), inInclusiveRange(26.0, 26.2));
    });

    test('sin ninguna pausa, ningún tramo pasa del largo máximo, y juntos '
        'cubren el audio entero, sin huecos ni solapes', () {
      final samples = _audio(95);
      final windows = planWindows(EnergyProfile.of(samples));

      expect(windows.first.start, 0);
      expect(windows.last.end, samples.length);
      for (var i = 0; i < windows.length; i++) {
        expect(windows[i].length, lessThanOrEqualTo(maxWindowSamples));
        expect(windows[i].length, greaterThan(0));
        if (i > 0) expect(windows[i].start, windows[i - 1].end);
      }
    });

    test('el mismo audio da siempre los mismos tramos: al retomar, el tramo '
        '12 es el mismo tramo 12', () {
      final samples = _audio(70, pauses: [(20, 20.3), (41, 41.5)]);

      expect(
        planWindows(EnergyProfile.of(samples)),
        planWindows(EnergyProfile.of(samples)),
      );
    });

    test('armar la energía por partes da lo mismo que de una vez', () {
      final samples = _audio(33, pauses: [(10, 10.5)]);
      final builder = EnergyProfileBuilder();
      // Pedazos de largo raro, que no coinciden con los bloques de 10 ms.
      for (var i = 0; i < samples.length; i += 12345) {
        builder.add(
          Float32List.sublistView(
            samples,
            i,
            math.min(i + 12345, samples.length),
          ),
        );
      }

      expect(
        planWindows(builder.build()),
        planWindows(EnergyProfile.of(samples)),
      );
    });

    test('un tramo de silencio puro se marca para no mandarlo al motor', () {
      // 20 s de voz y después 20 s de nada.
      final samples = Float32List(40 * _sr)..setAll(0, _audio(20));
      final windows = planWindows(EnergyProfile.of(samples));

      expect(windows.first.silent, isFalse);
      expect(windows.last.silent, isTrue);
    });

    test('la voz baja no es silencio: solo se descarta lo que está por '
        'debajo de -50 dBFS en todo el tramo', () {
      // Una voz lejana del micrófono, a -40 dBFS.
      final low = planWindows(EnergyProfile.of(_audio(10, level: 0.01)));
      // Ruido de fondo de una habitación en silencio, a -80 dBFS.
      final hiss = planWindows(EnergyProfile.of(_audio(10, level: 0.0001)));

      expect(low.single.silent, isFalse);
      expect(hiss.single.silent, isTrue);
    });

    test('cada tramo, salvo el primero, se transcribe desde 3 s antes de '
        'su corte (F22)', () {
      final windows = planWindows(EnergyProfile.of(_audio(40)));

      expect(windows.first.from, 0);
      for (final window in windows.skip(1)) {
        expect(window.from, window.start - overlapSamples);
        expect(window.decodeLength, window.length + overlapSamples);
      }
    });

    test('un audio vacío no tiene tramos', () {
      expect(planWindows(EnergyProfile.of(Float32List(0))), isEmpty);
    });
  });

  group('stitchOverlappingTexts', () {
    test('la nota de voz del usuario: las palabras del corte salen enteras '
        'y no se repiten', () {
      // Lo que transcribió Whisper en dos tramos seguidos de una nota de voz
      // de 1:52 (F22): el segundo empieza 3 s antes del corte, y cada uno
      // dice mal lo que le queda en el borde — "2C." por "docente".
      const first =
          'no nos olvidemos que son un conjunto de tareas que van a '
          'realizar los estudiantes. No hay intervención 2C.';
      const second =
          'que van a realizar los estudiantes. No hay intervención docente '
          'ahí. Es decir, las tareas puntuales';

      final texts = stitchOverlappingTexts([first, second]);

      // Se corta por la mitad de lo que comparten ("que van a realizar los
      // estudiantes. No hay intervención"): lejos del borde de los dos.
      expect(
        texts.first,
        'no nos olvidemos que son un conjunto de tareas que van a realizar',
      );
      expect(
        texts.last,
        'los estudiantes. No hay intervención docente ahí. Es decir, las '
        'tareas puntuales',
      );
    });

    test('se compara sin mayúsculas ni puntuación, y cada texto conserva '
        'sus palabras como las escribió el motor', () {
      final texts = stitchOverlappingTexts([
        'Hoy hablamos de la paciencia, que es',
        'De la paciencia que es confiar en el tiempo.',
      ]);

      expect(texts, [
        'Hoy hablamos de la',
        'paciencia que es confiar en el tiempo.',
      ]);
    });

    test('sin dos palabras seguidas en común, los dos textos quedan '
        'enteros: puede repetirse algo, pero no se pierde nada', () {
      final texts = stitchOverlappingTexts(['termina acá', '[Música] y sigue']);

      expect(texts, ['termina acá', '[Música] y sigue']);
    });

    test('un tramo en silencio no se une con nada', () {
      final texts = stitchOverlappingTexts([
        'uno dos tres',
        '',
        'tres cuatro cinco',
      ]);

      expect(texts, ['uno dos tres', '', 'tres cuatro cinco']);
    });

    test('un tramo cuyo texto entero está en el solape no repite nada', () {
      final texts = stitchOverlappingTexts([
        'y entonces dijo que sí',
        'dijo que sí',
        'que sí y se fue',
      ]);

      expect(
        texts.where((t) => t.isNotEmpty).join(' '),
        'y entonces dijo que sí y se fue',
      );
    });
  });

  group('looksLikeRepetitionLoop', () {
    test('el bucle medido en la alabanza de prueba es un bucle', () {
      expect(
        looksLikeRepetitionLoop(
          'Yo canta en la bondad de Dios. ${'oh, ' * 90}oh',
        ),
        isTrue,
      );
      expect(looksLikeRepetitionLoop('es tu maquillaje, ' * 20), isTrue);
    });

    test('un texto normal no, y una letra con estribillo tampoco', () {
      // Texto real de la charla de prueba.
      expect(
        looksLikeRepetitionLoop(
          'Los suicidios están más altos que nunca en la historia de la '
          'humanidad. Lo mismo ocurre con los casos de depresión, divorcios '
          'y personas declarándose infelices.',
        ),
        isFalse,
      );
      // El tramo más repetitivo que no era bucle en la alabanza (1,9).
      expect(
        looksLikeRepetitionLoop(
          'Tu fidelidad sigue persiguiéndome Tu fidelidad sigue '
          'persiguiéndome Todo lo que soy te lo entrego hoy a ti me rendiré '
          'Tu fidelidad sigue persiguiéndome',
        ),
        isFalse,
      );
    });

    test('un texto corto no se juzga', () {
      expect(looksLikeRepetitionLoop('sí, sí, sí'), isFalse);
      expect(looksLikeRepetitionLoop(''), isFalse);
    });
  });

  group('transcribeGuarded', () {
    const loop =
        'es tu maquillaje, es tu maquillaje, es tu maquillaje, '
        'es tu maquillaje, es tu maquillaje, es tu maquillaje';

    test('un tramo sin bucle se transcribe una sola vez, tal cual', () {
      var calls = 0;
      final text = transcribeGuarded(_audio(10), (samples) {
        calls++;
        return '  Te amo Dios, tu amor nunca me falla.  ';
      });

      expect(text, 'Te amo Dios, tu amor nunca me falla.');
      expect(calls, 1);
    });

    test('un tramo en bucle se vuelve a transcribir en dos mitades, '
        'cortadas en la pausa más cercana al medio', () {
      final samples = _audio(14, pauses: [(6.5, 6.8)]);
      final lengths = <int>[];
      final text = transcribeGuarded(samples, (part) {
        lengths.add(part.length);
        if (part.length == samples.length) return loop;
        return lengths.length == 2 ? 'de la bondad' : 'de Dios.';
      });

      expect(text, 'de la bondad de Dios.');
      expect(lengths, hasLength(3));
      expect(_seconds(lengths[1]), inInclusiveRange(6.5, 6.8));
      expect(lengths[1] + lengths[2], samples.length);
    });

    test('lo que sigue en bucle después de partirlo queda como un hueco '
        'marcado, con su minuto: nunca el texto inventado', () {
      // Empieza a los 3:15 del audio y dura 14 s: todo en bucle.
      final text = transcribeGuarded(
        _audio(14),
        (_) => loop,
        offset: 195 * _sr,
      );

      expect(text, '[fragmento no reconocido 3:15–3:29]');
      expect(text, isNot(contains('maquillaje')));
    });

    test('si solo una parte sigue en bucle, el resto se conserva', () {
      final samples = _audio(14);
      final text = transcribeGuarded(samples, (part) {
        if (part.length == samples.length) return loop;
        // La primera mitad sale bien; todo lo de la segunda, en bucle.
        return part.offsetInBytes == 0 ? 'Te amo Dios' : loop;
      });

      expect(text, startsWith('Te amo Dios [fragmento no reconocido 0:'));
      expect(text, isNot(contains('maquillaje')));
    });

    test('la marca da las horas en un audio largo', () {
      expect(
        unrecognizedMarker(3725 * _sr, 3739 * _sr),
        '[fragmento no reconocido 1:02:05–1:02:19]',
      );
    });
  });
}
