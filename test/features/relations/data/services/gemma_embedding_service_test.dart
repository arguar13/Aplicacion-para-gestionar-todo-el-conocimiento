import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/relations/data/services/gemma_embedding_service.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_service.dart';

/// Sin ningún modelo activo (no hay forma de tenerlo en un test sin canal
/// de plataforma real, mismo límite que `GemmaChatModel`, sin test propio
/// por el mismo motivo), lo único comprobable es el camino de "todavía no
/// está listo" — el mismo que protege a quien llama de pedir un embedding
/// antes de que `EmbeddingModelManager.isReady()` diera `true`.
void main() {
  late GemmaEmbeddingService service;
  late int checks;

  setUp(() {
    checks = 0;
    service = GemmaEmbeddingService(
      ensureReady: () async {
        checks++;
        return false;
      },
    );
  });

  test(
    'antes de usar el modelo le pregunta al gestor, que lo registra si '
    'su archivo está entero: flutter_gemma no lo recuerda al reabrir',
    () async {
      await expectLater(
        service.embed('texto'),
        throwsA(isA<EmbeddingModelNotReadyException>()),
      );
      expect(checks, 1);
    },
  );

  test('embed sin modelo activo lanza EmbeddingModelNotReadyException', () {
    expect(
      () => service.embed('texto'),
      throwsA(isA<EmbeddingModelNotReadyException>()),
    );
  });

  test(
    'embedBatch sin modelo activo lanza EmbeddingModelNotReadyException',
    () {
      expect(
        () => service.embedBatch(['a', 'b']),
        throwsA(isA<EmbeddingModelNotReadyException>()),
      );
    },
  );

  test('espera a que la persona suelte el modelo de lenguaje antes de usar '
      'el suyo (F30)', () async {
    final userDone = Completer<void>();
    var asked = 0;
    final waiting = GemmaEmbeddingService(
      ensureReady: () async {
        asked++;
        return false;
      },
      waitForUser: () => userDone.future,
    );

    final embedding = waiting.embedBatch(['a']);
    await pumpEventQueue();
    expect(asked, 0);

    userDone.complete();
    await expectLater(
      embedding,
      throwsA(isA<EmbeddingModelNotReadyException>()),
    );
    expect(asked, 1);
  });

  test('lo que busca la persona no espera a que suelte el modelo de '
      'lenguaje, y va del lado de la pregunta (F30)', () async {
    final model = _FakeEmbedder();
    final forUser = GemmaEmbeddingService(
      ensureReady: () async => true,
      load: () async => model,
      // Nunca se suelta: si la búsqueda esperara, no terminaría.
      waitForUser: () => Completer<void>().future,
    );

    expect(await forUser.embedQuery('mi tesis sobre Roma'), [1.0]);
    expect(model.taskTypes, [TaskType.retrievalQuery]);

    final background = forUser.embed('un fragmento');
    await pumpEventQueue();
    expect(model.taskTypes, hasLength(1), reason: 'el de fondo sí espera');
    unawaited(background);
  });

  group('sacarlo de la memoria (F30)', () {
    late List<_FakeEmbedder> loaded;
    late DateTime now;
    late GemmaEmbeddingService gemma;

    setUp(() {
      loaded = [];
      now = DateTime(2026, 10, 4);
      gemma = GemmaEmbeddingService(
        ensureReady: () async => true,
        load: () async {
          final model = _FakeEmbedder();
          loaded.add(model);
          return model;
        },
        now: () => now,
      );
    });

    test('lo cierra, y el próximo pedido lo vuelve a cargar', () async {
      await gemma.embed('a');

      await gemma.release();

      expect(loaded.single.closed, isTrue);
      expect(await gemma.embed('b'), [1.0]);
      expect(loaded, hasLength(2));
    });

    test('no lo suelta mientras un pedido lo usa', () async {
      await gemma.embed('a');
      final working = Completer<void>();
      loaded.single.pending = working;
      final batch = gemma.embedBatch(['b']);
      await pumpEventQueue();

      await gemma.release();
      expect(loaded.single.closed, isFalse);

      working.complete();
      await batch;
    });

    test('con un rato pedido, solo si pasó desde el último uso', () async {
      await gemma.embed('a');

      now = now.add(const Duration(minutes: 1));
      await gemma.release(unusedFor: const Duration(minutes: 3));
      expect(loaded.single.closed, isFalse);

      now = now.add(const Duration(minutes: 3));
      await gemma.release(unusedFor: const Duration(minutes: 3));
      expect(loaded.single.closed, isTrue);
    });
  });
}

/// Un modelo de vínculos de mentira: un vector de un número por texto.
class _FakeEmbedder extends Fake implements EmbeddingModel {
  bool closed = false;

  /// Si está, el próximo lote espera a que se complete.
  Completer<void>? pending;

  /// Con qué tipo de tarea se pidió cada vector suelto.
  final taskTypes = <TaskType>[];

  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    taskTypes.add(taskType);
    return [1.0];
  }

  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    await pending?.future;
    return [
      for (final _ in texts) const [1.0],
    ];
  }

  @override
  Future<void> close() async => closed = true;
}
