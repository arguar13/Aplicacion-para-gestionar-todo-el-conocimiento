import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/data/services/routing_text_to_speech_service.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';

import '../../../../support/fake_text_to_speech_service.dart';

const _phone = NarrationVoice(name: 'es-ar-x-local', locale: 'es-AR');
const _daniela = NarrationVoice(
  name: 'vits-piper-es_AR-daniela-high#0',
  locale: 'es-AR',
  engine: NarrationEngine.offline,
);

void main() {
  late FakeTextToSpeechService system;
  late FakeTextToSpeechService offline;
  late RoutingTextToSpeechService router;
  late List<NarrationEvent> events;
  late List<int> words;

  setUp(() {
    system = FakeTextToSpeechService(voices: const [_phone]);
    offline = FakeTextToSpeechService();
    router = RoutingTextToSpeechService(system: system, offline: offline);
    events = [];
    words = [];
    router.events.listen(events.add);
    router.progress.listen(words.add);
    addTearDown(router.dispose);
  });

  group('un lector, dos motores (F47, paso 3)', () {
    test('cada voz lee con su motor', () async {
      await router.setVoice(_phone);
      await router.speak('Del teléfono.');
      await router.setVoice(_daniela);
      await router.speak('Sin conexión.');
      await router.prepare('La que sigue.');

      expect(system.spoken, ['Del teléfono.']);
      expect(offline.spoken, ['Sin conexión.']);
      expect(offline.prepared, ['La que sigue.']);
      expect(offline.lastVoice, _daniela);
    });

    test('pasar al otro motor corta el que sonaba', () async {
      await router.setVoice(_phone);
      await router.speak('Del teléfono.');
      await router.setVoice(_daniela);
      expect(system.stopCount, 1);
    });

    test('solo cuenta lo que avisa el motor de la voz elegida', () async {
      await router.setVoice(_daniela);
      system
        ..completeCurrent()
        ..emitProgress(4);
      offline
        ..emitProgress(7)
        ..completeCurrent();
      await pumpEventQueue();

      expect(events, [NarrationEvent.completed]);
      expect(words, [7]);
    });

    test('la velocidad vale para los dos', () async {
      await router.setSpeed(1.5);
      expect(system.lastSpeed, 1.5);
      expect(offline.lastSpeed, 1.5);
    });

    test('las voces que ofrece son las del teléfono', () async {
      expect(await router.getVoices(), [_phone]);
    });

    test('sin motor sin conexión, una voz sin conexión lee con la del '
        'sistema', () async {
      final alone = RoutingTextToSpeechService(system: system);
      addTearDown(alone.dispose);

      await alone.setVoice(_daniela);
      await alone.speak('Hola.');

      expect(system.lastVoice, isNull);
      expect(system.voiceSetCount, 1);
      expect(system.spoken, ['Hola.']);
    });
  });
}
