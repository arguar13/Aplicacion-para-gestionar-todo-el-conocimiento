import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/data/voices/cloud_text_to_speech_service.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/speech_clip_player.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';

import '../../../../support/fake_offline_speech.dart';
import '../../../../support/fake_voice_cloud.dart';

const _clonada = NarrationVoice(
  name: 'mia:v1',
  locale: 'es-AR',
  engine: NarrationEngine.cloud,
);

void main() {
  late Directory clips;
  late FakeVoiceCloud cloud;
  late FakeSpeechClipPlayer player;
  late CloudTextToSpeechService service;
  late List<NarrationEvent> events;
  late List<int> words;

  setUp(() async {
    final temp = Directory.systemTemp.createTempSync('nube-');
    addTearDown(() => temp.deleteSync(recursive: true));
    clips = Directory(p.join(temp.path, 'voz-en-la-nube'));
    cloud = FakeVoiceCloud();
    player = FakeSpeechClipPlayer();
    service = CloudTextToSpeechService(
      cloud: cloud,
      player: player,
      cloudVoiceIdOf: (voice) async => voice == _clonada ? 'eleven-1' : null,
      clipsDirectory: () async => clips,
    );
    events = [];
    words = [];
    service.events.listen(events.add);
    service.progress.listen(words.add);
    addTearDown(service.dispose);
    await service.setVoice(_clonada);
  });

  test('pide el tramo a ElevenLabs con la voz de allá, y lo hace sonar a la '
      'velocidad elegida sin volver a pedirlo', () async {
    await service.setSpeed(1.5);
    await service.speak('Hola, mundo.');
    expect(cloud.spoken.single, (voiceId: 'eleven-1', text: 'Hola, mundo.'));
    final clip = player.played.single as FileSpeechClip;
    expect(p.dirname(clip.path), clips.path);
    expect(player.speeds.single, 1.5);

    player
      ..advance(0.5)
      ..finish();
    await pumpEventQueue();
    expect(events, [NarrationEvent.completed]);
    // A la mitad: «mundo», que empieza en el 6.
    expect(words, [6]);
    // Sonó y se borró.
    expect(File(clip.path).existsSync(), isFalse);
  });

  test('el que sigue se pide mientras suena, una sola vez', () async {
    await service.speak('Uno.');
    await service.prepare('Dos.');
    await service.prepare('Dos.');
    await pumpEventQueue();
    await service.speak('Dos.');
    expect([for (final s in cloud.spoken) s.text], ['Uno.', 'Dos.']);
  });

  test('una voz que no es de la nube no lee', () async {
    await service.setVoice(
      const NarrationVoice(name: 'es-ar-x-local', locale: 'es-AR'),
    );
    await expectLater(
      service.speak('Hola.'),
      throwsA(isA<VoiceCloudException>()),
    );
    expect(cloud.spoken, isEmpty);
  });

  test('si ElevenLabs falla, falla el tramo', () async {
    cloud.failures['speak'] = const VoiceCloudException(
      VoiceCloudFailure.noCredits,
    );
    await expectLater(
      service.speak('Hola.'),
      throwsA(
        isA<VoiceCloudException>().having(
          (e) => e.failure,
          'failure',
          VoiceCloudFailure.noCredits,
        ),
      ),
    );
    expect(player.played, isEmpty);
  });

  test('cortado mientras llega, no suena', () async {
    final speaking = service.speak('Hola.');
    await service.stop();
    await speaking;
    expect(player.played, isEmpty);
  });
}
