import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/creation_queue.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

import '../../creations_harness.dart';

/// Quien escribe, de mentira: solo dice quién es y su ventana.
class _Writer implements StructuredWriter {
  _Writer(this.name);

  final String name;

  @override
  int get contextTokens => 100000;

  @override
  Future<T> writeStructured<T>(StructuredRequest<T> request) =>
      throw UnimplementedError('el generador de mentira no lo usa');
}

/// Un generador de mentira: anota con qué lo llamaron y devuelve un mapa con
/// lo que leyó; con [hold], espera a que se complete o a que lo cancelen.
class _Generator extends CreationGenerator {
  _Generator(this.kind);

  @override
  final StudyCreationKind kind;

  final calls =
      <({CreationJob job, CreationMaterial material, String writer})>[];
  Completer<void>? hold;
  Exception? error;

  @override
  int maxOutputTokens(CreationJob job) => 500;

  @override
  Future<CreationOutput> generate(
    CreationJob job,
    CreationMaterial material,
    StructuredWriter writer,
    CreationProgressReport progress,
  ) async {
    calls.add((job: job, material: material, writer: (writer as _Writer).name));
    progress(0.5, CreationStep.writing);
    if (hold case final hold?) {
      await Future.any([hold.future, job.cancellation.whenCancelled]);
      if (job.cancellation.isCancelled) {
        throw const CreationCancelledException();
      }
    }
    if (error case final error?) throw error;
    return CreationOutput(
      title: 'Mapa de ${material.sources.first.title}',
      content: jsonEncode({'leido': material.chars, 'opciones': job.options}),
    );
  }
}

