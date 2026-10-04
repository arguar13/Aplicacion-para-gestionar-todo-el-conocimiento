import 'dart:async';

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
}
