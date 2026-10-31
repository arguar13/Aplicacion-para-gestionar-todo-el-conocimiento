import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_queue.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_generator.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

import '../creations_harness.dart';
import '../mind_map/support/fake_structured_writer.dart';

/// F47, paso 6 (decisión E): el podcast es una creación más de «Lo creado».
/// Por la cola de verdad, sobre la base de verdad y con una IA de mentira: se
/// pide, se escribe con el servicio en primer plano de siempre, queda listo
/// con su guion y sus fuentes —y lo que se cortó al cerrarse la app se
/// retoma—.
void main() {
  late CreationsHarness h;
  late String exodo;
  late FakeStructuredWriter writer;
  late _Keeper keeper;

  const ready = LanguageModelReady(provider: AiProvider.gemini);
  const text =
      'Moisés guía al pueblo fuera de Egipto. El mar se abre ante ellos y el '
      'pueblo cruza en seco. Después de mucho caminar llegan al monte Sinaí.';

  /// Un guion de unas [words] palabras, de dos voces, con su cita.
  String script(int words) => jsonEncode({
    'title': 'El mar abierto',
    'segments': [
      for (var i = 0; i < (words / 12).round(); i++)
        {
          'speaker': i.isEven ? 'A' : 'B',
          'kind': 'data',
          'text': 'Cuenta que el mar se abre y el pueblo lo cruza tranquilo.',
          'quotes': [
            {'source': 'Éxodo', 'quote': 'El mar se abre ante ellos'},
          ],
        },
    ],
  });

  CreationQueue newQueue() => CreationQueue(
    repository: () => h.creations,
    scopes: () => h.scopes,
    material: () => h.material,
    generators: () => {StudyCreationKind.podcast: const PodcastGenerator()},
    personWriter: () => writer,
    backgroundWriter: () => writer,
    readiness: () =>
        ({bool background = false}) async => ready,
    modelName: () => 'Gemma',
    keeper: () => keeper,
  );

  setUp(() async {
    h = await CreationsHarness.create();
    exodo = await h.processedDoc('exodo', title: 'Éxodo', text: text);
    // El material tiene unas 30 palabras: da para unas 44 de podcast.
    writer = FakeStructuredWriter((_, _) => script(48));
    keeper = _Keeper();
  });
  tearDown(() => h.close());

  Future<StudyCreation> stored(String id) async =>
      (await h.creations.find(id)).getRight().toNullable()!;

  Future<StudyCreation> settled(String id) async {
    for (var i = 0; i < 400; i++) {
      final creation = await stored(id);
      if (!creation.status.isPending) return creation;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('$id no terminó');
  }

  CreationRequest request() => CreationRequest(
    kind: StudyCreationKind.podcast,
    scope: CreationScope.document(exodo),
    sourceIds: [exodo],
    options: {
      'format': PodcastFormat.conversation.storageKey,
      'length': PodcastLength.short.storageKey,
      'voices': PodcastCast.toOptions(const [
        PodcastVoiceChoice(
          speaker: PodcastSpeaker.a,
          voiceId: 'device:es-AR:a',
        ),
        PodcastVoiceChoice(
          speaker: PodcastSpeaker.b,
          voiceId: 'device:es-AR:b',
        ),
      ]),
    },
  );

  test('se pide, se escribe con el servicio de siempre y queda en «Lo creado» '
      'con su guion, sus fuentes y sus voces', () async {
    final queue = newQueue();
    addTearDown(queue.dispose);
    writer.hold = Completer<void>();

    final created = (await queue.create(request())).getRight().toNullable()!;
    expect(created.status, CreationStatus.queued);
    for (var i = 0; i < 200 && writer.calls.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final generating = await stored(created.id);
    expect(generating.status, CreationStatus.generating);
    expect(generating.modelName, 'Gemma');
    // Mientras escribe, el servicio en primer plano de F21.
    expect(keeper.busy, isTrue);
    // Lo que se le dio a leer: el documento, bajo su título.
    expect(writer.calls.single.material, contains('## Éxodo'));

    writer.hold!.complete();
    final done = await settled(created.id);
    expect(done.status, CreationStatus.ready);
    expect(done.title, 'El mar abierto');
    expect(done.sourceIds, [exodo]);
    expect(keeper.busy, isFalse);
    final podcast = PodcastJson.decode(done.decodedContent)!;
    expect(podcast.speakers, [PodcastSpeaker.a, PodcastSpeaker.b]);
    expect(podcast.segments.first.citations.single.documentId, exodo);
    // Las voces quedan como se eligieron, para el audio.
    expect(PodcastCast.of(done.options, podcast.format).map((c) => c.voiceId), [
      'device:es-AR:a',
      'device:es-AR:b',
    ]);
  });

  test(
    'lo que quedó a medias al cerrarse la app se retoma al abrirla',
    () async {
      // Una sesión anterior lo empezó y la app se cerró a mitad.
      final created = (await h.creations.create(
        request(),
      )).getRight().toNullable()!;
      await h.creations.markGenerating(created.id, modelName: 'Gemma');
      await h.creations.reportProgress(
        created.id,
        progress: 0.5,
        step: CreationStep.writing,
      );

      final queue = newQueue();
      addTearDown(queue.dispose);
      await queue.resume();
      final done = await settled(created.id);

      expect(done.status, CreationStatus.ready);
      expect(writer.calls, isNotEmpty);
      expect(PodcastJson.decode(done.decodedContent), isA<Podcast>());
    },
  );

  test('un guion que no se sostiene, ni corregido, queda fallido con '
      '«Reintentar»', () async {
    writer = FakeStructuredWriter(
      (_, _) => jsonEncode({
        'segments': [
          {'speaker': 'A', 'text': 'Algo inventado de punta a punta.'},
          {'speaker': 'B', 'text': 'Y otra cosa que no está.'},
        ],
      }),
    );
    final queue = newQueue();
    addTearDown(queue.dispose);

    final created = (await queue.create(request())).getRight().toNullable()!;
    final done = await settled(created.id);

    expect(done.status, CreationStatus.failed);
    expect(done.failure, CreationFailure.unreadableReply);
    expect(done.failureDetail, contains('No quedó ningún tramo'));
  });
}

/// El servicio en primer plano, de mentira: anota lo que se le avisa.
class _Keeper implements LongWorkKeeper {
  final events = <String>[];

  /// Si lo último que se le avisó es que hay trabajo.
  bool get busy => events.isNotEmpty && events.last != 'idle';

  @override
  void working({
    required int done,
    required int total,
    LongWorkKind kind = LongWorkKind.dataSync,
    String? detail,
  }) => events.add('working $done/$total');

  @override
  void idle() => events.add('idle');
}
