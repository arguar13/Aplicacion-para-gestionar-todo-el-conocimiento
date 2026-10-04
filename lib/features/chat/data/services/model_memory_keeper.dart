import 'dart:async';

import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';

/// Cuánto tiene que pasar sin que nadie use los modelos, con la app en
/// segundo plano, para sacarlos de la memoria (F30).
///
/// Tres minutos: lo bastante para no soltarlos entre dos pasos de la IA de
/// fondo ni al cambiar un momento a otra app y volver, y lo bastante poco
/// para no dejar ~4 GB ocupados mientras el teléfono hace otra cosa.
/// Volver a cargarlos cuesta unos segundos; tenerlos de más puede hacer que
/// Android cierre la app —o las otras— por falta de memoria.
const kModelReleaseAfter = Duration(minutes: 3);

/// Saca de la memoria los dos modelos de la IA —Gemma, ~3,7 GB, y el de
/// vínculos— cuando no hacen falta (F30). Hasta F30 no se soltaban nunca,
/// ni con la app en segundo plano.
///
/// - **Cuando Android avisa que falta memoria** ([memoryPressure]): en el
///   acto, salvo lo que se esté usando en ese momento. Las charlas abiertas
///   cierran su sesión, como si llevaran un rato sin uso: el próximo mensaje
///   la reabre con lo conversado. Flutter da ese aviso con cualquier
///   `onTrimMemory` desde `TRIM_MEMORY_RUNNING_LOW`, y eso incluye
///   `TRIM_MEMORY_UI_HIDDEN`: **salir de la app** también lo dispara. Es lo
///   buscado —con la app oculta, ~4 GB ocupados sin uso es lo primero que
///   hace que Android la cierre—, y volver cuesta unos segundos de carga,
///   que el chat adelanta al verse de nuevo.
/// - **Con la app en segundo plano** ([appHidden]): pasado
///   [releaseAfter] sin que nadie los use —ni la persona ni la cola de la
///   IA—. Si la cola sigue trabajando, espera a que termine.
///
/// Nunca se cruza con un uso: Gemma se suelta en el turno del modelo
/// (`LanguageModelGate.runIfFree`), y el de vínculos, solo si ningún pedido
/// lo está usando. El próximo uso los vuelve a cargar solos.
class ModelMemoryKeeper {
  ModelMemoryKeeper({
    required LanguageModelGate gate,
    required GemmaEngine gemma,
    required Future<void> Function({Duration? unusedFor}) releaseEmbedder,
    required void Function(Object error, StackTrace stackTrace) onError,
    this.releaseAfter = kModelReleaseAfter,
  }) : _gate = gate,
       _gemma = gemma,
       _releaseEmbedder = releaseEmbedder,
       _onError = onError;

  final LanguageModelGate _gate;
  final GemmaEngine _gemma;
  final Future<void> Function({Duration? unusedFor}) _releaseEmbedder;

  /// Soltar falla de formas del motor nativo, sin un tipo propio: se
  /// registra y la app sigue —lo peor es que el modelo siga en memoria—.
  final void Function(Object error, StackTrace stackTrace) _onError;

  /// Ver [kModelReleaseAfter].
  final Duration releaseAfter;

  var _inBackground = false;
  Timer? _timer;

  /// La app pasó a segundo plano: pasado [releaseAfter] sin uso, los
  /// modelos se sueltan.
  void appHidden() {
    _inBackground = true;
    _timer?.cancel();
    _timer = Timer(releaseAfter, _check);
  }

  /// La app volvió al frente: ya no se sueltan por tiempo.
  void appShown() {
    _inBackground = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Android avisa que falta memoria: se sueltan ya.
  Future<void> memoryPressure() => _release(closeConversations: true);

  /// Ya en segundo plano un rato: si nadie los usó en ese rato, se sueltan.
  /// Mientras siga en segundo plano se vuelve a mirar: la cola pudo estar
  /// trabajando, o el de vínculos, recién usado.
  Future<void> _check() async {
    _timer = null;
    if (!_inBackground) return;
    final unused = _gate.unusedFor ?? (_gate.isIdle ? releaseAfter : null);
    if (unused != null && unused >= releaseAfter) {
      await _release(closeConversations: false, unusedFor: releaseAfter);
    }
    if (!_inBackground) return;
    _timer = Timer(
      unused == null || unused >= releaseAfter
          ? releaseAfter
          : releaseAfter - unused,
      _check,
    );
  }

  Future<void> _release({
    required bool closeConversations,
    Duration? unusedFor,
  }) async {
    try {
      await _releaseEmbedder(unusedFor: unusedFor);
      // Ver [_onError].
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
    if (!_gemma.isLoaded) return;
    try {
      if (closeConversations) await _gate.closeIdleConversations();
      await _gate.runIfFree(_gemma.release);
      // Ver [_onError].
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
