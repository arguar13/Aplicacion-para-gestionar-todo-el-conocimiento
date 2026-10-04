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
///
/// `ensureReady` es `EmbeddingModelManager.isReady`: registra el modelo si
/// sus archivos están enteros y `flutter_gemma` no lo recuerda —al reabrir la
/// app—, mismo motivo que `GemmaChatModel`.
///
/// **Espera a la persona** (F30): todo lo que lo usa es trabajo de fondo
/// —indexar, buscar vínculos, la IA que organiza—, y compite con el modelo de
/// lenguaje por el procesador y la memoria. Antes de cada pedido espera a
/// que la persona no esté usando el de lenguaje (`waitForUser`,
/// `LanguageModelGate.whenUserIdle`): con el chat a la vista, no corre.
class GemmaEmbeddingService implements EmbeddingService {
  GemmaEmbeddingService({
    required Future<bool> Function() ensureReady,
    Future<void> Function()? waitForUser,
  }) : _ensureReady = ensureReady,
       _waitForUser = waitForUser ?? _noWait;

  final Future<bool> Function() _ensureReady;
  final Future<void> Function() _waitForUser;

  static Future<void> _noWait() async {}

  EmbeddingModel? _model;

  Future<EmbeddingModel> _activeModel() async {
    final cached = _model;
    if (cached != null) return cached;

    if (!await _ensureReady()) {
      throw const EmbeddingModelNotReadyException();
    }

    final model = await FlutterGemma.getActiveEmbedder();
    _model = model;
    return model;
  }

  @override
  Future<List<double>> embed(String text) async {
    await _waitForUser();
    final model = await _activeModel();
    // `retrievalDocument` siempre, nunca `retrievalQuery`: acá no hay
    // ninguna pregunta de usuario — tanto los chunks indexados como el
    // excerpt del elemento semilla que se compara contra ellos son
    // documentos, una comparación simétrica documento-a-documento.
    return model.generateEmbedding(text, taskType: TaskType.retrievalDocument);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    await _waitForUser();
    final model = await _activeModel();
    return model.generateEmbeddings(
      texts,
      taskType: TaskType.retrievalDocument,
    );
  }
}