class _Keeper implements LongWorkKeeper {
  final events = <String>[];

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

void main() {
  late CreationsHarness h;
  late String exodo;
  late _Generator mindMap;
  late _Keeper keeper;
  late LanguageModelStatus personStatus;
  late LanguageModelStatus backgroundStatus;
  late List<String> analyzed;
  late List<Object> errors;
  late List<CreationQueue> queues;

  const ready = LanguageModelReady(provider: AiProvider.gemma);

  CreationQueue newQueue({Duration laterRetry = const Duration(minutes: 10)}) {
    final queue = CreationQueue(
      repository: () => h.creations,
      scopes: () => h.scopes,
      material: () => h.material,
      generators: () => {StudyCreationKind.mindMap: mindMap},
      personWriter: () => _Writer('persona'),
      backgroundWriter: () => _Writer('fondo'),
      readiness: () =>
          ({bool background = false}) async =>
              background ? backgroundStatus : personStatus,
      modelName: () => 'Gemma 3n',
      keeper: () => keeper,
      analyzeForStudy: analyzed.add,
      onError: (error, _) => errors.add(error),
      laterRetryDelay: laterRetry,
    );
    queues.add(queue);
    return queue;
  }

  setUp(() async {
    h = await CreationsHarness.create();
    exodo = await h.processedDoc('exodo', title: 'Éxodo', summary: [(0, 22)]);
    mindMap = _Generator(StudyCreationKind.mindMap);
    keeper = _Keeper();
    personStatus = ready;
    backgroundStatus = ready;
    analyzed = [];
    errors = [];
    queues = [];
  });
  tearDown(() async {
    for (final queue in queues) {
      queue.dispose();
    }
    await h.close();
  });

  CreationRequest request({
    StudyCreationKind kind = StudyCreationKind.mindMap,
    bool runNow = true,
    List<String>? sources,
  }) => CreationRequest(
    kind: kind,
    scope: CreationScope.document(exodo),
    sourceIds: sources ?? [exodo],
    options: const {'tema': 'Moisés'},
    runNow: runNow,
  );

  Future<StudyCreation> stored(String id) async =>
      (await h.creations.find(id)).getRight().toNullable()!;

  /// Espera a que [id] deje de estar pendiente.
  Future<StudyCreation> settled(String id) async {
    for (var i = 0; i < 200; i++) {
      final creation = await stored(id);
      if (!creation.status.isPending) return creation;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('$id sigue pendiente');
  }

  group('«Generar ahora»', () {
    test('la genera con el modelo de la persona y la deja lista, con lo que '
        'leyó y el modelo que la escribió', () async {
      final queue = newQueue();

      final created = (await queue.create(request())).getRight().toNullable()!;
      expect(created.status, CreationStatus.queued);
      final done = await settled(created.id);

      expect(done.status, CreationStatus.ready);
      expect(done.title, 'Mapa de Éxodo');
      expect(done.modelName, 'Gemma 3n');
      expect(done.sourceIds, [exodo]);
      final call = mindMap.calls.single;
      expect(call.writer, 'persona');
      expect(call.job.options, {'tema': 'Moisés'});
      expect(call.material.mode, CreationMaterialMode.fullText);
      expect(jsonDecode(done.content!), {
        'leido': call.material.chars,
        'opciones': {'tema': 'Moisés'},
      });
      // Mantuvo viva la app mientras generaba, y la soltó.
      expect(keeper.events.first, 'working 0/100');
      expect(keeper.events, contains('working 50/100'));
      expect(keeper.events.last, 'idle');
    });

    test(
      'si el modelo de la persona no puede, falla diciendo por qué',
      () async {
        personStatus = const LanguageModelNeedsDownload();
        final queue = newQueue();

        final created = (await queue.create(
          request(),
        )).getRight().toNullable()!;
        final done = await settled(created.id);

        expect(done.status, CreationStatus.failed);
        expect(done.failure, CreationFailure.modelUnavailable);
        expect(mindMap.calls, isEmpty);
      },
    );

    test('va antes que todo lo de «más tarde»', () async {
      final later = (await h.creations.create(
        request(runNow: false),
      )).getRight().toNullable()!;
      final now = (await h.creations.create(
        request(),
      )).getRight().toNullable()!;

      await newQueue().resume();
      await settled(later.id);

      expect(
        [for (final c in mindMap.calls) c.job.creation.id],
        [now.id, later.id],
      );
    });
  });

  test(
    '«ahora» no espera la cuota de fondo que traba lo de «más tarde»',
    () async {
      backgroundStatus = LanguageModelBackgroundCapReached(
        provider: AiProvider.gemini,
        cap: 50,
        resetsAt: DateTime(2026, 10, 29),
      );
      final later = (await h.creations.create(
        request(runNow: false),
      )).getRight().toNullable()!;
      final now = (await h.creations.create(
        request(),
      )).getRight().toNullable()!;

      await newQueue().resume();

      expect((await settled(now.id)).status, CreationStatus.ready);
      expect((await stored(later.id)).status, CreationStatus.queued);
    },
  );

  group('«Generar más tarde»', () {
    test('va con la cola de fondo', () async {
      final queue = newQueue();
      final created = (await queue.create(
        request(runNow: false),
      )).getRight().toNullable()!;

      expect((await settled(created.id)).status, CreationStatus.ready);
      expect(mindMap.calls.single.writer, 'fondo');
    });

    test(
      'sin cuota de fondo espera sin fallar, y sigue cuando vuelve',
      () async {
        backgroundStatus = LanguageModelBackgroundCapReached(
          provider: AiProvider.gemini,
          cap: 50,
          resetsAt: DateTime(2026, 10, 29),
        );
        final queue = newQueue(laterRetry: const Duration(milliseconds: 20));
        final created = (await queue.create(
          request(runNow: false),
        )).getRight().toNullable()!;

        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect((await stored(created.id)).status, CreationStatus.queued);
        expect(mindMap.calls, isEmpty);

        backgroundStatus = ready;
        expect((await settled(created.id)).status, CreationStatus.ready);
      },
    );
  });

  group('cerrar y volver a abrir la app', () {
    test('lo que quedó en la cola o a medias se retoma solo', () async {
      final queued = (await h.creations.create(
        request(runNow: false),
      )).getRight().toNullable()!;
      final halfway = (await h.creations.create(
        request(),
      )).getRight().toNullable()!;
      await h.creations.markGenerating(halfway.id, modelName: null);

      await newQueue().resume();

      expect((await settled(halfway.id)).status, CreationStatus.ready);
      expect((await settled(queued.id)).status, CreationStatus.ready);
    });

    test('lo que se cortó tres veces queda fallido por interrumpido', () async {
      final stuck = (await h.creations.create(
        request(),
      )).getRight().toNullable()!;
      for (var i = 0; i < CreationQueue.maxInterruptedAttempts; i++) {
        await h.creations.markGenerating(stuck.id, modelName: null);
      }

      await newQueue().resume();

      final done = await settled(stuck.id);
      expect(done.failure, CreationFailure.interrupted);
      expect(mindMap.calls, isEmpty);
    });

    test(
      'descartar la cola a mitad la deja «generándose», para retomarla',
      () async {
        mindMap.hold = Completer<void>();
        final first = newQueue();
        final created = (await first.create(
          request(),
        )).getRight().toNullable()!;
        await pumpEventQueue();
        expect(mindMap.calls, hasLength(1));

        first.dispose();
        await pumpEventQueue();
        expect((await stored(created.id)).status, CreationStatus.generating);

        mindMap.hold = null;
        await newQueue().resume();
        expect((await settled(created.id)).status, CreationStatus.ready);
      },
    );
  });

  group('cuando algo sale mal', () {
    test(
      'la IA no devolvió lo pedido: fallida con el motivo, y la cola sigue',
      () async {
        mindMap.error = const UnreadableStructuredReply('Falta «raiz».');
        final queue = newQueue();
        final bad = (await queue.create(request())).getRight().toNullable()!;
        final failed = await settled(bad.id);

        expect(failed.failure, CreationFailure.unreadableReply);
        expect(failed.failureDetail, 'Falta «raiz».');

        mindMap.error = null;
        final good = (await queue.create(request())).getRight().toNullable()!;
        expect((await settled(good.id)).status, CreationStatus.ready);
      },
    );

    test('cualquier otra falla queda anotada y se avisa', () async {
      mindMap.error = Exception('se rompió');
      final queue = newQueue();
      final created = (await queue.create(request())).getRight().toNullable()!;

      final failed = await settled(created.id);
      expect(failed.failure, CreationFailure.error);
      expect(failed.failureDetail, contains('se rompió'));
      expect(errors.single, isA<Exception>());
    });

    test('sin nada que leer: fallida por sin fuentes', () async {
      final queue = newQueue();
      final created = (await queue.create(
        request(sources: ['no-existe']),
      )).getRight().toNullable()!;

      expect((await settled(created.id)).failure, CreationFailure.noSources);
    });

    test('un tipo sin generador: fallida por sin soporte', () async {
      final queue = newQueue();
      final created = (await queue.create(
        request(kind: StudyCreationKind.presentation),
      )).getRight().toNullable()!;

      expect((await settled(created.id)).failure, CreationFailure.unsupported);
    });

    test('reintentar una fallida la genera de nuevo', () async {
      mindMap.error = Exception('una vez');
      final queue = newQueue();
      final created = (await queue.create(request())).getRight().toNullable()!;
      await settled(created.id);

      mindMap.error = null;
      await queue.retry(created.id);

      expect((await settled(created.id)).status, CreationStatus.ready);
    });
  });

  group('cancelar, borrar y volver a generar', () {
    test('cancelar lo que se genera lo corta: cancelada', () async {
      mindMap.hold = Completer<void>();
      final queue = newQueue();
      final created = (await queue.create(request())).getRight().toNullable()!;
      await pumpEventQueue();
      expect(queue.isRunning(created.id), isTrue);

      await queue.cancel(created.id);

      expect((await settled(created.id)).failure, CreationFailure.cancelled);
      expect(queue.isRunning(created.id), isFalse);
    });

    test('cancelar lo que espera lo saca de la cola', () async {
      mindMap.hold = Completer<void>();
      final queue = newQueue();
      final first = (await queue.create(request())).getRight().toNullable()!;
      final waiting = (await queue.create(request())).getRight().toNullable()!;

      await queue.cancel(waiting.id);
      expect((await stored(waiting.id)).failure, CreationFailure.cancelled);

      mindMap.hold!.complete();
      await settled(first.id);
      expect(mindMap.calls, hasLength(1));
    });

    test('mandarla a la papelera mientras se genera la corta', () async {
      mindMap.hold = Completer<void>();
      final queue = newQueue();
      final created = (await queue.create(request())).getRight().toNullable()!;
      await pumpEventQueue();

      await h.creations.trash(created.id);

      final done = await settled(created.id);
      expect(done.isTrashed, isTrue);
      expect(done.failure, CreationFailure.cancelled);
    });

    test('volver a generar con otras opciones las usa, y conserva la '
        'creación', () async {
      final queue = newQueue();
      final created = (await queue.create(request())).getRight().toNullable()!;
      await settled(created.id);

      await queue.regenerate(created.id, options: const {'tema': 'El mar'});

      final again = await settled(created.id);
      expect(again.id, created.id);
      expect(mindMap.calls.last.job.options, {'tema': 'El mar'});
      expect(
        again.decodedContent,
        containsPair('opciones', {'tema': 'El mar'}),
      );
    });
  });

  group('las de extraer', () {
    test(
      'quedan listas sin la IA, y piden el análisis de lo que les falta',
      () async {
        final genesis = await h.processedDoc('genesis', title: 'Génesis');
        final queue = newQueue();

        final summary = (await queue.create(
          CreationRequest(
            kind: StudyCreationKind.summary,
            scope: const CreationScope.allProcessed(),
            sourceIds: [exodo, genesis],
          ),
        )).getRight().toNullable()!;

        expect(summary.status, CreationStatus.ready);
        expect(analyzed, [genesis], reason: 'el Éxodo ya tiene su resumen');
        expect(mindMap.calls, isEmpty);

        analyzed.clear();
        await queue.create(
          CreationRequest(
            kind: StudyCreationKind.synthesis,
            scope: const CreationScope.allProcessed(),
            sourceIds: [exodo, genesis],
          ),
        );
        expect(analyzed, [exodo, genesis]);
      },
    );
  });
}
