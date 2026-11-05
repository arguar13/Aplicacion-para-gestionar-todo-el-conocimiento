import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_audio.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_generator.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_progress.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../../mind_map/support/fake_structured_writer.dart';

/// Lo hecho, en memoria: lo que la cola guarda con los archivos de la
/// creación.
class _Memory implements CreationCheckpoint {
  String? value;
  final saved = <String>[];

  @override
  Future<String?> read() async => value;

  @override
  Future<void> save(String json) async {
    saved.add(json);
    value = json;
  }
}

/// Quien da voz, de mentira: anota lo que le piden y devuelve el audio —o
/// por qué no—.
class _Voicer implements PodcastVoicer {
  final calls =
      <
        ({
          String creationId,
          Podcast podcast,
          List<PodcastVoiceChoice> cast,
          String languageCode,
        })
      >[];
  PodcastAudioIssue? issue;
  bool cancel = false;

  static const audio = PodcastAudio(
    reference: 'originales/c-1/audio/podcast.m4a',
    mimeType: 'audio/mp4',
    fingerprint: 'huella',
    duration: Duration(minutes: 3),
    starts: [],
  );

  @override
  Future<Podcast> voice({
    required String creationId,
    required Podcast podcast,
    required List<PodcastVoiceChoice> cast,
    required String languageCode,
    CancellationSignal? cancellation,
    void Function(double progress)? onProgress,
  }) async {
    calls.add((
      creationId: creationId,
      podcast: podcast,
      cast: cast,
      languageCode: languageCode,
    ));
    onProgress?.call(0.5);
    if (cancel) throw const ProcessingCancelledException();
    onProgress?.call(1);
    final issue = this.issue;
    return issue == null
        ? podcast.withAudio(audio)
        : podcast.withAudioIssue(issue);
  }
}

