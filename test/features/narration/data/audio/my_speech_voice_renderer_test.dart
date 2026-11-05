import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/data/audio/my_speech_voice_renderer.dart';
import 'package:sinapsis/features/narration/data/voices/eleven_labs_voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/services/offline_speech_synthesizer.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/speech_audio_providers.dart';

import '../../../../support/my_voices_harness.dart';
import 'speech_audio_fakes.dart';

final _cloned = MyVoice(
  id: 'v1',
  name: 'Papá',
  origin: VoiceOrigin.cloned,
  home: MyVoiceHome.elevenLabs,
  locale: 'es-AR',
  createdAt: DateTime.utc(2026, 10, 31),
  cloudVoiceId: 'eleven-1',
  consent: VoiceConsent(
    kind: VoiceConsentKind.permission,
    personName: 'Jorge',
    grantedAt: DateTime.utc(2026, 10, 31),
  ),
);

final _created = MyVoice(
  id: 'v2',
  name: 'Serena',
  origin: VoiceOrigin.created,
  home: MyVoiceHome.phone,
  locale: 'es',
  createdAt: DateTime.utc(2026, 10, 31),
  blend: KokoroBlend(
    locale: 'es',
    timbre: const [BlendPart(28, 0.5), BlendPart(3, 0.5)],
    prosody: const [BlendPart(28, 1)],
    pace: 1.25,
  ),
);

String _id(MyVoice voice) => voice.narrationVoice.name;

Matcher _fails(SpeechAudioFailure failure) => throwsA(
  isA<SpeechAudioException>().having((e) => e.failure, 'failure', failure),
);

