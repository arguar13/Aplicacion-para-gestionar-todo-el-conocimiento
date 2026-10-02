import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';

import '../../../../support/fake_text_to_speech_service.dart';

/// Tres líneas: "Primera " son 8 caracteres, así que "línea" empieza en 8 y
/// "del" en 14.
const _text = 'Primera línea del texto.\nSegunda línea.\nTercera.';

final _document = ReadableDocument(
  id: 'item:1',
  title: 'Un elemento',
  segments: buildReadableSegments(_text, sourceKey: 'item:1/texto'),
);

/// Diez líneas de diez palabras de tres letras —"L00 L01 … L09", "L10 …"—:
/// cada palabra con su espacio son 4 caracteres y cada línea, 39. Así se
/// puede seguir a mano dónde cae un salto.
final _words = ReadableDocument(
  id: 'palabras',
  title: 'Palabras',
  segments: buildReadableSegments(
    [
      for (var line = 0; line < 10; line++)
        [for (var word = 0; word < 10; word++) 'L$line$word'].join(' '),
    ].join('\n'),
    sourceKey: 'palabras',
  ),
);

const _voice = NarrationVoice(name: 'es-ar-x-local', locale: 'es-AR');

void main() {
  late FakeTextToSpeechService tts;
  late SharedPreferences prefs;
  late ProviderContainer container;
  var now = Duration.zero;

  Future<void> start({Map<String, Object> stored = const {}}) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    tts = FakeTextToSpeechService();
    now = Duration.zero;
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        textToSpeechServiceProvider.overrideWithValue(tts),
        narrationClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
  }

  ReadAloudController controller() =>
      container.read(readAloudControllerProvider.notifier);
  ReadAloudState state() => container.read(readAloudControllerProvider);

  /// El motor dice las palabras que empiezan en [offsets] —relativas a lo
  /// último que se le pidió—, una cada [every].
  Future<void> sayWords(
    List<int> offsets, {
    Duration every = const Duration(milliseconds: 300),
  }) async {
    for (final offset in offsets) {
      tts.emitProgress(offset);
      await pumpEventQueue();
      now += every;
    }
  }

  setUp(start);

  group('abrir y leer', () {
    test('abrir lee el primer pedazo con la voz y la velocidad '
        'guardadas', () async {
      await start(
        stored: {
          'narration_speed': 1.25,
          'narration_voice': 'es-ar-x-local\u0000es-AR',
        },
      );

      await controller().open(_document);

      expect(tts.spoken, ['Primera línea del texto.']);
      expect(tts.lastSpeed, 1.25);
      expect(tts.lastVoice, _voice);
      expect(state().playing, isTrue);
      expect(state().panel, ReadAloudPanel.expanded);
      expect(state().segmentIndex, 0);
      expect(state().speed, 1.25);
      expect(state().voice, _voice);
    });

    test('abrir desde un pedazo empieza ahí', () async {
      await controller().open(_document, fromSegment: 2);

      expect(tts.spoken, ['Tercera.']);
      expect(state().segmentIndex, 2);
    });

    test('un documento vacío no abre nada', () async {
      await controller().open(
        const ReadableDocument(id: 'vacío', title: '', segments: []),
      );

      expect(tts.spoken, isEmpty);
      expect(state().panel, ReadAloudPanel.hidden);
    });

    test('cada palabra avisada mueve la posición, una vez por '
        'palabra', () async {
      await controller().open(_document);
      final updates = <int>[];
      container.listen(
        readAloudControllerProvider,
        (_, next) => updates.add(next.charInSegment),
      );

      tts.emitProgress(8);
      await pumpEventQueue();
      tts.emitProgress(8);
      await pumpEventQueue();
      tts.emitProgress(14);
      await pumpEventQueue();

      expect(state().charInSegment, 14);
      expect(updates, [8, 14]);
    });

    test('al terminar un pedazo sigue solo con el próximo', () async {
      await controller().open(_document);
      tts.emitProgress(14);
      await pumpEventQueue();

      tts.completeCurrent();
      await pumpEventQueue();

      expect(tts.spoken, ['Primera línea del texto.', 'Segunda línea.']);
      expect(state().segmentIndex, 1);
      expect(state().charInSegment, 0);
    });

    test('al terminar el último se detiene al final, con el reproductor '
        'abierto', () async {
      await controller().open(_document);
      for (var i = 0; i < 3; i++) {
        tts.completeCurrent();
        await pumpEventQueue();
      }

      expect(tts.spoken, hasLength(3));
      expect(state().playing, isFalse);
      expect(state().segmentIndex, 2);
      expect(state().charInSegment, 'Tercera.'.length);
      expect(state().progress, 1);
      expect(state().panel, ReadAloudPanel.expanded);
    });

    test('reproducir después del final vuelve a empezar', () async {
      await controller().open(_document, fromSegment: 2);
      tts.completeCurrent();
      await pumpEventQueue();

      await controller().play();

      expect(tts.spoken.last, 'Primera línea del texto.');
      expect(state().segmentIndex, 0);
      expect(state().playing, isTrue);
    });

    test('si el motor falla, se detiene y lo marca', () async {
      await controller().open(_document);

      tts.failCurrent();
      await pumpEventQueue();

      expect(state().playing, isFalse);
      expect(state().failed, isTrue);

      await controller().play();
      expect(state().failed, isFalse);
      expect(state().playing, isTrue);
    });
  });

  group('pausa de verdad', () {
    test('pausar corta el motor y retomar sigue desde la última '
        'palabra', () async {
      await controller().open(_document);
      tts.emitProgress(8);
      await pumpEventQueue();

      await controller().pause();

      expect(tts.stopCount, 1);
      expect(state().playing, isFalse);
      expect(state().charInSegment, 8);

      await controller().play();

      expect(tts.spoken.last, 'línea del texto.');
      // El progreso de la lectura retomada es relativo a lo que se pidió.
      tts.emitProgress(6);
      await pumpEventQueue();
      expect(state().charInSegment, 14);
    });

    test('un "terminó" o una palabra que llegan después de pausar no '
        'mueven nada', () async {
      await controller().open(_document);
      tts.emitProgress(8);
      await pumpEventQueue();
      await controller().pause();

      tts
        ..completeCurrent()
        ..emitProgress(14);
      await pumpEventQueue();

      expect(state().segmentIndex, 0);
      expect(state().charInSegment, 8);
      expect(tts.spoken, hasLength(1));
    });

    test('alternar pausa y reproducción', () async {
      await controller().open(_document);

      await controller().togglePlay();
      expect(state().playing, isFalse);

      await controller().togglePlay();
      expect(state().playing, isTrue);
      expect(tts.spoken, hasLength(2));
    });
  });

  group('±10 s de habla (decisión A)', () {
    test('sin nada medido, 10 s son unos 14 caracteres por segundo, al '
        'comienzo de una palabra', () async {
      await controller().open(_words);

      await controller().skip(const Duration(seconds: 10));

      // 140 caracteres: la línea 3 (desde 117), carácter 23 —el espacio
      // después de "L35"—: la palabra que sigue.
      expect(state().segmentIndex, 3);
      expect(state().charInSegment, 24);
      expect(tts.spoken.last, startsWith('L36 '));
    });

    test('con el ritmo medido, salta lo que esa voz dice en 10 s y cruza '
        'pedazos', () async {
      await controller().open(_words);
      // Una palabra —4 caracteres— cada 0,3 s: 13,3 caracteres por segundo.
      await sayWords([0, 4, 8, 12, 16, 20, 24, 28, 32, 36]);
      expect(state().charInSegment, 36);

      await controller().skip(const Duration(seconds: 10));

      // 36 + 133 = 169: la línea 4 (desde 156), carácter 13, dentro de
      // "L43": su comienzo.
      expect(state().segmentIndex, 4);
      expect(state().charInSegment, 12);
      expect(tts.stopCount, 1);
      expect(tts.spoken.last, startsWith('L43 '));

      await controller().skip(const Duration(seconds: -10));

      // 168 - 133 = 35: el espacio antes de "L09".
      expect(state().segmentIndex, 0);
      expect(state().charInSegment, 36);
      expect(tts.spoken.last, 'L09');
    });

    test('una pausa larga entre dos palabras no cuenta para el '
        'ritmo', () async {
      await controller().open(_words);
      await sayWords([0, 4, 8, 12, 16]);
      now += const Duration(seconds: 30);
      await sayWords([20, 24, 28, 32, 36]);

      await controller().skip(const Duration(seconds: 10));

      // Igual que sin la pausa: 13,3 caracteres por segundo.
      expect(state().segmentIndex, 4);
      expect(state().charInSegment, 12);
    });

    test('en pausa, salta sin leer', () async {
      await controller().open(_words);
      await controller().pause();

      await controller().skip(const Duration(seconds: 10));

      expect(state().segmentIndex, 3);
      expect(state().charInSegment, 24);
      expect(state().playing, isFalse);
      expect(tts.spoken, hasLength(1));
    });

    test('retroceder desde el principio no hace nada', () async {
      await controller().open(_words);

      await controller().skip(const Duration(seconds: -10));

      expect(state().segmentIndex, 0);
      expect(state().charInSegment, 0);
      expect(tts.spoken, hasLength(1));
    });

    test('retroceder vuelve a la palabra anterior aunque sea en el pedazo '
        'de antes', () async {
      await controller().open(_words, fromSegment: 1);

      await controller().skip(const Duration(milliseconds: -100));

      expect(state().segmentIndex, 0);
      expect(state().charInSegment, 36);
    });

    test('avanzar un poco pasa a la palabra siguiente', () async {
      await controller().open(_words);

      await controller().skip(const Duration(milliseconds: 100));

      expect(state().charInSegment, 4);
      expect(tts.spoken.last, startsWith('L01 '));
    });

    test('avanzar más allá del final lo deja terminado', () async {
      await controller().open(_words, fromSegment: 9);

      await controller().skip(const Duration(seconds: 10));

      expect(state().playing, isFalse);
      expect(state().segmentIndex, 9);
      expect(state().progress, 1);
      expect(tts.stopCount, 1);
    });
  });

  group('voz y velocidad', () {
    test('cambiar la velocidad la guarda y se oye enseguida, desde la misma '
        'palabra', () async {
      await controller().open(_document);
      tts.emitProgress(8);
      await pumpEventQueue();

      await controller().setSpeed(1.5);

      expect(state().speed, 1.5);
      expect(tts.lastSpeed, 1.5);
      expect(prefs.getDouble('narration_speed'), 1.5);
      expect(container.read(narrationSettingsNotifierProvider).speed, 1.5);
      expect(tts.stopCount, 1);
      expect(tts.spoken.last, 'línea del texto.');
    });

    test('la velocidad nueva escala el ritmo de los saltos', () async {
      await controller().open(_words);
      await controller().pause();

      await controller().setSpeed(2);
      await controller().skip(const Duration(seconds: 10));

      // 28 caracteres por segundo: 280 = línea 7 (desde 273), carácter 7,
      // el espacio después de "L71": la palabra que sigue.
      expect(state().segmentIndex, 7);
      expect(state().charInSegment, 8);
    });

    test('en pausa, cambiar la velocidad no lee', () async {
      await controller().open(_document);
      await controller().pause();

      await controller().setSpeed(0.75);

      expect(tts.lastSpeed, 0.75);
      expect(tts.spoken, hasLength(1));
    });

    test('la velocidad queda entre 0,5 y 2', () async {
      await controller().setSpeed(5);

      expect(state().speed, 2);
    });

    test('cambiar la voz la guarda, y volver a la del sistema la '
        'borra', () async {
      await controller().open(_document);

      await controller().setVoice(_voice);

      expect(state().voice, _voice);
      expect(tts.lastVoice, _voice);
      expect(prefs.getString('narration_voice'), 'es-ar-x-local\u0000es-AR');
      expect(tts.spoken, hasLength(2));

      await controller().setVoice(null);

      expect(state().voice, isNull);
      expect(prefs.getString('narration_voice'), isNull);
      expect(container.read(narrationSettingsNotifierProvider).voice, isNull);
    });
  });

  group('el reproductor', () {
    test('abrir otra vez el mismo documento no vuelve a empezar', () async {
      await controller().open(_document);
      tts.completeCurrent();
      await pumpEventQueue();
      controller().minimize();
      expect(state().panel, ReadAloudPanel.minimized);

      await controller().open(_document);

      expect(tts.spoken, hasLength(2));
      expect(state().segmentIndex, 1);
      expect(state().panel, ReadAloudPanel.expanded);
    });

    test('abrir otro documento corta el que sonaba y lee el nuevo', () async {
      await controller().open(_document);

      await controller().open(_words);

      expect(tts.stopCount, 1);
      expect(tts.spoken.last, startsWith('L00 '));
      expect(state().document, _words);
    });

    test('minimizar y expandir sin nada abierto no muestran nada', () {
      controller()
        ..minimize()
        ..expand();

      expect(state().panel, ReadAloudPanel.hidden);
    });

    test('cerrar corta, olvida el documento y conserva la voz y la '
        'velocidad', () async {
      await controller().open(_document);
      await controller().setSpeed(1.5);
      final stops = tts.stopCount;

      await controller().close();

      expect(tts.stopCount, stops + 1);
      expect(state().document, isNull);
      expect(state().panel, ReadAloudPanel.hidden);
      expect(state().playing, isFalse);
      expect(state().speed, 1.5);

      tts.completeCurrent();
      await pumpEventQueue();
      expect(tts.spoken, hasLength(2));
    });
  });

  group('readAloudHighlightProvider', () {
    test('resalta el pedazo de ahora solo en su texto', () async {
      final chat = documentFrom('chat', 'Chat', [
        (sourceKey: 'm1', text: 'Hola', markdown: false, transcript: false),
        (sourceKey: 'm2', text: 'Uno\nDos', markdown: false, transcript: false),
      ]);
      (int, int)? highlight(String key) =>
          container.read(readAloudHighlightProvider(key));

      expect(highlight('m1'), isNull);

      await controller().open(chat);
      expect(highlight('m1'), (0, 4));
      expect(highlight('m2'), isNull);

      tts.completeCurrent();
      await pumpEventQueue();
      expect(highlight('m1'), isNull);
      expect(highlight('m2'), (0, 3));

      tts.completeCurrent();
      await pumpEventQueue();
      expect(highlight('m2'), (4, 7));

      await controller().close();
      expect(highlight('m2'), isNull);
    });
  });
}
