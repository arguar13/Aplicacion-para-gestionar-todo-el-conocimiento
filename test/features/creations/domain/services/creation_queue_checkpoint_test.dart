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

import '../../../../support/in_memory_file_store.dart';
import '../../creations_harness.dart';

class _Writer implements StructuredWriter {
  @override
  int get contextTokens => 100000;

  @override
  Future<T> writeStructured<T>(StructuredRequest<T> request) =>
      throw UnimplementedError();
}

/// Un generador de mentira que guarda su avance —«mitad»— y, si lo encuentra
/// como `listo:<algo>`, termina sin la IA con eso.
class _Generator extends CreationGenerator {
  final seen = <String?>[];
  int generated = 0;
  int finished = 0;
  Exception? error;

  @override
  StudyCreationKind get kind => StudyCreationKind.podcast;

  @override
  int maxOutputTokens(CreationJob job) => 500;

  @override
  Future<CreationFinisher?> finisherWithoutModel(CreationJob job) async {
    final saved = await job.checkpoint.read();
    if (saved == null || !saved.startsWith('listo:')) return null;
    return (CreationProgressReport progress) async {
      finished++;
      progress(0.5, CreationStep.voicing);
      return CreationOutput(title: 'Sin IA', content: saved.substring(6));
    };
  }

  @override
  Future<CreationOutput> generate(
    CreationJob job,
    CreationMaterial material,
    StructuredWriter writer,
    CreationProgressReport progress,
  ) async {
    seen.add(await job.checkpoint.read());
    generated++;
    await job.checkpoint.save('mitad');
    if (error case final error?) throw error;
    return const CreationOutput(title: 'Con IA', content: '{}');
  }
}

/// F47, paso 6b: la cola de «Lo creado» con lo hecho guardado —«Reintentar»
/// sigue desde ahí, «Volver a generar» empieza de cero— y lo que se termina
/// sin la IA, que no la espera ni arma el material.
void main() {
  late CreationsHarness h;
  late String exodo;
  late _Generator generator;
  late LanguageModelStatus status;
  late List<CreationQueue> queues;

  const ready = LanguageModelReady(provider: AiProvider.gemma);
  const unavailable = LanguageModelNeedsDownload();

  CreationQueue newQueue() {
    final queue = CreationQueue(
      repository: () => h.creations,
      scopes: () => h.scopes,
      material: () => h.material,
      generators: () => {StudyCreationKind.podcast: generator},
      personWriter: _Writer.new,
      backgroundWriter: _Writer.new,
      readiness: () =>
          ({bool background = false}) async => status,
      modelName: () => 'Gemma',
    );
    queues.add(queue);
    return queue;
  }

  setUp(() async {
    h = await CreationsHarness.create(files: InMemoryFileStore());
    exodo = await h.processedDoc('exodo', title: 'Éxodo');
    generator = _Generator();
    status = ready;
    queues = [];
  });
  tearDown(() async {
    for (final queue in queues) {
      queue.dispose();
    }
    await h.close();
  });

  Future<StudyCreation> settled(String id) async {
    for (var i = 0; i < 400; i++) {
      final c = (await h.creations.find(id)).getRight().toNullable()!;
      if (!c.status.isPending) return c;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('$id sigue pendiente');
  }

  CreationRequest request({bool runNow = true, List<String>? sources}) =>
      CreationRequest(
        kind: StudyCreationKind.podcast,
        scope: CreationScope.document(exodo),
        sourceIds: sources ?? [exodo],
        runNow: runNow,
      );

  test('el generador recibe lo que guardó el intento anterior; «Reintentar» '
      'lo conserva y «Volver a generar» lo descarta', () async {
    generator.error = Exception('se cortó');
    final queue = newQueue();
    final c = (await queue.create(request())).getRight().toNullable()!;
    await settled(c.id);
    expect(generator.seen, [null]);

    generator.error = null;
    await queue.retry(c.id);
    expect((await settled(c.id)).status, CreationStatus.ready);
    expect(generator.seen, [null, 'mitad']);
    // Terminada, lo hecho se va.
    expect((await h.creations.checkpoint(c.id)).getRight().toNullable(), null);

    await h.creations.saveCheckpoint(c.id, 'mitad');
    await queue.regenerate(c.id, options: const {'format': 'brief'});
    await settled(c.id);
    expect(generator.seen.last, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('lo que se termina sin la IA no espera al modelo, no arma el material '
      '—aunque sus fuentes se hayan borrado— y conserva el modelo con que se '
      'escribió', () async {
    final queue = newQueue();
    final c = (await queue.create(request())).getRight().toNullable()!;
    expect((await settled(c.id)).modelName, 'Gemma');

    status = unavailable;
    await h.creations.saveCheckpoint(c.id, 'listo:{"audio":1}');
    await queue.retry(c.id, runNow: true);
    final done = await settled(c.id);
    expect(done.status, CreationStatus.ready);
    expect(done.content, '{"audio":1}');
    expect(done.title, 'Sin IA');
    expect(done.modelName, 'Gemma');
    expect(done.sourceIds, [exodo]);
    expect(generator.finished, 1);
    expect(generator.generated, 1);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('sin fuentes y sin modelo, termina igual lo que no los usa', () async {
    final queue = newQueue();
    status = unavailable;
    final c = (await h.creations.create(
      request(sources: ['borrado']),
    )).getRight().toNullable()!;
    await h.creations.saveCheckpoint(c.id, 'listo:{}');
    await queue.resume();
    expect((await settled(c.id)).status, CreationStatus.ready);
    expect(generator.generated, 0);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('lo de «más tarde» que se termina sin la IA no espera la cuota de '
      'fondo; lo demás, sí', () async {
    status = unavailable;
    final queue = newQueue();
    final waits = (await queue.create(
      request(runNow: false),
    )).getRight().toNullable()!;
    final voice = (await h.creations.create(
      request(runNow: false),
    )).getRight().toNullable()!;
    await h.creations.saveCheckpoint(voice.id, 'listo:{}');
    await queue.resume();

    expect((await settled(voice.id)).status, CreationStatus.ready);
    final still = (await h.creations.find(waits.id)).getRight().toNullable()!;
    expect(still.status, CreationStatus.queued);
    expect(generator.generated, 0);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('lo que no se puede saber se genera como siempre, y se avisa', () async {
    final errors = <Object>[];
    final failing = _ThrowingFinisher();
    final queue = CreationQueue(
      repository: () => h.creations,
      scopes: () => h.scopes,
      material: () => h.material,
      generators: () => {StudyCreationKind.podcast: failing},
      personWriter: _Writer.new,
      backgroundWriter: _Writer.new,
      onError: (error, _) => errors.add(error),
    );
    queues.add(queue);
    final c = (await queue.create(request())).getRight().toNullable()!;
    expect((await settled(c.id)).status, CreationStatus.ready);
    expect(failing.generated, 1);
    expect(errors.single, isA<StateError>());
  }, timeout: const Timeout(Duration(seconds: 30)));
}

class _ThrowingFinisher extends _Generator {
  @override
  Future<CreationFinisher?> finisherWithoutModel(CreationJob job) =>
      throw StateError('no se pudo leer');
}