/// F47, paso 6b: el guion del podcast se retoma por vuelta, y la voz es una
/// etapa más de la misma creación —que se termina sin la IA si la app se
/// cerró mientras se generaba—.
void main() {
  const daniela = 'offline:vits-piper-es_AR-daniela-high#0';

  StudyCreation creation({String? title}) => StudyCreation(
    id: 'c-1',
    kind: StudyCreationKind.podcast,
    scope: const CreationScope.document('p-exodo'),
    languageCode: 'es',
    status: CreationStatus.generating,
    createdAt: DateTime(2026, 10, 30),
    updatedAt: DateTime(2026, 10, 30),
    title: title,
    sourceIds: const ['p-exodo'],
    options: {
      'format': PodcastFormat.conversation.storageKey,
      'length': PodcastLength.short.storageKey,
      'voices': PodcastCast.toOptions(const [
        PodcastVoiceChoice(speaker: PodcastSpeaker.a, voiceId: daniela),
        PodcastVoiceChoice(speaker: PodcastSpeaker.b),
      ]),
    },
  );

  CreationJob job(_Memory memory, {String? title, CancellationSignal? on}) =>
      CreationJob(
        creation: creation(title: title),
        cancellation: on ?? CancellationSignal(),
        checkpoint: memory,
      );

  const sentence = 'El mar se abre ante ellos y el pueblo cruza en seco.';

  CreationMaterial material({String extra = ''}) {
    final text = '${List.filled(100, sentence).join(' ')}$extra';
    return CreationMaterial(
      mode: CreationMaterialMode.fullText,
      text: '## Éxodo\n\n$text',
      sources: [
        CreationMaterialSource(
          documentId: 'p-exodo',
          title: 'Éxodo',
          chars: text.length,
        ),
      ],
      sourceStarts: const [0],
    );
  }

  String script(int words, {String title = 'El mar'}) => jsonEncode({
    'title': title,
    'segments': [
      for (var i = 0; i < (words / 12).round(); i++)
        {
          'speaker': i.isEven ? 'A' : 'B',
          'kind': 'data',
          'text': 'Cuenta que el mar se abre y el pueblo lo cruza tranquilo.',
          'quotes': [
            {'source': 'Éxodo', 'quote': 'el pueblo cruza en seco'},
          ],
        },
    ],
  });

  /// Con Gemma (2.048 tokens), un Corto va en dos vueltas.
  FakeStructuredWriter gemma({int? failOn}) => FakeStructuredWriter((_, i) {
    if (i == failOn) throw StateError('la app se cerró');
    return script(225, title: 'Vuelta $i');
  }, contextTokens: 2048);

  group('el retome por vuelta', () {
    test('si se corta en la segunda vuelta, el próximo intento sigue ahí, sin '
        'volver a pedir la primera', () async {
      final memory = _Memory();
      await expectLater(
        const PodcastGenerator().generate(
          job(memory),
          material(),
          gemma(failOn: 1),
          (_, _) {},
        ),
        throwsStateError,
      );
      final saved = PodcastProgress.decode(memory.value);
      expect(saved, isA<PodcastScriptProgress>());
      expect((saved! as PodcastScriptProgress).rounds, hasLength(1));

      final writer = gemma();
      final steps = <double>[];
      final output = await const PodcastGenerator().generate(
        job(memory),
        material(),
        writer,
        (done, _) => steps.add(done),
      );
      expect(writer.calls, hasLength(1));
      final instruction = writer.calls.single.instruction;
      expect(instruction, contains('la parte 2 de 2'));
      expect(instruction, contains('Así terminó la parte anterior'));
      final podcast = PodcastJson.decode(output.content)!;
      // El título es el de la primera vuelta, la que se guardó.
      expect(podcast.title, 'Vuelta 0');
      expect(podcast.segments, hasLength(2 * (225 / 12).round()));
      // Entre la vuelta guardada y la nueva, la pausa del cambio de voz.
      expect(
        podcast.segments[(225 / 12).round() - 1].pauseAfter,
        isNot(Duration.zero),
      );
      expect(steps.first, greaterThanOrEqualTo(0.5));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
      'si cambió el material, el pedido o el reparto, empieza de cero',
      () async {
        final memory = _Memory();
        await expectLater(
          const PodcastGenerator().generate(
            job(memory),
            material(),
            gemma(failOn: 1),
            (_, _) {},
          ),
          throwsStateError,
        );
        final writer = gemma();
        await const PodcastGenerator().generate(
          job(memory),
          material(extra: ' Una oración nueva al final.'),
          writer,
          (_, _) {},
        );
        expect(writer.calls, hasLength(2));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('guarda cada vuelta menos la última; sin voz, nada más', () async {
      final memory = _Memory();
      await const PodcastGenerator().generate(
        job(memory),
        material(),
        gemma(),
        (_, _) {},
      );
      expect(memory.saved, hasLength(1));
      expect(
        PodcastProgress.decode(memory.saved.single),
        isA<PodcastScriptProgress>(),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('la voz, como una etapa más', () {
    test('con el guion terminado, lo guarda entero y le da voz con las voces '
        'elegidas; el avance pasa por «Generando la voz»', () async {
      final memory = _Memory();
      final voicer = _Voicer();
      final steps = <(double, CreationStep)>[];
      final output = await PodcastGenerator(voicer: voicer).generate(
        job(memory),
        material(),
        gemma(),
        (done, step) => steps.add((done, step)),
      );

      expect(
        PodcastProgress.decode(memory.saved.last),
        isA<PodcastVoiceProgress>(),
      );
      final call = voicer.calls.single;
      expect(call.creationId, 'c-1');
      expect(call.languageCode, 'es');
      expect(call.cast.map((c) => c.voiceId), [daniela, null]);
      expect(call.podcast.audio, isNull);
      final podcast = PodcastJson.decode(output.content)!;
      expect(podcast.audio, _Voicer.audio);
      expect(output.title, 'Vuelta 0');

      final script = steps.where((s) => s.$2 != CreationStep.voicing);
      final voice = steps.where((s) => s.$2 == CreationStep.voicing);
      expect(
        script.where((s) => s.$2 != CreationStep.finishing).map((s) => s.$1),
        everyElement(lessThanOrEqualTo(PodcastGenerator.scriptShare)),
      );
      expect(voice.map((s) => s.$1), [
        PodcastGenerator.scriptShare,
        PodcastGenerator.scriptShare + (1 - PodcastGenerator.scriptShare) / 2,
        1,
      ]);
      expect(steps.last, (1.0, CreationStep.finishing));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('si la voz no se pudo, el guion queda, con por qué', () async {
      final voicer = _Voicer()
        ..issue = const PodcastAudioIssue(
          PodcastAudioProblem.voiceMissing,
          voiceId: daniela,
        );
      final output = await PodcastGenerator(
        voicer: voicer,
      ).generate(job(_Memory()), material(), gemma(), (_, _) {});
      final podcast = PodcastJson.decode(output.content)!;
      expect(podcast.segments, isNotEmpty);
      expect(podcast.audio, isNull);
      expect(podcast.audioIssue!.voiceId, daniela);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('cancelada mientras se genera la voz, no sigue', () async {
      final voicer = _Voicer()..cancel = true;
      await expectLater(
        PodcastGenerator(
          voicer: voicer,
        ).generate(job(_Memory()), material(), gemma(), (_, _) {}),
        throwsA(isA<ProcessingCancelledException>()),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('terminar sin la IA', () {
    const podcast = Podcast(
      title: 'El mar',
      format: PodcastFormat.conversation,
      length: PodcastLength.short,
      segments: [
        PodcastSegment(
          speaker: PodcastSpeaker.a,
          text: 'Hola.',
          kind: PodcastSegmentKind.link,
        ),
      ],
      requestedWords: 450,
      targetWords: 450,
    );

    test(
      'sin quien dé voz, o sin el guion guardado, se genera como siempre',
      () async {
        final memory = _Memory()
          ..value = const PodcastVoiceProgress(podcast).encode();
        expect(
          await const PodcastGenerator().finisherWithoutModel(job(memory)),
          isNull,
        );
        expect(
          await PodcastGenerator(
            voicer: _Voicer(),
          ).finisherWithoutModel(job(_Memory())),
          isNull,
        );
        final rounds = _Memory()
          ..value = const PodcastScriptProgress(
            key: 'k',
            title: '',
            rounds: [],
          ).encode();
        expect(
          await PodcastGenerator(
            voicer: _Voicer(),
          ).finisherWithoutModel(job(rounds)),
          isNull,
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('con el guion guardado, le da voz desde cero, sin la IA; el título, '
        'el nuevo o —si lo pidió la persona— el que tiene', () async {
      final voicer = _Voicer();
      final generator = PodcastGenerator(voicer: voicer);

      final resumed = _Memory()
        ..value = const PodcastVoiceProgress(podcast).encode();
      final steps = <double>[];
      final finish = (await generator.finisherWithoutModel(
        job(resumed, title: 'El de antes'),
      ))!;
      final output = await finish((done, _) => steps.add(done));
      expect(output.title, 'El mar');
      expect(PodcastJson.decode(output.content)!.audio, _Voicer.audio);
      expect(steps.first, 0);
      expect(voicer.calls.single.podcast, podcast);

      final asked = _Memory()
        ..value = const PodcastVoiceProgress(podcast, keepTitle: true).encode();
      final renamed = await (await generator.finisherWithoutModel(
        job(asked, title: 'Mi podcast'),
      ))!((_, _) {});
      expect(renamed.title, 'Mi podcast');
      final untitled = await (await generator.finisherWithoutModel(
        job(asked),
      ))!((_, _) {});
      expect(untitled.title, 'El mar');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
