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

  setUp(() {
    service = GemmaEmbeddingService();
  });

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
}
