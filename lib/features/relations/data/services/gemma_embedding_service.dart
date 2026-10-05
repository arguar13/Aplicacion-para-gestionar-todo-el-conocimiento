import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_service.dart';

/// [EmbeddingService] sobre el embedder activo de `flutter_gemma` — mismo
/// patrón de caching que `GemmaEngine`: el modelo cargado queda en memoria
/// entre pedidos, no se vuelve a resolver en cada llamado, hasta que se lo
/// suelta ([release]) porque falta memoria o la app lleva un rato en segundo
/// plano (F30).
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
/// `LanguageModelGate.whenUserIdle`): con el chat a la vista, no corre. La
/// excepción es [embedQuery], lo que busca la persona: lo pide ella.
class GemmaEmbeddingService implements EmbeddingService {
  GemmaEmbeddingService({
    required Future<bool> Function() ensureReady,
    Future<void> Function()? waitForUser,
    Future<EmbeddingModel> Function()? load,
    DateTime Function()? now,
  }) : _ensureReady = ensureReady,
       _waitForUser = waitForUser ?? _noWait,
       _load = load ?? FlutterGemma.getActiveEmbedder,
       _now = now ?? DateTime.now;

  final Future<bool> Function() _ensureReady;
  final Future<void> Function() _waitForUser;

  /// Carga el embedder activo: una función y no la llamada estática suelta,
  /// para probar el resto sin el motor nativo.
  final Future<EmbeddingModel> Function() _load;
  final DateTime Function() _now;

  static Future<void> _noWait() async {}

  EmbeddingModel? _model;

  /// Cuántos pedidos están usando el modelo ahora: con alguno, no se suelta.
  var _inUse = 0;
  DateTime? _lastUse;

  /// El cierre en curso: cargar de nuevo espera a que termine, para no
  /// recibir el modelo que se está cerrando.
  Future<void>? _closing;

  Future<EmbeddingModel> _activeModel() async {
    final closing = _closing;
    if (closing != null) await closing;

    final cached = _model;
    if (cached != null) return cached;

    if (!await _ensureReady()) {
      throw const EmbeddingModelNotReadyException();
    }

    final model = await _load();
    _model = model;
    return model;
  }

  @override
  Future<List<double>> embed(String text) => _using(
    // `retrievalDocument` siempre, nunca `retrievalQuery`: acá no hay
    // ninguna pregunta de usuario — tanto los chunks indexados como el
    // excerpt del elemento semilla que se compara contra ellos son
    // documentos, una comparación simétrica documento-a-documento.
    (model) =>
        model.generateEmbedding(text, taskType: TaskType.retrievalDocument),
  );

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) => _using(
    (model) =>
        model.generateEmbeddings(texts, taskType: TaskType.retrievalDocument),
  );

  /// Lo que busca la persona (F30): del lado de la pregunta
  /// (`retrievalQuery`), contra fragmentos guardados del lado del documento.
  /// Sin esperar: es ella quien lo pide. `retrievalQuery` es el tipo por
  /// defecto de `generateEmbedding`.
  @override
  Future<List<double>> embedQuery(String text) =>
      _using((model) => model.generateEmbedding(text), forUser: true);

  /// Corre [work] con el modelo, cuando la persona no está usando el de
  /// lenguaje —salvo que lo pida ella ([forUser])—, y anota el uso.
  Future<T> _using<T>(
    Future<T> Function(EmbeddingModel model) work, {
    bool forUser = false,
  }) async {
    if (!forUser) await _waitForUser();
    _inUse++;
    try {
      return await work(await _activeModel());
    } finally {
      _inUse--;
      _lastUse = _now();
    }
  }

  /// Saca el modelo de la memoria (F30), salvo que se esté usando o —con
  /// [unusedFor]— que se haya usado hace menos de ese rato.
  @override
  Future<void> release({Duration? unusedFor}) async {
    final model = _model;
    if (model == null || _inUse > 0) return;
    final last = _lastUse;
    if (unusedFor != null &&
        last != null &&
        _now().difference(last) < unusedFor) {
      return;
    }
    _model = null;
    final closing = _closing = model.close();
    try {
      await closing;
    } finally {
      _closing = null;
    }
  }
}
