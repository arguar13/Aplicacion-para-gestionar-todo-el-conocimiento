import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';

/// La ventana de contexto con la que se carga Gemma: lo que entra entre la
/// instrucción, lo conversado, el pedido y la respuesta. Es la memoria de
/// trabajo del modelo —su «caché KV»—, que ocupa RAM aunque no se use: más
/// grande es más memoria y más espera para leer el pedido.
const kGemmaContextTokens = 2048;

/// Qué se le pide a `flutter_gemma` al cargar el modelo.
class GemmaLoadRequest {
  const GemmaLoadRequest({
    required this.maxTokens,
    this.backend,
    this.vision = false,
    this.speculativeDecoding,
  });

  final int maxTokens;

  /// `null`: lo que elija `flutter_gemma`, que prueba la GPU y cae a la CPU.
  final PreferredBackend? backend;

  /// Con la parte del modelo que mira imágenes.
  final bool vision;

  /// `null`: lo que traiga el modelo.
  final bool? speculativeDecoding;
}

/// Carga el modelo activo de `flutter_gemma`. Una función y no la llamada
/// estática suelta, para probar el resto sin el motor nativo.
typedef GemmaModelLoader =
    Future<InferenceModel> Function(GemmaLoadRequest request);

/// [GemmaModelLoader] de verdad.
Future<InferenceModel> loadActiveGemma(GemmaLoadRequest request) =>
    FlutterGemma.getActiveModel(
      maxTokens: request.maxTokens,
      preferredBackend: request.backend,
      supportImage: request.vision,
      maxNumImages: request.vision ? 1 : null,
      enableSpeculativeDecoding: request.speculativeDecoding,
    );

/// El modelo de Gemma cargado en memoria (~3,7 GB), compartido por todos los
/// que lo usan —el chat, las tareas de la persona y la IA de fondo—: los
/// mismos pesos, cargados una sola vez.
///
/// No ordena quién lo usa: [model] y [release] se llaman SIEMPRE dentro de un
/// turno de `LanguageModelGate`, que deja a uno solo a la vez. Así cargar,
/// usar y soltar nunca se cruzan.
///
/// Mide cada carga (F30): cuánto tardó y en qué parte del teléfono quedó
/// corriendo —`flutter_gemma` prueba la GPU y, si no arranca, cae a la CPU
/// sin avisar—.
class GemmaEngine {
  GemmaEngine({
    required Future<bool> Function() ensureReady,
    required LanguageModelMeter meter,
    GemmaModelLoader load = loadActiveGemma,
    this.contextTokens = kGemmaContextTokens,
  }) : _ensureReady = ensureReady,
       _meter = meter,
       _load = load;

  /// `ChatModelManager.isReady` del modelo elegido: lo registra si su archivo
  /// está entero —`flutter_gemma` no lo recuerda al reabrir la app—.
  final Future<bool> Function() _ensureReady;
  final LanguageModelMeter _meter;
  final GemmaModelLoader _load;

  /// La ventana de contexto que se pide al cargar.
  final int contextTokens;

  InferenceModel? _model;
  var _loads = 0;

  /// Si el modelo cargado tiene la parte que mira imágenes.
  var _vision = false;

  /// Si el modelo está en memoria ahora.
  bool get isLoaded => _model != null;

  /// Cuántas veces se cargó. Una sesión abierta sobre una carga anterior ya
  /// no sirve: el modelo de entonces se cerró.
  int get loadCount => _loads;

  /// El modelo cargado; lo carga si hace falta. Dentro de un turno.
  ///
  /// Con [vision], con la parte que mira imágenes (F30): si estaba cargado
  /// sin ella, lo vuelve a cargar. Esa parte ocupa memoria, así que no se
  /// carga hasta que llega la primera foto; después queda hasta que el
  /// modelo se suelte. Si no se puede cargar con ella, lo deja cargado sin
  /// ella y lanza [ChatImagesUnsupportedException].
  Future<InferenceModel> model({bool vision = false}) async {
    final loaded = _model;
    if (loaded != null && (_vision || !vision)) return loaded;
    if (loaded != null) await release();

    if (!await _ensureReady()) throw const ChatModelNotReadyException();

    if (!vision) return _loadWith(vision: false);
    try {
      return await _loadWith(vision: true);
      // El motor falla de formas sin un tipo propio: sea cual sea, la foto
      // no puede llegar, y se dice así.
    } on Object catch (error, stackTrace) {
      await _loadWith(vision: false);
      Error.throwWithStackTrace(
        ChatImagesUnsupportedException(error),
        stackTrace,
      );
    }
  }

  Future<InferenceModel> _loadWith({required bool vision}) async {
    final request = GemmaLoadRequest(maxTokens: contextTokens, vision: vision);
    final watch = Stopwatch()..start();
    final model = await _load(request);
    watch.stop();
    _model = model;
    _vision = vision;
    _loads++;
    _meter.recordLoad(
      LanguageModelLoad(
        duration: watch.elapsed,
        backend: _backendOf(model.activeBackend),
        requestedBackend: _backendOf(request.backend),
        vision: request.vision,
      ),
    );
    return model;
  }

  /// Saca el modelo de la memoria. Dentro de un turno; el próximo [model] lo
  /// vuelve a cargar.
  Future<void> release() async {
    final model = _model;
    if (model == null) return;
    _model = null;
    _vision = false;
    await model.close();
  }
}

LanguageModelBackend? _backendOf(PreferredBackend? backend) =>
    switch (backend) {
      null => null,
      PreferredBackend.gpu => LanguageModelBackend.gpu,
      PreferredBackend.cpu => LanguageModelBackend.cpu,
      PreferredBackend.npu => LanguageModelBackend.npu,
    };
