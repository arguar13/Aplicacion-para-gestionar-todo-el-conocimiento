import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/data/voices/kokoro_style_bank.dart';
import 'package:sinapsis/features/narration/data/voices/my_voices_service.dart';
import 'package:sinapsis/features/narration/data/voices/my_voices_store.dart';
import 'package:sinapsis/features/narration/data/voices/offline_voice_files.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/recording_check.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_samples.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/fake_offline_speech.dart';
import '../../../../support/fake_voice_cloud.dart';
import '../../../../support/on_device_harness.dart';

/// Un banco de estilos de mentira: anota qué se le pidió escribir y deja un
/// archivo donde se le dice.
class _FakeBank implements KokoroStyleBank {
  final writes =
      <({String source, String target, Map<int, KokoroBlend> blends})>[];

  @override
  Future<void> write({
    required String source,
    required String target,
    required Map<int, KokoroBlend> blends,
  }) async {
    writes.add((source: source, target: target, blends: blends));
    File(target)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('estilos ${blends.keys}');
  }
}

final _blend = KokoroBlend(
  locale: 'es',
  timbre: const [BlendPart(28, 0.6), BlendPart(3, 0.4)],
  prosody: const [BlendPart(28, 1)],
  pace: 0.95,
);

const _design = VoiceDesign(
  locale: 'es',
  gender: VoiceGender.female,
  style: VoiceStyle.calm,
);

const _report = RecordingReport(
  total: Duration(seconds: 90),
  voiced: Duration(seconds: 75),
  noiseDb: -70,
  voiceDb: -18,
  clippedRatio: 0,
);

