import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_service.dart';

/// [EmbeddingService] sobre el embedder activo de `flutter_gemma` — mismo
/// patrón de caching que `GemmaChatModel._activeModel()`: el modelo cargado
/// queda en memoria entre pedidos, no se vuelve a resolver en cada llamado.
///
/// Import plano de `flutter_gemma.dart`: este archivo solo necesita la
/// clase abstracta de instancia (`EmbeddingModel`, con `generateEmbedding`),
/// nunca el enum de specs (`rag/embedding_models.dart`, con las URLs) que
/// sí necesita `GemmaEmbeddingModelManager` — cada uno importa solo lo que
/// usa, sin el `hide`/`show` que hace falta cuando conviven los dos en el
/// mismo archivo.
class GemmaEmbeddingService implements EmbeddingService {
  GemmaEmbeddingService();

  EmbeddingModel? _model;

  Future<EmbeddingModel> _activeModel() async {
    final cached = _model;
    if (cached != null) return cached;

    if (!FlutterGemma.hasActiveEmbedder()) {
      throw const EmbeddingModelNotReadyException();
    }

    final model = await FlutterGemma.getActiveEmbedder();
    _model = model;
    return model;
  }

  @override
  Future<List<double>> embed(String text) async {
    final model = await _activeModel();
    // `retrievalDocument` siempre, nunca `retrievalQuery`: acá no hay
    // ninguna pregunta de usuario — tanto los chunks indexados como el
    // excerpt del elemento semilla que se compara contra ellos son
    // documentos, una comparación simétrica documento-a-documento.
    return model.generateEmbedding(text, taskType: TaskType.retrievalDocument);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final model = await _activeModel();
    return model.generateEmbeddings(
      texts,
      taskType: TaskType.retrievalDocument,
    );
  }
}
