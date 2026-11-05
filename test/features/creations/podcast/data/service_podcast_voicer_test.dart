import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/creations/podcast/data/service_podcast_voicer.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_audio.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/narration/data/audio/speech_audio_renderer.dart';
import 'package:sinapsis/features/narration/data/audio/speech_wav.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../narration/data/audio/speech_audio_fakes.dart';

class _BrokenStore extends InMemoryFileStore {
  @override
  Future<String> saveStream({
    required Stream<List<int>> bytes,
    required String suggestedName,
    required String id,
    String? folder,
    bool unique = false,
  }) => throw const FileSystemException('sin lugar');
}

/// F47, paso 6b: la voz del podcast, en el teléfono y en la bóveda —cada
/// tramo con la voz de quien habla, con la pieza común—, o por qué no.
void main() {
  late Directory root;
  late FakeVoiceRenderer voices;
  late InMemoryFileStore files;

  setUp(() {
    root = Directory.systemTemp.createTempSync('voz');
    voices = FakeVoiceRenderer(prefix: 'offline:');
    files = InMemoryFileStore();
  });
  tearDown(() => root.deleteSync(recursive: true));

  ServicePodcastVoicer voicer({InMemoryFileStore? store}) =>
      ServicePodcastVoicer(
        renderer: SpeechAudioRenderer(
          voices: () => [voices, FakeVoiceRenderer(prefix: 'device:')],
          workRoot: () async => root,
          encoder: FakeEncoder(),
          assemble: (job) async => assembleSpeechWav(job),
        ),
        files: store ?? files,
      );

  const podcast = Podcast(
    title: 'El mar',
    format: PodcastFormat.conversation,
    length: PodcastLength.short,
    segments: [
      PodcastSegment(
        speaker: PodcastSpeaker.a,
        text: '¿Qué pasó?',
        kind: PodcastSegmentKind.link,
        pauseAfter: Duration(milliseconds: 550),
      ),
      PodcastSegment(
        speaker: PodcastSpeaker.b,
        text: 'El mar se abrió.',
        kind: PodcastSegmentKind.data,
      ),
    ],
    requestedWords: 450,
    targetWords: 450,
  );
  const cast = [
    PodcastVoiceChoice(speaker: PodcastSpeaker.a, voiceId: 'offline:dani'),
    PodcastVoiceChoice(speaker: PodcastSpeaker.b),
  ];

  test('genera cada tramo con la voz de quien habla, lo guarda en la carpeta '
      'de audio de la creación y suelta el trabajo', () async {
    final progress = <double>[];
    final voiced = await voicer().voice(
      creationId: 'c1',
      podcast: podcast,
      cast: cast,
      languageCode: 'es',
      onProgress: progress.add,
    );

    expect(voices.said, [('offline:dani', '¿Qué pasó?')]);
    final audio = voiced.audio!;
    expect(audio.reference, startsWith('originales/c1/audio/podcast-'));
    expect(audio.reference, endsWith('.m4a'));
    expect(audio.mimeType, 'audio/mp4');
    expect(files.paths, [audio.reference]);
    expect(
      audio.fingerprint,
      podcastAudioFingerprint(podcastSpeechPieces(podcast, cast, 'es')),
    );
    expect(audio.starts, [
      Duration.zero,
      const Duration(milliseconds: 480 + 550),
    ]);
    expect(voiced.audioIssue, isNull);
    expect(voiced.segments, podcast.segments);
    expect(Directory(p.join(root.path, 'podcast-c1')).existsSync(), isFalse);
    expect(progress.last, 1);
    expect(podcastAudioStateOf(voiced, cast, 'es'), PodcastAudioState.ready);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('una voz que falta deja el guion y dice cuál; lo hecho queda para el '
      'próximo intento', () async {
    voices.missing.add('offline:dani');
    final voiced = await voicer().voice(
      creationId: 'c1',
      podcast: podcast,
      cast: cast,
      languageCode: 'es',
    );
    expect(voiced.audio, isNull);
    expect(
      voiced.audioIssue,
      const PodcastAudioIssue(
        PodcastAudioProblem.voiceMissing,
        voiceId: 'offline:dani',
      ),
    );
    expect(files.paths, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('un motor que falla, y un disco que no guarda, también', () async {
    voices.failOn = 'offline:dani';
    expect(
      (await voicer().voice(
        creationId: 'c1',
        podcast: podcast,
        cast: cast,
        languageCode: 'es',
      )).audioIssue!.problem,
      PodcastAudioProblem.engine,
    );
    voices.failOn = null;
    expect(
      (await voicer(store: _BrokenStore()).voice(
        creationId: 'c1',
        podcast: podcast,
        cast: cast,
        languageCode: 'es',
      )).audioIssue!.problem,
      PodcastAudioProblem.file,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('cancelada, no guarda nada y lo dice', () async {
    final signal = CancellationSignal()..cancel();
    await expectLater(
      voicer().voice(
        creationId: 'c1',
        podcast: podcast,
        cast: cast,
        languageCode: 'es',
        cancellation: signal,
      ),
      throwsA(isA<ProcessingCancelledException>()),
    );
    expect(files.paths, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
