import 'dart:convert';

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

/// Un texto estudiado: dos líneas, y adentro de la primera las oraciones y
/// palabras que se leen aparte.
const _studiedText = 'Uno dos tres. Cuatro cinco seis.\nSiete ocho.';

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

  group('leer una parte: todo, el resumen o las palabras clave (F39)', () {
    List<ReadableSegment> within(String part, {String key = 'texto'}) {
      final start = _studiedText.indexOf(part);
      return buildReadableSegmentsWithin(
        _studiedText,
        start,
        start + part.length,
        sourceKey: key,
      );
    }

    ReadableDocument studied({bool withText = true}) => ReadableDocument(
      id: 'item:2',
      title: 'Estudiado',
      segments: withText
          ? buildReadableSegments(_studiedText, sourceKey: 'texto')
          : const [],
      scopes: {
        ReadScope.summary: [
          ...within('Cuatro cinco seis.'),
          ...within('Siete ocho.'),
        ],
        ReadScope.synthesis: const [],
        ReadScope.keywords: [...within('cinco'), ...within('ocho')],
      },
    );

    (int, int)? highlight() =>
        container.read(readAloudHighlightProvider('texto'));

    test('abrir sin decir la parte lee todo, como siempre', () async {
      await controller().open(studied());

      expect(state().scope, ReadScope.all);
      expect(tts.spoken, ['Uno dos tres. Cuatro cinco seis.']);
    });

    test('las oraciones del resumen suenan una tras otra, en el orden del '
        'texto, y cada una se resalta en su lugar del texto entero', () async {
      await controller().open(studied(), scope: ReadScope.summary);

      expect(state().scope, ReadScope.summary);
      expect(tts.spoken, ['Cuatro cinco seis.']);
      expect(highlight(), (
        _studiedText.indexOf('Cuatro'),
        _studiedText.indexOf('Cuatro') + 'Cuatro cinco seis.'.length,
      ));

      tts.completeCurrent();
      await pumpEventQueue();
      expect(tts.spoken, ['Cuatro cinco seis.', 'Siete ocho.']);
      expect(highlight(), (_studiedText.indexOf('Siete'), _studiedText.length));

      tts.completeCurrent();
      await pumpEventQueue();
      expect(state().playing, isFalse);
      expect(tts.spoken, hasLength(2));
    });

    test('las palabras clave se leen una tras otra', () async {
      await controller().open(studied(), scope: ReadScope.keywords);

      expect(tts.spoken, ['cinco']);
      tts.completeCurrent();
      await pumpEventQueue();
      expect(tts.spoken, ['cinco', 'ocho']);
      expect(highlight(), (
        _studiedText.indexOf('ocho'),
        _studiedText.indexOf('ocho') + 4,
      ));
    });

    test('sin texto propio —ya suena en su audio—, empieza por lo estudiado: '
        'la primera parte que tenga algo', () async {
      await controller().open(studied(withText: false));

      expect(state().scope, ReadScope.summary);
      expect(tts.spoken, ['Cuatro cinco seis.']);
    });

    test('una parte sin nada que leer no abre nada', () async {
      await controller().open(studied(), scope: ReadScope.synthesis);

      expect(state().document, isNull);
      expect(tts.spoken, isEmpty);
    });

    test('elegir otra parte corta lo que suena y la lee desde el '
        'principio', () async {
      await controller().open(studied());
      tts.emitProgress(4);
      await pumpEventQueue();

      await controller().setScope(ReadScope.keywords);

      expect(state().scope, ReadScope.keywords);
      expect(state().segmentIndex, 0);
      expect(state().charInSegment, 0);
      expect(state().playing, isTrue);
      expect(tts.stopCount, 1);
      expect(tts.spoken.last, 'cinco');
      expect(state().document?.id, 'item:2');
    });

    test(
      'elegir la parte que ya se lee, o una vacía, no cambia nada',
      () async {
        await controller().open(studied(), scope: ReadScope.summary);
        final spoken = [...tts.spoken];

        await controller().setScope(ReadScope.summary);
        await controller().setScope(ReadScope.synthesis);

        expect(state().scope, ReadScope.summary);
        expect(tts.spoken, spoken);
      },
    );

    test('elegir una parte en pausa la lee sonando', () async {
      await controller().open(studied());
      await controller().pause();

      await controller().setScope(ReadScope.summary);

      expect(state().playing, isTrue);
      expect(tts.spoken.last, 'Cuatro cinco seis.');
    });

    test('sin documento, elegir una parte no hace nada', () async {
      await controller().setScope(ReadScope.summary);

      expect(state().document, isNull);
      expect(tts.spoken, isEmpty);
    });

    test('el avance y los saltos cuentan solo lo de la parte', () async {
      await controller().open(studied(), scope: ReadScope.keywords);
      // "cinco" y "ocho": 9 caracteres en total.
      expect(state().progress, 0);

      tts.completeCurrent();
      await pumpEventQueue();
      expect(state().segmentIndex, 1);
      expect(state().progress, closeTo(5 / 9, 1e-9));

      await controller().skip(const Duration(seconds: 10));
      expect(state().playing, isFalse);
      expect(state().segmentIndex, 1);
      expect(state().charInSegment, 4);
    });

    test('volver a abrir el mismo documento sigue donde iba; pidiendo otra '
        'parte, la empieza', () async {
      await controller().open(studied(), scope: ReadScope.summary);
      tts.completeCurrent();
      await pumpEventQueue();
      expect(state().segmentIndex, 1);

      await controller().open(studied());
      expect(state().scope, ReadScope.summary);
      expect(state().segmentIndex, 1);
      expect(tts.spoken, ['Cuatro cinco seis.', 'Siete ocho.']);

      await controller().open(studied(), scope: ReadScope.keywords);
      expect(state().scope, ReadScope.keywords);
      expect(state().segmentIndex, 0);
      expect(tts.spoken.last, 'cinco');
    });

    test('si el documento vuelve con otro texto, los saltos cuentan el '
        'nuevo', () async {
      ReadableDocument version(List<String> pieces) => ReadableDocument(
        id: 'item:9',
        title: 'Cambiante',
        segments: const [],
        scopes: {
          ReadScope.summary: [
            for (final (i, piece) in pieces.indexed)
              ReadableSegment(
                sourceKey: 'texto',
                start: i * 200,
                end: i * 200 + piece.length,
                spoken: piece,
              ),
          ],
        },
      );
      final long = List.filled(10, 'palabra').join(' ');
      await controller().open(version(['Corto']));

      await controller().open(version([long, long, long]));
      await controller().skip(const Duration(seconds: 10));

      // Diez segundos son unos 140 caracteres: cae adentro de la segunda
      // línea y sigue sonando, no queda terminado como con el texto viejo.
      expect(state().playing, isTrue);
      expect(state().segmentIndex, 1);
    });

    test('si el documento vuelve sin la parte que se leía, sigue con lo '
        'que haya', () async {
      await controller().open(studied(), scope: ReadScope.summary);

      await controller().open(
        ReadableDocument(
          id: 'item:2',
          title: 'Estudiado',
          segments: buildReadableSegments(_studiedText, sourceKey: 'texto'),
        ),
      );

      expect(state().scope, ReadScope.all);
      expect(state().segmentIndex, 0);
      expect(tts.spoken.last, 'Uno dos tres. Cuatro cinco seis.');
    });

    test('cerrar vuelve a leer todo la próxima vez', () async {
      await controller().open(studied(), scope: ReadScope.keywords);
      await controller().close();

      expect(state().scope, ReadScope.all);
    });

    test('readAloudRunProvider dice si esa parte de ese documento suena, '
        'está en pausa o no se lee', () async {
      const summary = (documentId: 'item:2', scope: ReadScope.summary);
      const keywords = (documentId: 'item:2', scope: ReadScope.keywords);
      const other = (documentId: 'item:3', scope: ReadScope.summary);
      ReadAloudRun run(({String documentId, ReadScope scope}) key) =>
          container.read(readAloudRunProvider(key));

      expect(run(summary), ReadAloudRun.none);

      await controller().open(studied(), scope: ReadScope.summary);
      expect(run(summary), ReadAloudRun.playing);
      expect(run(keywords), ReadAloudRun.none);
      expect(run(other), ReadAloudRun.none);

      await controller().pause();
      expect(run(summary), ReadAloudRun.paused);

      controller().minimize();
      expect(run(summary), ReadAloudRun.paused);

      await controller().close();
      expect(run(summary), ReadAloudRun.none);
    });
  });

  group('empezar por lo que se ve (escuchar dentro del documento)', () {
    /// Diez líneas de "_words"; la vista está donde diga [place].
    ReadablePlace? place;
    ReadablePlace? whereLooking() => place;
    ReadableDocument looking() => ReadableDocument(
      id: 'libro',
      title: 'Un libro',
      segments: _words.segments,
      scopes: {
        ReadScope.summary: [_words.segments[2], _words.segments[7]],
      },
      startAt: whereLooking,
    );

    setUp(() => place = null);

    test('sin decir desde dónde, empieza por la línea que se ve', () async {
      place = (sourceKey: 'palabras', offset: _words.segments[4].start);

      await controller().open(looking());

      expect(state().segmentIndex, 4);
      expect(tts.spoken, [_words.segments[4].spoken]);
    });

    test('a mitad de una línea, empieza por esa línea', () async {
      place = (sourceKey: 'palabras', offset: _words.segments[4].end - 1);

      await controller().open(looking());

      expect(state().segmentIndex, 4);
    });

    test('desde dónde, dicho, manda', () async {
      place = (sourceKey: 'palabras', offset: _words.segments[4].start);

      await controller().open(looking(), fromSegment: 1);

      expect(state().segmentIndex, 1);
    });

    test('en otro texto, o pasado el final, desde el principio', () async {
      place = (sourceKey: 'otro', offset: _words.segments[4].start);
      await controller().open(looking());
      expect(state().segmentIndex, 0);
      await controller().close();

      place = (sourceKey: 'palabras', offset: 1 << 20);
      await controller().open(looking());
      expect(state().segmentIndex, 0);
    });

    test('elegir otra parte la empieza por lo que se ve ahora, no por lo que '
        'se veía al abrir', () async {
      await controller().open(looking());
      expect(state().segmentIndex, 0);

      place = (sourceKey: 'palabras', offset: _words.segments[5].start);
      await controller().setScope(ReadScope.summary);

      expect(state().scope, ReadScope.summary);
      expect(state().segmentIndex, 1);
      expect(tts.spoken.last, _words.segments[7].spoken);
    });

    test('el mismo documento que ya se lee sigue donde iba', () async {
      await controller().open(looking(), fromSegment: 2);

      place = (sourceKey: 'palabras', offset: _words.segments[8].start);
      await controller().open(looking());

      expect(state().segmentIndex, 2);
    });

    test('es parte de ser el mismo documento', () {
      expect(looking(), looking());
      expect(looking().hashCode, looking().hashCode);
      expect(looking(), isNot(looking().withStartAt(null)));
      expect(looking().withScopes(const {}).startAt, whereLooking);
      expect(looking().withOwnAudio().startAt, whereLooking);
    });
  });

  group('el avance', () {
    test('cuenta lo dicho de cada pedazo y lo de antes, sin recorrer '
        'todo', () async {
      // Cada línea de "_words" dice 39 caracteres.
      await controller().open(_words, fromSegment: 3);
      tts.emitProgress(8);
      await pumpEventQueue();

      expect(state().progress, closeTo((3 * 39 + 8) / 390, 1e-9));
    });

    test('pasado el último pedazo, todo', () {
      expect(ReadAloudState(document: _words, segmentIndex: 10).progress, 1);
      expect(
        ReadAloudState(
          document: _words,
          segmentIndex: 9,
          charInSegment: 99,
        ).progress,
        1,
      );
    });

    test('sin nada que decir, nada', () {
      const silent = ReadableDocument(
        id: 'mudo',
        title: 'Mudo',
        segments: [
          ReadableSegment(sourceKey: 'x', start: 0, end: 0, spoken: ''),
        ],
      );
      expect(const ReadAloudState(document: silent).progress, 0);
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

  group('la voz sigue al idioma del texto (F47, paso 3)', () {
    /// Dos oraciones en español y, en el medio, dos en inglés.
    final bilingual = ReadableDocument(
      id: 'dos-idiomas',
      title: 'Dos idiomas',
      segments: buildReadableSegments(
        'La historia de la ciudad es larga y los que la cuentan son muchos.\n'
        'As the old saying goes, the river is the road of the people.\n'
        'And the people of the river were the first to build it.\n'
        'Después vinieron los demás, con lo que tenían en las manos.',
        sourceKey: 'dos-idiomas',
      ),
    );
    const english = NarrationVoice(name: 'en-us-x-sfg-local', locale: 'en-US');
    const daniela = NarrationVoice(
      name: 'vits-piper-es_AR-daniela-high#0',
      locale: 'es-AR',
      engine: NarrationEngine.offline,
    );

    test('cada parte se lee con la voz elegida para su idioma', () async {
      await start(
        stored: {
          'narration_voice': 'es-ar-x-local\u0000es-AR',
          'narration_voices_by_language':
              r'{"en": "en-us-x-sfg-local\u0000en-US"}',
        },
      );

      await controller().open(bilingual);
      expect(tts.lastVoice, _voice);
      for (var i = 0; i < 3; i++) {
        tts.completeCurrent();
        await pumpEventQueue();
        expect(tts.lastVoice, i < 2 ? english : _voice, reason: 'pedazo $i');
        expect(state().voice, tts.lastVoice);
      }
      expect(tts.spoken, hasLength(4));
    });

    test(
      'sin una elegida para el idioma, la del teléfono en ese idioma',
      () async {
        await start(stored: {'narration_voice': 'es-ar-x-local\u0000es-AR'});
        tts = FakeTextToSpeechService(voices: const [_voice, english]);
        container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            textToSpeechServiceProvider.overrideWithValue(tts),
            narrationClockProvider.overrideWithValue(() => now),
          ],
        );
        addTearDown(container.dispose);
        controller();
        await pumpEventQueue();

        await controller().open(bilingual, fromSegment: 1);

        expect(tts.lastVoice, english);
      },
    );

    test('sin ninguna en ese idioma, la del sistema: nunca una de otro '
        'idioma', () async {
      await start(stored: {'narration_voice': 'es-ar-x-local\u0000es-AR'});

      await controller().open(bilingual, fromSegment: 1);

      expect(tts.lastVoice, isNull);
      expect(tts.voiceSetCount, 1);
    });

    test(
      'lo que no se sabe en qué idioma está, con la última elegida',
      () async {
        await start(stored: {'narration_voice': 'es-ar-x-local\u0000es-AR'});

        await controller().open(_words);

        expect(tts.lastVoice, _voice);
      },
    );

    test(
      'una voz sin conexión que ya no está en el teléfono no se usa',
      () async {
        await start(
          stored: {
            'narration_voices_by_language': jsonEncode({
              'es': 'vits-piper-es_AR-daniela-high#0\u0000es-AR\u0000offline',
            }),
          },
        );
        expect(
          container
              .read(narrationSettingsNotifierProvider)
              .voicesByLanguage['es'],
          daniela,
        );

        await controller().open(bilingual);

        expect(tts.lastVoice, isNull);
      },
    );

    test('elegir una voz de otro idioma la deja para ese idioma, sin cortar '
        'lo que se lee', () async {
      await start(stored: {'narration_voice': 'es-ar-x-local\u0000es-AR'});
      await controller().open(bilingual);

      await controller().setVoice(english);

      expect(state().voice, _voice);
      expect(tts.spoken, hasLength(1));
      expect(
        container
            .read(narrationSettingsNotifierProvider)
            .voicesByLanguage['en'],
        english,
      );
      tts.completeCurrent();
      await pumpEventQueue();
      expect(tts.lastVoice, english);
    });

    test(
      'elegir la del sistema deja sin elegida al idioma que se lee',
      () async {
        await start(stored: {'narration_voice': 'es-ar-x-local\u0000es-AR'});
        await controller().open(bilingual);

        await controller().setVoice(null);

        final settings = container.read(narrationSettingsNotifierProvider);
        expect(settings.voicesByLanguage.containsKey('es'), isFalse);
        expect(state().voice, isNull);
        expect(tts.lastVoice, isNull);
      },
    );

    test('mientras dice un pedazo, deja listo el que sigue si es de la misma '
        'voz', () async {
      await start(
        stored: {
          'narration_voices_by_language':
              r'{"en": "en-us-x-sfg-local\u0000en-US"}',
        },
      );
      await controller().open(bilingual, fromSegment: 1);

      // El segundo, en inglés como el primero: listo. El tercero, en
      // español, es otra voz: no.
      expect(tts.prepared, [bilingual.segments[2].spoken]);
      tts.completeCurrent();
      await pumpEventQueue();
      expect(tts.prepared, hasLength(1));
    });

    test('después de prestar el motor a una muestra, le vuelve a poner su '
        'voz y su velocidad', () async {
      await start(
        stored: {
          'narration_voice': 'es-ar-x-local\u0000es-AR',
          'narration_speed': 1.25,
        },
      );
      await controller().open(_document);
      await controller().pause();
      controller().lendEngine();
      await tts.setVoice(english);
      await tts.setSpeed(1);

      await controller().play();

      expect(tts.lastVoice, _voice);
      expect(tts.lastSpeed, 1.25);
    });
  });
}
