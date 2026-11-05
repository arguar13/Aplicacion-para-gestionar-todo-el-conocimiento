import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_audio.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_progress.dart';

/// F47, paso 6b: el audio del podcast como dato —sus tramos con su voz y su
/// pausa, su huella, lo guardado y lo hecho mientras se genera—.
void main() {
  const a = PodcastSegment(
    speaker: PodcastSpeaker.a,
    text: '¿Qué pasó con el mar?',
    kind: PodcastSegmentKind.link,
    pauseAfter: Duration(milliseconds: 550),
  );
  const b = PodcastSegment(
    speaker: PodcastSpeaker.b,
    text: 'El mar se abrió y el pueblo cruzó en seco.',
    kind: PodcastSegmentKind.data,
    citations: [
      PodcastCitation(quote: 'El mar se abre ante ellos', documentId: 'ex'),
    ],
  );
  const podcast = Podcast(
    title: 'El mar abierto',
    format: PodcastFormat.conversation,
    length: PodcastLength.short,
    segments: [a, b],
    requestedWords: 450,
    targetWords: 450,
  );
  const daniela = 'offline:vits-piper-es_AR-daniela-high#0';
  const cast = [
    PodcastVoiceChoice(speaker: PodcastSpeaker.a, voiceId: daniela),
    PodcastVoiceChoice(speaker: PodcastSpeaker.b),
  ];
  const audio = PodcastAudio(
    reference: 'originales/c1/audio/podcast-ab.m4a',
    mimeType: 'audio/mp4',
    fingerprint: 'huella',
    duration: Duration(milliseconds: 4321),
    starts: [Duration.zero, Duration(milliseconds: 2100)],
  );

  test('cada tramo con la voz de quien habla y su pausa; la del teléfono por '
      'defecto es la del idioma', () {
    final pieces = podcastSpeechPieces(podcast, cast, 'es');
    expect([for (final p in pieces) p.voiceId], [daniela, 'device:es:']);
    expect([for (final p in pieces) p.text], [a.text, b.text]);
    expect(pieces.first.pauseAfter, const Duration(milliseconds: 550));
    expect(podcastSpeechVoiceId(null, 'en'), 'device:en:');
    expect(podcastSpeechVoiceId('device:es-AR:x', 'en'), 'device:es-AR:x');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('la huella cambia con un texto, una voz o una pausa, y no con lo '
      'demás', () {
    String print(Podcast p, List<PodcastVoiceChoice> c) =>
        podcastAudioFingerprint(podcastSpeechPieces(p, c, 'es'));
    final base = print(podcast, cast);
    expect(print(podcast, cast), base);
    expect(base, hasLength(32));

    Podcast withA(PodcastSegment segment) => Podcast(
      title: 'Otro título',
      format: podcast.format,
      length: podcast.length,
      segments: [segment, b],
      requestedWords: 1,
      targetWords: 1,
    );
    // El título y las cifras no se oyen.
    expect(print(withA(a), cast), base);
    expect(
      print(
        withA(
          const PodcastSegment(
            speaker: PodcastSpeaker.a,
            text: '¿Qué pasó con el río?',
            kind: PodcastSegmentKind.link,
            pauseAfter: Duration(milliseconds: 550),
          ),
        ),
        cast,
      ),
      isNot(base),
    );
    expect(
      print(
        withA(
          const PodcastSegment(
            speaker: PodcastSpeaker.a,
            text: '¿Qué pasó con el mar?',
            kind: PodcastSegmentKind.link,
            pauseAfter: Duration(milliseconds: 1200),
          ),
        ),
        cast,
      ),
      isNot(base),
    );
    expect(
      print(podcast, const [
        PodcastVoiceChoice(speaker: PodcastSpeaker.a),
        PodcastVoiceChoice(speaker: PodcastSpeaker.b),
      ]),
      isNot(base),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('el estado del audio: listo si es de este guion con estas voces; de '
      'otra versión, fallido o ninguno', () {
    final fingerprint = podcastAudioFingerprint(
      podcastSpeechPieces(podcast, cast, 'es'),
    );
    final good = PodcastAudio(
      reference: audio.reference,
      mimeType: audio.mimeType,
      fingerprint: fingerprint,
      duration: audio.duration,
      starts: audio.starts,
    );
    expect(
      podcastAudioStateOf(podcast.withAudio(good), cast, 'es'),
      PodcastAudioState.ready,
    );
    expect(
      podcastAudioStateOf(podcast.withAudio(audio), cast, 'es'),
      PodcastAudioState.stale,
    );
    // Con un comienzo de menos no se puede seguir la transcripción.
    final short = PodcastAudio(
      reference: audio.reference,
      mimeType: audio.mimeType,
      fingerprint: fingerprint,
      duration: audio.duration,
      starts: const [Duration.zero],
    );
    expect(
      podcastAudioStateOf(podcast.withAudio(short), cast, 'es'),
      PodcastAudioState.stale,
    );
    expect(
      podcastAudioStateOf(
        podcast.withAudioIssue(
          const PodcastAudioIssue(PodcastAudioProblem.engine),
        ),
        cast,
        'es',
      ),
      PodcastAudioState.failed,
    );
    expect(podcastAudioStateOf(podcast, cast, 'es'), PodcastAudioState.none);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('el audio y por qué no hay se guardan y se leen; el archivo, con '
      '`audio_ref`', () {
    final voiced = podcast.withAudio(audio);
    final json = PodcastJson.encode(voiced);
    expect((json['audio']! as Map)['audio_ref'], audio.reference);
    expect(PodcastJson.decode(jsonEncode(json)), voiced);

    final failed = podcast.withAudioIssue(
      const PodcastAudioIssue(PodcastAudioProblem.voiceMissing, voiceId: 'x'),
    );
    expect(PodcastJson.decode(PodcastJson.encodeString(failed)), failed);
    expect(failed.audio, isNull);
    // Dar voz de nuevo saca las dos cosas.
    expect(voiced.withoutAudio(), podcast);
    expect(failed.withAudio(audio).audioIssue, isNull);

    // Un audio al que le falta algo no se puede escuchar: no cuenta.
    for (final broken in [
      {
        'audio_ref': '',
        'fingerprint': 'h',
        'durationMs': 1,
        'startsMs': <Object?>[],
      },
      {'audio_ref': 'r', 'durationMs': 1, 'startsMs': <Object?>[]},
      {'audio_ref': 'r', 'fingerprint': 'h', 'startsMs': <Object?>[]},
      {
        'audio_ref': 'r',
        'fingerprint': 'h',
        'durationMs': 1,
        'startsMs': ['x'],
      },
    ]) {
      final raw = {...PodcastJson.encode(podcast), 'audio': broken};
      expect(PodcastJson.decode(raw)!.audio, isNull, reason: '$broken');
    }
    final unknown = {
      ...PodcastJson.encode(podcast),
      'audioIssue': {'reason': 'otra'},
    };
    expect(PodcastJson.decode(unknown)!.audioIssue, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  group('lo hecho mientras se genera', () {
    test('las vueltas escritas, con su clave, su título y lo quitado', () {
      const done = PodcastScriptProgress(
        key: 'k',
        title: 'Título',
        rounds: [
          PodcastRoundDone(
            segments: [a],
            discarded: [
              PodcastDiscard(
                reason: PodcastDiscardReason.noCitation,
                text: 'Sin cita.',
              ),
            ],
          ),
          PodcastRoundDone(segments: [b]),
        ],
      );
      final read = PodcastProgress.decode(done.encode())!;
      expect(read, isA<PodcastScriptProgress>());
      read as PodcastScriptProgress;
      expect(read.key, 'k');
      expect(read.title, 'Título');
      expect(read.rounds.map((r) => r.segments), [
        [a],
        [b],
      ]);
      expect(read.rounds.first.discarded.single.text, 'Sin cita.');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('el guion listo para la voz, y si conserva el título', () {
      final read = PodcastProgress.decode(
        const PodcastVoiceProgress(podcast, keepTitle: true).encode(),
      )!;
      expect(read, isA<PodcastVoiceProgress>());
      expect((read as PodcastVoiceProgress).podcast, podcast);
      expect(read.keepTitle, isTrue);
      expect(
        (PodcastProgress.decode(const PodcastVoiceProgress(podcast).encode())!
                as PodcastVoiceProgress)
            .keepTitle,
        isFalse,
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('lo que no se entiende, de otra versión o con una vuelta vacía, '
        'cuenta como que no hay', () {
      for (final raw in [
        null,
        'no es json',
        '[]',
        '{"v":2,"stage":"voice"}',
        '{"v":1,"stage":"otra"}',
        '{"v":1,"stage":"script","rounds":[]}',
        '{"v":1,"stage":"script","key":"k","rounds":[{"segments":[]}]}',
        '{"v":1,"stage":"script","key":"k","rounds":[3]}',
        '{"v":1,"stage":"voice","podcast":{}}',
      ]) {
        expect(PodcastProgress.decode(raw), isNull, reason: raw);
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('la clave del guion cambia con el pedido, el material y el reparto '
        'en vueltas', () {
      String key({
        String format = 'conversation',
        String length = 'short',
        String? focus,
        String language = 'es',
        int target = 450,
        int rounds = 2,
        int perRound = 225,
        List<String> material = const ['texto'],
      }) => podcastScriptKey(
        format: format,
        length: length,
        focus: focus,
        languageCode: language,
        targetWords: target,
        rounds: rounds,
        perRound: perRound,
        material: material,
      );
      final base = key();
      expect(key(), base);
      for (final other in [
        key(format: 'brief'),
        key(length: 'long'),
        key(focus: 'Moisés'),
        key(language: 'en'),
        key(target: 400),
        key(rounds: 3),
        key(perRound: 150),
        key(material: const ['texto cambiado']),
      ]) {
        expect(other, isNot(base));
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
