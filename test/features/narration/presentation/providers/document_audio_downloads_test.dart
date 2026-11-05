import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/narration/data/audio/speech_audio_renderer.dart';
import 'package:sinapsis/features/narration/data/audio/speech_wav.dart';
import 'package:sinapsis/features/narration/domain/audio/document_audio.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/providers/document_audio_downloads.dart';
import 'package:sinapsis/features/narration/presentation/providers/document_audio_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/providers/speech_audio_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

import '../../../../support/disk_path_file_store.dart';
import '../../../../support/fake_speech_track_player.dart';
import '../../../../support/fake_text_to_speech_service.dart';
import '../../data/audio/speech_audio_fakes.dart';

/// Lo que se le pide al servicio en primer plano.
class RecordingKeeper implements LongWorkKeeper {
  final calls = <String>[];

  @override
  void working({
    required int done,
    required int total,
    LongWorkKind kind = LongWorkKind.dataSync,
    String? detail,
  }) => calls.add('working $done/$total ${kind.name}');

  @override
  void idle() => calls.add('idle');
}

ReadableDocument _doc(String text, {String id = 'item:1'}) => ReadableDocument(
  id: id,
  title: 'Roma',
  segments: buildReadableSegments(text, sourceKey: id),
);

/// F47, paso 5: descargar el audio de un documento —generado en el teléfono,
/// de a uno, con su avance, cancelable y retomable— y que el lector lo haga
/// sonar desde ese audio mientras siga siendo el de ese texto con esas
/// voces.
void main() {
  late Directory root;
  late FakeVoiceRenderer voices;
  late DiskPathFileStore files;
  late RecordingKeeper keeper;
  late FakeTextToSpeechService tts;
  late FakeSpeechTrackPlayer track;
  late ProviderContainer container;

  Future<void> make({bool supported = true}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        textToSpeechServiceProvider.overrideWithValue(tts),
        speechTrackPlayerProvider.overrideWithValue(track),
        documentAudioSupportedProvider.overrideWithValue(supported),
        fileStoreProvider.overrideWithValue(files),
        speechFallbackLocaleProvider.overrideWithValue('es-AR'),
        speechAudioRendererProvider.overrideWithValue(
          SpeechAudioRenderer(
            voices: () => [voices],
            workRoot: () async => root,
            encoder: FakeEncoder(),
            assemble: (job) async => assembleSpeechWav(job),
          ),
        ),
        documentAudioKeeperProvider.overrideWithValue(keeper),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 5)),
      ],
    );
    addTearDown(container.dispose);
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('doc-audio');
    // Las voces del teléfono, de mentira: hacen un tono por tramo.
    voices = FakeVoiceRenderer(prefix: 'device:');
    files = DiskPathFileStore();
    keeper = RecordingKeeper();
    tts = FakeTextToSpeechService();
    track = FakeSpeechTrackPlayer();
    await make();
  });
  tearDown(() => root.deleteSync(recursive: true));

  DocumentAudioDownloads downloads() =>
      container.read(documentAudioDownloadsProvider.notifier);
  Map<String, DocumentAudioJob> jobs() =>
      container.read(documentAudioDownloadsProvider);
  ReadAloudController controller() =>
      container.read(readAloudControllerProvider.notifier);
  ReadAloudState state() => container.read(readAloudControllerProvider);
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  Future<DocumentAudio?> download(ReadableDocument doc) =>
      downloads().download(doc, downloads().planOf(doc));
  SpeechAudioRenderer renderer() => container.read(speechAudioRendererProvider);

  const timeout = Timeout(Duration(seconds: 30));

  group('descargar', () {
    test('genera cada pedazo con la voz del lector, lo guarda en la bóveda, '
        'suelta el trabajo y avisa al servicio en primer plano', () async {
      final doc = _doc('Uno dos.\nTres cuatro.');
      final progress = <int>[];
      container.listen(
        documentAudioDownloadsProvider,
        (_, next) => progress.add(next[doc.id]?.done ?? -1),
      );

      // Quien ya miraba si tenía audio se entera solo.
      final watched = container.listen(
        documentAudioProvider(doc.id),
        (_, _) {},
      );
      expect(
        await container.read(documentAudioProvider(doc.id).future),
        isNull,
      );

      final audio = await download(doc);

      expect(voices.said, [
        ('device:es-AR:', 'Uno dos.'),
        ('device:es-AR:', 'Tres cuatro.'),
      ]);
      expect(audio, isNotNull);
      expect(audio!.documentId, doc.id);
      expect(audio.starts, hasLength(2));
      expect(audio.fingerprint, downloads().planOf(doc).fingerprint);
      expect(audio.reference, startsWith('originales/audio-documentos/'));
      final stored = await container.read(documentAudioProvider(doc.id).future);
      expect(stored?.reference, audio.reference);
      watched.close();
      // Lo del trabajo se fue: ya está en la bóveda.
      expect(await renderer().hasWork(documentAudioWorkKey(doc.id)), isFalse);
      expect(jobs(), isEmpty);
      expect(progress, containsAllInOrder([0, 1, 2, 3, -1]));
      expect(keeper.calls, [
        'working 0/3 mediaProcessing',
        'working 1/3 mediaProcessing',
        'working 2/3 mediaProcessing',
        'working 3/3 mediaProcessing',
        'idle',
      ]);
    }, timeout: timeout);

    test(
      'cancelar corta, no guarda nada y deja lo hecho para seguir',
      () async {
        final doc = _doc('Uno dos.\nTres cuatro.');
        voices.onSay = (_, text) {
          if (text == 'Uno dos.') downloads().cancel(doc.id);
        };

        expect(await download(doc), isNull);

        expect(jobs(), isEmpty);
        expect(
          await container.read(documentAudioProvider(doc.id).future),
          isNull,
        );
        expect(await renderer().hasWork(documentAudioWorkKey(doc.id)), isTrue);
        expect(keeper.calls.last, 'idle');

        // El próximo intento no rehace lo hecho.
        voices
          ..onSay = null
          ..said.clear();
        expect(await download(doc), isNotNull);
        expect(voices.said, [('device:es-AR:', 'Tres cuatro.')]);
      },
      timeout: timeout,
    );

    test(
      'una voz que falta queda dicha, con su voz, hasta descartarla',
      () async {
        final doc = _doc('Uno dos.');
        voices.missing.add('device:es-AR:');

        await expectLater(
          download(doc),
          throwsA(
            isA<SpeechAudioException>()
                .having(
                  (e) => e.failure,
                  'failure',
                  SpeechAudioFailure.voiceMissing,
                )
                .having((e) => e.voiceId, 'voiceId', 'device:es-AR:'),
          ),
        );
        final job = jobs()[doc.id]!;
        expect(job.phase, DocumentAudioJobPhase.failed);
        expect(job.failure?.failure, SpeechAudioFailure.voiceMissing);
        expect(keeper.calls.last, 'idle');

        downloads().dismiss(doc.id);
        expect(jobs(), isEmpty);
      },
      timeout: timeout,
    );

    test('si no se puede guardar en la bóveda, es una falla del archivo, y '
        'lo generado queda para el próximo intento', () async {
      final doc = _doc('Uno dos.');
      files = _FullDisk();
      await make();

      await expectLater(
        download(doc),
        throwsA(
          isA<SpeechAudioException>().having(
            (e) => e.failure,
            'failure',
            SpeechAudioFailure.file,
          ),
        ),
      );
      expect(jobs()[doc.id]?.phase, DocumentAudioJobPhase.failed);
      expect(await renderer().hasWork(documentAudioWorkKey(doc.id)), isTrue);
    }, timeout: timeout);

    test('de a uno: el segundo espera al primero; pedir lo mismo dos veces es '
        'la misma descarga', () async {
      final first = _doc('Uno dos.');
      final second = _doc('Tres cuatro.', id: 'item:2');
      final gate = Completer<void>();
      voices.onSay = (_, text) {
        if (text == 'Uno dos.' && !gate.isCompleted) {
          // El motor tarda: mientras, se mira la cola.
          expect(jobs()[first.id]?.phase, DocumentAudioJobPhase.running);
          expect(jobs()[second.id]?.phase, DocumentAudioJobPhase.waiting);
          gate.complete();
        }
      };

      final a = download(first);
      final b = download(second);
      expect(identical(download(first), a), isTrue);
      await Future.wait([a, b]);

      expect(gate.isCompleted, isTrue);
      expect(voices.said.map((s) => s.$2), ['Uno dos.', 'Tres cuatro.']);
      expect(jobs(), isEmpty);
    }, timeout: timeout);
  });

  group('escuchar desde el audio descargado', () {
    test(
      'suena desde el archivo, con su tiempo real, y no con la voz',
      () async {
        final doc = _doc('Uno dos.\nTres cuatro.');
        final audio = (await download(doc))!;

        await controller().open(doc);
        await settle();

        expect(track.calls.first, 'open /disco/${audio.reference}');
        expect(track.calls, contains('play'));
        expect(tts.spoken, isEmpty);
        expect(state().recording?.starts, audio.starts);
        expect(state().total, audio.duration);
      },
      timeout: timeout,
    );

    test('volver a ofrecer el mismo texto lo conserva; con otro texto, sigue '
        'con la voz desde el mismo pedazo', () async {
      final doc = _doc('Uno dos.\nTres cuatro.');
      await download(doc);
      await controller().open(doc);
      await settle();

      await controller().open(_doc('Uno dos.\nTres cuatro.'));
      expect(state().recording, isNotNull);

      await controller().open(_doc('Uno dos.\nTres cinco.'));
      await settle();
      expect(state().recording, isNull);
      expect(tts.spoken, isNotEmpty);
    }, timeout: timeout);

    test(
      'si cambió el texto o la voz, quedó viejo: se lee con la voz',
      () async {
        final doc = _doc('Uno dos.\nTres cuatro.');
        await download(doc);

        await controller().open(_doc('Uno dos.\nTres cinco.'));
        await settle();
        expect(state().recording, isNull);
        expect(track.calls, isEmpty);
        expect(tts.spoken, isNotEmpty);
        await controller().close();

        await container
            .read(narrationSettingsNotifierProvider.notifier)
            .selectVoice(const NarrationVoice(name: 'otra', locale: 'es-AR'));
        tts.spoken.clear();
        await controller().open(doc);
        await settle();
        expect(state().recording, isNull);
        expect(track.calls, isEmpty);
        expect(tts.spoken, isNotEmpty);
      },
      timeout: timeout,
    );

    test('sin el archivo, se lee con la voz', () async {
      final doc = _doc('Uno dos.');
      final audio = (await download(doc))!;
      await files.delete(audio.reference);

      await controller().open(doc);
      await settle();
      expect(state().recording, isNull);
      expect(tts.spoken, isNotEmpty);
    }, timeout: timeout);

    test('lo que se pidió último manda, aunque lo de antes siguiera buscando '
        'su audio', () async {
      final doc = _doc('Uno dos.');
      await download(doc);
      final other = _doc('Otra cosa.', id: 'item:2');

      final slow = controller().open(doc);
      final fast = controller().open(other);
      await Future.wait([slow, fast]);
      await settle();

      expect(state().document?.id, 'item:2');
      expect(track.calls, isEmpty);
    }, timeout: timeout);

    test('donde no se descargan audios, el lector ni busca', () async {
      final doc = _doc('Uno dos.');
      await download(doc);
      await make(supported: false);

      expect(container.read(downloadedSpeechLookupProvider), isNull);
      expect(
        await container.read(documentAudioProvider(doc.id).future),
        isNull,
      );
      await controller().open(doc);
      await settle();
      expect(state().recording, isNull);
      expect(tts.spoken, isNotEmpty);
    }, timeout: timeout);
  });
}

/// Un disco lleno: no se puede guardar nada.
class _FullDisk extends DiskPathFileStore {
  @override
  Future<String> saveStream({
    required Stream<List<int>> bytes,
    required String suggestedName,
    required String id,
    String? folder,
    bool unique = false,
  }) async {
    await bytes.drain<void>();
    throw const FileSystemException('sin lugar');
  }
}