/// F47, paso 4, con el paso 6b: las voces propias en la pieza común del audio
/// —el podcast y «Descargar audio»—, `mia:<id>`. Nunca sale a ElevenLabs: la
/// nube y el motor son dobles.
void main() {
  late MyVoicesHarness harness;
  late List<MyVoice> known;
  late Set<String> ready;
  late MySpeechVoiceRenderer renderer;
  late Directory out;

  setUp(() async {
    harness = await MyVoicesHarness.create(
      cloudEnabled: true,
      cloudKey: 'k',
      kokoro: true,
    );
    await harness.store.save(_cloned);
    await harness.store.save(_created);
    known = [_cloned, _created];
    ready = {_id(_cloned), _id(_created)};
    renderer = MySpeechVoiceRenderer(
      service: () => harness.service,
      cloud: () => harness.cloud,
      synthesizer: harness.synthesizer,
      known: () => known,
      ready: () async => ready,
    );
    out = Directory(p.join(harness.root.path, 'salida'))..createSync();
  });
  tearDown(() => harness.dispose());

  String target(String name) => p.join(out.path, name);

  group('quién es y qué cuesta', () {
    test('son las de prefijo mia:, y listas si el lector puede leer con '
        'ellas', () async {
      expect(renderer.owns(_id(_cloned)), isTrue);
      expect(renderer.owns('offline:x#0'), isFalse);
      expect(renderer.owns('device:es:'), isFalse);
      expect(await renderer.isReady(_id(_created)), isTrue);
      ready.remove(_id(_created));
      expect(await renderer.isReady(_id(_created)), isFalse);
      expect(await renderer.isReady('offline:x#0'), isFalse);
    });

    test('la de la nube cobra en créditos, la del teléfono es gratis, y una '
        'que todavía no se conoce cobra: se pregunta antes', () {
      expect(renderer.priceOf(_id(_cloned)), MySpeechVoiceRenderer.cloudPrice);
      expect(
        MySpeechVoiceRenderer.cloudPrice.costOf(1000),
        1000 * ElevenLabsFacts.creditsPerCharacter,
      );
      expect(
        MySpeechVoiceRenderer.cloudPrice.currency,
        ElevenLabsFacts.creditsCurrency,
      );
      expect(renderer.priceOf(_id(_created)), isNull);
      known = const [];
      expect(renderer.priceOf(_id(_created)), MySpeechVoiceRenderer.cloudPrice);
      expect(renderer.priceOf('offline:x#0'), isNull);
    });

    test('la versión sigue al motor y no a lo cargado: un tramo pagado se '
        'reusa aunque las voces no se hayan cargado', () {
      final version = renderer.versionOf(_id(_cloned));
      expect(version, contains(OfflineVoiceCatalog.kokoro.sha256));
      expect(version, contains(ElevenLabsFacts.readingModel));
      known = const [];
      expect(renderer.versionOf(_id(_cloned)), version);
    });
  });

  group('la creada en el teléfono', () {
    test('dice el tramo con Kokoro, su lugar en el voices.bin y su ritmo, a '
        'velocidad 1', () async {
      await renderer.render(
        voiceId: _id(_created),
        text: 'Hola',
        outputPath: target('a.wav'),
      );
      final call = harness.synthesizer.requests.single;
      expect(call.text, 'Hola');
      expect(call.speed, 1.25);
      expect(call.outputPath, target('a.wav'));
      expect(call.speakerId, blendSlots(known)[_created.id]);
      // Con el voices.bin de las creadas, no con el del paquete.
      expect(call.engine.voices, endsWith('creadas.voices.bin'));
      expect(harness.cloud.spoken, isEmpty);
    });

    test('sin Kokoro falta, y un motor que falla es una falla del '
        'motor', () async {
      harness.synthesizer.failWith = const OfflineSpeechException('roto');
      await expectLater(
        renderer.render(
          voiceId: _id(_created),
          text: 'x',
          outputPath: target('b.wav'),
        ),
        _fails(SpeechAudioFailure.engine),
      );
      harness.synthesizer.failWith = null;
      Directory(
        p.join(harness.root.path, 'modelos', 'voces'),
      ).deleteSync(recursive: true);
      await expectLater(
        renderer.render(
          voiceId: _id(_created),
          text: 'x',
          outputPath: target('c.wav'),
        ),
        _fails(SpeechAudioFailure.voiceMissing),
      );
    });
  });

  group('la de la nube', () {
    test('pide el tramo con su id allá y deja el MP3 tal cual', () async {
      final took = await renderer.render(
        voiceId: _id(_cloned),
        text: 'Hola',
        outputPath: target('d.part'),
      );
      expect(harness.cloud.spoken.single, (voiceId: 'eleven-1', text: 'Hola'));
      expect(File(target('d.part')).readAsStringSync(), 'mp3 de: Hola');
      expect(took, Duration.zero);
      expect(harness.synthesizer.requests, isEmpty);
    });

    test('una voz que ElevenLabs ya no tiene falta; sin créditos es una '
        'falla del motor', () async {
      harness.cloud.failures['speak'] = const VoiceCloudException(
        VoiceCloudFailure.voiceNotFound,
      );
      await expectLater(
        renderer.render(
          voiceId: _id(_cloned),
          text: 'x',
          outputPath: target('e'),
        ),
        _fails(SpeechAudioFailure.voiceMissing),
      );
      harness.cloud.failures['speak'] = const VoiceCloudException(
        VoiceCloudFailure.noCredits,
      );
      await expectLater(
        renderer.render(
          voiceId: _id(_cloned),
          text: 'x',
          outputPath: target('f'),
        ),
        _fails(SpeechAudioFailure.engine),
      );
      expect(File(target('f')).existsSync(), isFalse);
    });
  });

  test('una voz que se borró falta', () async {
    await harness.store.delete(_cloned.id);
    await expectLater(
      renderer.render(
        voiceId: _id(_cloned),
        text: 'x',
        outputPath: target('g'),
      ),
      _fails(SpeechAudioFailure.voiceMissing),
    );
  });

  group('en la pieza común (speechVoiceRenderersProvider)', () {
    ProviderContainer containerWith(FakeDecoder decoder) {
      final container = ProviderContainer(
        overrides: [
          ...harness.overrides,
          deviceSpeechToFileAvailableProvider.overrideWithValue(false),
          speechAudioWorkRootProvider.overrideWithValue(
            () async => Directory(p.join(harness.root.path, 'trabajo')),
          ),
          speechAudioEncoderProvider.overrideWithValue(
            FakeEncoder()..supported = false,
          ),
          speechClipDecoderProvider.overrideWithValue(decoder),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('las propias tienen quién las haga, y el costo cuenta solo lo que '
        'lee la de la nube, por voz', () async {
      final container = containerWith(FakeDecoder());
      final audio = container.read(speechAudioRendererProvider);
      expect(audio.rendererOf(_id(_cloned)), isA<MySpeechVoiceRenderer>());
      // Antes de que nadie haya mirado las voces: listas igual.
      expect(await audio.isReady(_id(_cloned)), isTrue);
      expect(await audio.isReady(_id(_created)), isTrue);

      final cost = audio.costOf([
        SpeechAudioPiece(text: 'Hola, ¿cómo va?', voiceId: _id(_cloned)),
        SpeechAudioPiece(text: 'Muy bien.', voiceId: _id(_created)),
        SpeechAudioPiece(text: 'Me alegro.', voiceId: _id(_cloned)),
      ])!;
      expect(cost.charactersByVoice, {_id(_cloned): 15 + 10});
      expect(cost.characters, 25);
      expect(cost.currency, ElevenLabsFacts.creditsCurrency);
    });

    test('genera un audio con las dos: el MP3 de la nube pasa a WAV, y cada '
        'tramo ya hecho no se vuelve a pagar', () async {
      final decoder = FakeDecoder();
      final container = containerWith(decoder);
      final audio = container.read(speechAudioRendererProvider);
      final request = SpeechAudioRequest(
        workKey: 'podcast-prueba',
        pieces: [
          SpeechAudioPiece(text: 'Hola.', voiceId: _id(_cloned)),
          SpeechAudioPiece(text: 'Chau.', voiceId: _id(_created)),
        ],
      );
      final first = await audio.render(request);
      expect(first.starts, hasLength(2));
      expect(harness.cloud.spoken.map((s) => s.text), ['Hola.']);
      expect(harness.synthesizer.requests.map((r) => r.text), ['Chau.']);
      // Los dos tramos llegan como no-WAV (el MP3, y el «audio» del motor de
      // mentira): los dos pasan por el decodificador.
      expect(decoder.calls, hasLength(2));

      // Sin descartar, el mismo trabajo otra vez: nada sale a la nube.
      final again = await audio.render(request);
      expect(again.starts, hasLength(2));
      expect(harness.cloud.spoken, hasLength(1));
    });

    test('apenas abre la app, con la clave todavía cargándose, espera a '
        'saberla en vez de dar la de la nube por faltante', () async {
      final container = ProviderContainer(
        overrides: [
          ...harness.overrides,
          elevenLabsKeyStoreProvider.overrideWithValue(
            ElevenLabsKeyStore(storage: _SlowSecureStorage(harness.secure)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final audio = container.read(speechAudioRendererProvider);
      expect(await audio.isReady(_id(_cloned)), isTrue);
    });

    test('con la nube apagada, la de la nube no está lista y no se le pide '
        'nada', () async {
      final quiet = await MyVoicesHarness.create(kokoro: true);
      addTearDown(quiet.dispose);
      await quiet.store.save(_cloned);
      final container = ProviderContainer(overrides: quiet.overrides);
      addTearDown(container.dispose);
      final audio = container.read(speechAudioRendererProvider);
      expect(await audio.isReady(_id(_cloned)), isFalse);
      expect(quiet.cloud.spoken, isEmpty);
    });
  });
}

/// Un almacén seguro que tarda en contestar, como el de un teléfono recién
/// prendido: lo que tarda es más que leer las fichas del disco.
class _SlowSecureStorage extends FakeSecureStorage {
  _SlowSecureStorage(FakeSecureStorage from) {
    values.addAll(from.values);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final answer = super.noSuchMethod(invocation);
    if (invocation.memberName != #read) return answer;
    return Future<void>.delayed(
      const Duration(milliseconds: 500),
    ).then((_) => answer as Future<String?>);
  }
}