void main() {
  late Directory root;
  late MyVoicesStore store;
  late OfflineVoiceFiles files;
  late FakeOfflineSpeechSynthesizer synthesizer;
  late FakeVoiceCloud cloud;
  late _FakeBank bank;
  late MyVoicesService service;

  /// Pone Kokoro «bajado»: su carpeta con la ficha y un `voices.bin`.
  void installKokoro() {
    final folder = Directory(
      p.join(root.path, 'modelos', 'voces', OfflineVoiceCatalog.kokoro.id),
    );
    final base = Directory(p.join(folder.path, 'kokoro-multi'))
      ..createSync(recursive: true);
    File(p.join(base.path, 'voices.bin')).writeAsStringSync('estilos');
    File(p.join(folder.path, '.voz.json')).writeAsStringSync(
      const OfflineVoiceManifest(
        base: 'kokoro-multi',
        model: 'model.int8.onnx',
      ).encode(),
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('mias-servicio-');
    store = MyVoicesStore(rootDirectory: () async => root);
    files = OfflineVoiceFiles(
      transfer: FakeModelTransfer(),
      rootDirectory: () async => root,
    );
    synthesizer = FakeOfflineSpeechSynthesizer();
    cloud = FakeVoiceCloud();
    bank = _FakeBank();
    service = MyVoicesService(
      store: store,
      ids: FakeIdGenerator(),
      clock: () => DateTime.utc(2026, 10, 31, 15),
      files: files,
      synthesizer: synthesizer,
      cloud: cloud,
      bank: bank,
    );
    addTearDown(() async {
      await store.dispose();
      await files.dispose();
      root.deleteSync(recursive: true);
    });
  });

  group('crear en el teléfono', () {
    test('sin Kokoro no se puede', () async {
      expect(await service.canCreateOnPhone(), isFalse);
      installKokoro();
      expect(await service.canCreateOnPhone(), isTrue);
    });

    test('cada voz creada toma el primer lugar libre, y uno borrado se '
        'vuelve a usar', () async {
      final a = await service.createOnPhone(
        name: ' Clara ',
        blend: _blend,
        design: _design,
        description: 'mujer serena',
      );
      final b = await service.createOnPhone(
        name: 'Beto',
        blend: _blend,
        design: _design,
      );
      expect(a.slot, 0);
      expect(b.slot, 1);
      expect(a.name, 'Clara');
      expect(a.origin, VoiceOrigin.created);
      expect(a.home, MyVoiceHome.phone);
      expect(a.gender, VoiceGender.female);
      expect(a.styles, {VoiceStyle.calm});
      expect(a.description, 'mujer serena');
      expect(b.description, isNull);
      await service.delete(a);
      final c = await service.createOnPhone(
        name: 'Ceci',
        blend: _blend,
        design: _design,
      );
      expect(c.slot, 0);
    });

    test('con todos los lugares ocupados, lo dice', () async {
      for (var i = 0; i < kokoroSpeakerSlots; i++) {
        await store.save(
          MyVoice(
            id: 'v$i',
            name: 'V$i',
            origin: VoiceOrigin.created,
            home: MyVoiceHome.phone,
            locale: 'es',
            createdAt: DateTime.utc(2026),
            blend: _blend,
            slot: i,
          ),
        );
      }
      await expectLater(
        service.createOnPhone(name: 'Una más', blend: _blend, design: _design),
        throwsA(
          isA<MyVoiceException>().having(
            (e) => e.problem,
            'problem',
            MyVoiceProblem.noRoom,
          ),
        ),
      );
    });

    test(
      'lee como un hablante del voices.bin de las creadas, armado una vez '
      'y de nuevo solo si cambian; el motor suelta los estilos viejos',
      () async {
        installKokoro();
        final voice = await service.createOnPhone(
          name: 'Clara',
          blend: _blend,
          design: _design,
        );
        final offline = (await service.offlineVoiceOf(voice.narrationVoice))!;
        expect(offline.isBlend, isTrue);
        expect(offline.speakerId, voice.slot);
        expect(offline.pace, 0.95);
        expect(offline.kokoroPhonemes, const KokoroPhonemes.espeak('es'));

        final engine = (await service.engineConfigOf(offline))!;
        expect(engine.voices, endsWith('creadas.voices.bin'));
        expect(engine.espeakVoice, 'es');
        expect(bank.writes, hasLength(1));
        expect(bank.writes.single.blends, {0: _blend});
        expect(bank.writes.single.source, endsWith('voices.bin'));
        expect(synthesizer.releases, 1);

        // Sin cambios, ni se escribe ni se suelta.
        await service.engineConfigOf(offline);
        expect(bank.writes, hasLength(1));
        expect(synthesizer.releases, 1);

        await service.createOnPhone(
          name: 'Beto',
          blend: _blend,
          design: _design,
        );
        await service.engineConfigOf(offline);
        expect(bank.writes, hasLength(2));
        expect(bank.writes.last.blends.keys, {0, 1});
        expect(synthesizer.releases, 2);
      },
    );

    test('las del catálogo leen de su paquete, sin el voices.bin de las '
        'creadas', () async {
      installKokoro();
      final heart = OfflineVoiceCatalog.byId('kokoro-int8-multi-lang-v1_0#3')!;
      final engine = (await service.engineConfigOf(heart))!;
      expect(
        engine.voices,
        p.join(
          root.path,
          'modelos',
          'voces',
          OfflineVoiceCatalog.kokoro.id,
          'kokoro-multi',
          'voices.bin',
        ),
      );
      expect(bank.writes, isEmpty);
      expect(
        await service.offlineVoiceOf(
          const NarrationVoice(
            name: 'kokoro-int8-multi-lang-v1_0#3',
            locale: 'en-US',
            engine: NarrationEngine.offline,
          ),
        ),
        heart,
      );
    });

    test('una propia que ya no está no lee', () async {
      expect(
        await service.offlineVoiceOf(
          const NarrationVoice(
            name: 'mia:no-esta',
            locale: 'es',
            engine: NarrationEngine.offline,
          ),
        ),
        isNull,
      );
    });

    test('la muestra se dice con la mezcla en el lugar 0 de un voices.bin '
        'aparte, a su ritmo', () async {
      installKokoro();
      final output = p.join(root.path, 'muestra.wav');
      await service.previewOnPhone(
        blend: _blend,
        text: 'Hola.',
        outputPath: output,
      );
      expect(bank.writes.single.blends, {0: _blend});
      expect(bank.writes.single.target, endsWith('muestra.voices.bin'));
      final request = synthesizer.requests.single;
      expect(request.speakerId, 0);
      expect(request.speed, 0.95);
      expect(request.engine.voices, endsWith('muestra.voices.bin'));
      expect(request.outputPath, output);
      expect(synthesizer.releases, 1);
    });

    test('sin Kokoro, la muestra lo dice', () async {
      await expectLater(
        service.previewOnPhone(blend: _blend, text: 'Hola.', outputPath: 'x'),
        throwsA(isA<MyVoiceException>()),
      );
    });
  });

  group('en ElevenLabs', () {
    late File sample;

    setUp(() {
      sample = File(p.join(root.path, 'grabado.wav'))
        ..writeAsStringSync('audio');
    });

    VoiceConsent consent() => VoiceConsent(
      kind: VoiceConsentKind.permission,
      personName: 'Jorge',
      grantedAt: DateTime.utc(2026, 10, 31, 14),
    );

    test('clonar sube la muestra, y guarda la voz con su consentimiento, su '
        'grabación y una muestra ya generada', () async {
      final voice = await service.cloneInCloud(
        name: 'Papá',
        locale: 'es-AR',
        consent: consent(),
        sample: sample,
        report: _report,
        uploaded: false,
      );
      expect(cloud.clones.single.samplePath, sample.path);
      expect(cloud.clones.single.name, 'Papá');
      expect(voice.cloudVoiceId, 'clonada-0');
      expect(voice.origin, VoiceOrigin.cloned);
      expect(voice.home, MyVoiceHome.elevenLabs);
      expect(voice.consent, consent());
      expect(voice.recording!.file, 'grabacion.wav');
      expect(voice.recording!.report.voiced, _report.voiced);
      expect((await service.recordingOf(voice))!.readAsStringSync(), 'audio');
      // La muestra se pidió una vez, en su idioma.
      expect(cloud.spoken.single.text, voiceSampleText('es'));
      expect(await service.sampleFileOf(voice), isNotNull);
      expect((await service.list()).single.consent, consent());
    });

    test('si guardarla acá falla después de clonarla, se borra allá', () async {
      cloud.failures['speak'] = const VoiceCloudException(
        VoiceCloudFailure.network,
      );
      await expectLater(
        service.cloneInCloud(
          name: 'Papá',
          locale: 'es-AR',
          consent: consent(),
          sample: sample,
          report: _report,
          uploaded: true,
        ),
        throwsA(isA<VoiceCloudException>()),
      );
      expect(cloud.deleted, ['clonada-0']);
      expect(await service.list(), isEmpty);
    });

    test('crear desde una descripción guarda la propuesta elegida con su '
        'audio', () async {
      final previews = await service.designInCloud(
        description: 'mujer serena',
        text: 'texto de muestra',
      );
      final voice = await service.saveDesignedInCloud(
        name: 'Serena',
        description: 'mujer serena',
        preview: previews[1],
        design: _design,
      );
      expect(cloud.saved.single.generatedVoiceId, 'propuesta-1');
      expect(voice.cloudVoiceId, 'diseñada-0');
      expect(voice.origin, VoiceOrigin.created);
      expect(voice.home, MyVoiceHome.elevenLabs);
      expect(voice.sampleFile, 'muestra.mp3');
      expect((await service.sampleFileOf(voice))!.readAsBytesSync(), [1, 1, 1]);
    });

    test('borrar borra allá primero; si allá falla, acá queda, salvo que se '
        'pida borrar solo acá', () async {
      final voice = await service.cloneInCloud(
        name: 'Papá',
        locale: 'es-AR',
        consent: consent(),
        sample: sample,
        report: _report,
        uploaded: false,
      );
      cloud.failures['deleteVoice'] = const VoiceCloudException(
        VoiceCloudFailure.network,
      );
      await expectLater(
        service.delete(voice),
        throwsA(isA<VoiceCloudException>()),
      );
      expect(await service.list(), hasLength(1));
      await service.delete(voice, onlyHere: true);
      expect(await service.list(), isEmpty);
      expect(cloud.deleted, isEmpty);

      final other = await service.cloneInCloud(
        name: 'Mamá',
        locale: 'es-AR',
        consent: consent(),
        sample: sample,
        report: _report,
        uploaded: false,
      );
      await service.delete(other);
      expect(cloud.deleted, [other.cloudVoiceId]);
      expect(await service.list(), isEmpty);
      expect(await service.recordingOf(other), isNull);
    });

    test('sin la nube, nada sale', () async {
      final offline = MyVoicesService(
        store: store,
        ids: FakeIdGenerator(),
        clock: DateTime.now,
      );
      await expectLater(
        offline.designInCloud(description: 'x', text: 'y'),
        throwsA(
          isA<VoiceCloudException>().having(
            (e) => e.failure,
            'failure',
            VoiceCloudFailure.noKey,
          ),
        ),
      );
    });
  });
}
