import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/cloud_reading_gate.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';

import '../../../../support/fake_text_to_speech_service.dart';

const _line =
    'La historia de la ciudad es larga y los que la cuentan son muchos.';

/// Un documento en español de [lines] líneas.
ReadableDocument _document(String id, int lines) => ReadableDocument(
  id: id,
  title: id,
  segments: buildReadableSegments(
    List.filled(lines, _line).join('\n'),
    sourceKey: id,
  ),
);

const _cloned = NarrationVoice(
  name: 'mia:v1',
  locale: 'es-AR',
  engine: NarrationEngine.cloud,
);

const _created = NarrationVoice(
  name: 'mia:v2',
  locale: 'es',
  engine: NarrationEngine.offline,
);

void main() {
  late FakeTextToSpeechService tts;
  late ProviderContainer container;
  late CloudReadingGate gate;
  late List<(NarrationVoice, int)> asked;
  var approve = true;

  Future<void> start({
    required NarrationVoice chosen,
    Set<String> ready = const {'mia:v1', 'mia:v2'},
    bool host = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'narration_voices_by_language': jsonEncode({
        'es':
            '${chosen.name}\u0000${chosen.locale}\u0000'
            '${chosen.engine == NarrationEngine.cloud ? 'cloud' : 'offline'}',
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    tts = FakeTextToSpeechService();
    gate = CloudReadingGate();
    asked = [];
    approve = true;
    if (host) {
      gate.attach((voice, characters) async {
        asked.add((voice, characters));
        return approve;
      });
    }
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        textToSpeechServiceProvider.overrideWithValue(tts),
        narrationClockProvider.overrideWithValue(() => Duration.zero),
        readyMyVoiceNamesProvider.overrideWith((ref) => ready),
        cloudReadingGateProvider.overrideWithValue(gate),
      ],
    );
    addTearDown(container.dispose);
  }

  ReadAloudController controller() =>
      container.read(readAloudControllerProvider.notifier);
  ReadAloudState state() => container.read(readAloudControllerProvider);

  group('leer con una voz de la nube (F47, paso 4)', () {
    test('lo largo pregunta antes, con lo que falta del documento, una sola '
        'vez', () async {
      await start(chosen: _cloned);
      final long = _document('largo', 30);
      await controller().open(long);

      final total = long
          .segmentsOf(ReadScope.all)
          .fold<int>(0, (sum, segment) => sum + segment.spoken.length);
      expect(total, greaterThanOrEqualTo(cloudLongReadCharacters));
      expect(asked, [(_cloned, total)]);
      expect(tts.lastVoice, _cloned);
      expect(tts.spoken, [_line]);
      expect(state().playing, isTrue);

      tts.completeCurrent();
      await pumpEventQueue();
      expect(tts.spoken, hasLength(2));
      expect(asked, hasLength(1));
    });

    test('si no se aprueba, no lee: queda en pausa', () async {
      await start(chosen: _cloned);
      approve = false;
      await controller().open(_document('largo', 30));
      expect(asked, hasLength(1));
      expect(tts.spoken, isEmpty);
      expect(state().playing, isFalse);

      // Volver a tocar ▶ pregunta de nuevo.
      approve = true;
      await controller().play();
      expect(asked, hasLength(2));
      expect(tts.spoken, [_line]);
    });

    test('sin nadie que pregunte, no se gasta', () async {
      await start(chosen: _cloned, host: false);
      await controller().open(_document('largo', 30));
      expect(tts.spoken, isEmpty);
      expect(state().playing, isFalse);
    });

    test('lo corto no pregunta', () async {
      await start(chosen: _cloned);
      await controller().open(_document('corto', 2));
      expect(asked, isEmpty);
      expect(tts.spoken, [_line]);
    });

    test(
      'lo que falta desde donde se empieza, no el documento entero',
      () async {
        await start(chosen: _cloned);
        final long = _document('largo', 30);
        await controller().open(long, fromSegment: 28);
        expect(asked, isEmpty);
        expect(tts.spoken, [_line]);
      },
    );
  });

  group('las voces propias que no pueden leer', () {
    test('una de la nube con la nube apagada lee con la del sistema', () async {
      await start(chosen: _cloned, ready: const {});
      await controller().open(_document('corto', 2));
      expect(tts.lastVoice, isNull);
      expect(asked, isEmpty);
    });

    test('una creada en el teléfono, con Kokoro, lee con su motor', () async {
      await start(chosen: _created);
      await controller().open(_document('largo', 30));
      expect(tts.lastVoice, _created);
      // En el teléfono no se paga: no pregunta.
      expect(asked, isEmpty);
    });

    test('si deja de poder leer mientras lee, se cambia en el acto', () async {
      final ready = StateProvider<Set<String>>((ref) => {'mia:v2'});
      SharedPreferences.setMockInitialValues({
        'narration_voices_by_language': jsonEncode({
          'es': 'mia:v2\u0000es\u0000offline',
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      tts = FakeTextToSpeechService();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          textToSpeechServiceProvider.overrideWithValue(tts),
          narrationClockProvider.overrideWithValue(() => Duration.zero),
          readyMyVoiceNamesProvider.overrideWith((ref) => ref.watch(ready)),
        ],
      );
      addTearDown(container.dispose);
      await controller().open(_document('corto', 2));
      expect(tts.lastVoice, _created);

      container.read(ready.notifier).state = const {};
      await pumpEventQueue();
      expect(state().voice, isNull);
      expect(tts.lastVoice, isNull);
    });
  });
}
