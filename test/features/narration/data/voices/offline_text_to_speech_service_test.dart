import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/data/voices/offline_text_to_speech_service.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/offline_speech_synthesizer.dart';
import 'package:sinapsis/features/narration/domain/services/speech_clip_player.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';

import '../../../../support/fake_offline_speech.dart';

final _daniela = OfflineVoiceCatalog.byId('vits-piper-es_AR-daniela-high#0')!;
final _sharvardF = OfflineVoiceCatalog.byId(
  'vits-piper-es_ES-sharvard-medium#1',
)!;

void main() {
  late Directory clips;
  late FakeOfflineSpeechSynthesizer synthesizer;
  late FakeSpeechClipPlayer player;
  late OfflineTextToSpeechService service;
  late List<NarrationEvent> events;
  late List<int> words;
  var installed = true;

  OfflineTextToSpeechService create({bool hold = false}) {
    synthesizer = FakeOfflineSpeechSynthesizer(hold: hold);
    player = FakeSpeechClipPlayer();
    final created = OfflineTextToSpeechService(
      synthesizer: synthesizer,
      player: player,
      engineOf: (voice) async => installed
          ? OfflineVoiceEngineConfig(
              family: voice.package.family,
              model: '${voice.package.id}.onnx',
              tokens: 'tokens.txt',
              dataDir: 'espeak-ng-data',
            )
          : null,
      clipsDirectory: () async => clips,
    );
    events = [];
    words = [];
    created.events.listen(events.add);
    created.progress.listen(words.add);
    addTearDown(created.dispose);
    return created;
  }

  setUp(() async {
    installed = true;
    final temp = Directory.systemTemp.createTempSync('tramos-');
    addTearDown(() => temp.deleteSync(recursive: true));
    clips = Directory(p.join(temp.path, 'voz-sin-conexion'));
    service = create();
    await service.setVoice(narrationVoiceOf(_daniela));
  });

  group('leer con una voz sin conexión (F47, paso 3)', () {
    test('genera el tramo con la voz y la velocidad elegidas, y lo hace '
        'sonar', () async {
      await service.setSpeed(1.5);
      await service.speak('Hola, mundo.');

      final request = synthesizer.requests.single;
      expect(request.text, 'Hola, mundo.');
      expect(request.speakerId, 0);
      expect(request.speed, 1.5);
      expect(request.engine.model, 'vits-piper-es_AR-daniela-high.onnx');
      expect(player.played.single, FileSpeechClip(request.outputPath));
      expect(p.dirname(request.outputPath), clips.path);
    });

    test('el hablante de un paquete con dos voces', () async {
      await service.setVoice(narrationVoiceOf(_sharvardF));
      await service.speak('Hola.');
      expect(synthesizer.requests.single.speakerId, 1);
    });

    test('terminar de sonar avisa que terminó, y borra el tramo', () async {
      await service.speak('Hola, mundo.');
      final path = synthesizer.requests.single.outputPath;
      expect(File(path).existsSync(), isTrue);

      player.finish();
      await pumpEventQueue();

      expect(events, [NarrationEvent.completed]);
      expect(File(path).existsSync(), isFalse);
    });

    test('por qué palabra va, por cuánto sonó: una vez por palabra y nunca '
        'para atrás', () async {
      // «Uno dos tres cuatro»: las palabras empiezan en 0, 4, 8 y 13.
      await service.speak('Uno dos tres cuatro');
      for (final fraction in [0.0, 0.1, 0.25, 0.3, 0.5, 0.4, 0.75, 1.0]) {
        player.advance(fraction);
      }
      await pumpEventQueue();
      expect(words, [0, 4, 8, 13]);
    });

    test('el próximo tramo se genera mientras suena el de ahora, y se usa '
        'tal cual', () async {
      await service.speak('Primera oración.');
      await service.prepare('Segunda oración.');
      await pumpEventQueue();
      expect(synthesizer.requests.map((r) => r.text), [
        'Primera oración.',
        'Segunda oración.',
      ]);

      player.finish();
      await pumpEventQueue();
      await service.speak('Segunda oración.');

      // No se volvió a generar.
      expect(synthesizer.requests, hasLength(2));
      expect(
        player.played.last,
        FileSpeechClip(synthesizer.requests[1].outputPath),
      );
    });

    test('lo preparado con otra velocidad no sirve: se genera de nuevo, y lo '
        'viejo se borra', () async {
      await service.prepare('Segunda oración.');
      await pumpEventQueue();
      final stale = synthesizer.requests.single.outputPath;
      await pumpEventQueue();
      await service.setSpeed(2);
      await pumpEventQueue();

      await service.speak('Segunda oración.');

      expect(synthesizer.requests, hasLength(2));
      expect(synthesizer.requests.last.speed, 2);
      expect(File(stale).existsSync(), isFalse);
    });

    test('cortado mientras genera, no suena', () async {
      service = create(hold: true);
      await service.setVoice(narrationVoiceOf(_daniela));
      final speaking = service.speak('Hola.');
      await pumpEventQueue();

      await service.stop();
      synthesizer.finishNext();
      await speaking;

      expect(player.played, isEmpty);
      expect(clips.listSync(), isEmpty);
    });

    test('un tramo cortado no avisa que terminó ni por dónde iba', () async {
      await service.speak('Uno dos tres');
      await service.stop();
      player.advance(0.9);
      await pumpEventQueue();

      expect(events, isEmpty);
      expect(words, isEmpty);
    });

    test('si no se pudo generar, lo dice al pedirlo', () async {
      synthesizer.failWith = StateError('modelo roto');
      await expectLater(
        service.speak('Hola.'),
        throwsA(isA<OfflineSpeechException>()),
      );
    });

    test('una voz que ya no está en el teléfono no lee', () async {
      installed = false;
      await expectLater(
        service.speak('Hola.'),
        throwsA(isA<OfflineSpeechException>()),
      );
    });

    test('si el tramo no se pudo hacer sonar, avisa el error', () async {
      await service.speak('Hola.');
      player.fail();
      await pumpEventQueue();
      expect(events, [NarrationEvent.error]);
    });

    test('una voz del sistema no es suya: no lee', () async {
      await service.setVoice(
        const NarrationVoice(name: 'es-ar-x-local', locale: 'es-AR'),
      );
      await expectLater(
        service.speak('Hola.'),
        throwsA(isA<OfflineSpeechException>()),
      );
      await service.prepare('Hola.');
      await pumpEventQueue();
      expect(synthesizer.requests, isEmpty);
    });

    test('lo que quedó de una vez anterior se borra al empezar', () async {
      clips.createSync(recursive: true);
      final old = File(p.join(clips.path, 'viejo.wav'))
        ..writeAsStringSync('viejo');

      await service.speak('Hola.');

      expect(old.existsSync(), isFalse);
    });
  });
}
