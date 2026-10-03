import 'dart:async';
import 'dart:collection';

/// El turno para usar el modelo de lenguaje del teléfono (F27): uno solo a la
/// vez, y la persona antes que la IA que organiza en segundo plano.
///
/// Hay UNA instancia de Gemma cargada (~3,7 GB) para el chat, resumir,
/// generar tarjetas, el quiz y ahora la cola de la IA. Hasta F27 nada
/// ordenaba quién la usaba: `flutter_gemma` arma cada `createChat` sobre la
/// sesión única del modelo (`InferenceModel.session`), así que dos pedidos a
/// la vez —un resumen mientras se generaban las tarjetas, o la cola de la IA
/// mientras la persona chatea— se pisaban la sesión. Con la cola corriendo
/// sola, eso iba a pasar todo el tiempo.
///
/// Las reglas:
///
/// - **De a uno.** Lo que corre, corre hasta el final: una generación de
///   `flutter_gemma` no se puede interrumpir a mitad sin perderla.
/// - **La persona primero.** Cuando se libera el turno, lo toma quien espera
///   de parte de la persona ([runForUser]) antes que la cola de la IA
///   ([runInBackground]).
/// - **Una charla abierta es uso.** Una conversación deja su sesión abierta
///   entre mensajes; si la cola abriera la suya en el medio, le cerraría la
///   sesión a la charla. Mientras haya una abierta ([holdForUser]), la cola
///   no empieza nada.
///
/// Lo peor que espera la persona es lo que tarde el paso de la IA que ya
/// estaba corriendo —una sola llamada al modelo, no una pasada entera—: la
/// cola pide el turno de nuevo para cada llamada.
class LanguageModelGate {
  var _busy = false;
  var _holds = 0;
  final _userWaiting = Queue<Completer<void>>();
  final _backgroundWaiting = Queue<Completer<void>>();

  /// Si la persona está usando el modelo: corriendo, esperando su turno o con
  /// una charla abierta.
  bool get isUserActive => _holds > 0 || _userWaiting.isNotEmpty;

  /// Corre [work] de parte de la persona: espera, como mucho, a que termine
  /// lo que ya está corriendo, y pasa antes que la cola de la IA.
  Future<T> runForUser<T>(Future<T> Function() work) async {
    if (_busy) {
      final turn = Completer<void>();
      _userWaiting.add(turn);
      await turn.future;
    } else {
      _busy = true;
    }
    try {
      return await work();
    } finally {
      _release();
    }
  }

  /// Corre [work] para la cola de la IA: solo cuando nadie más lo usa ni
  /// espera, y sin charla abierta.
  Future<T> runInBackground<T>(Future<T> Function() work) async {
    if (_busy || isUserActive) {
      final turn = Completer<void>();
      _backgroundWaiting.add(turn);
      await turn.future;
    } else {
      _busy = true;
    }
    try {
      return await work();
    } finally {
      _release();
    }
  }

  /// Una charla abierta: hasta que se suelte, la cola de la IA no empieza
  /// nada. Los mensajes de la charla van igual por [runForUser].
  LanguageModelHold holdForUser() {
    _holds++;
    return LanguageModelHold._(this);
  }

  void _dropHold() {
    _holds--;
    if (!_busy) _handOver();
  }

  /// Pasa el turno: primero a la persona; a la cola, solo si la persona no
  /// lo está usando.
  void _release() {
    _busy = false;
    _handOver();
  }

  void _handOver() {
    if (_userWaiting.isNotEmpty) {
      _busy = true;
      _userWaiting.removeFirst().complete();
    } else if (_holds == 0 && _backgroundWaiting.isNotEmpty) {
      _busy = true;
      _backgroundWaiting.removeFirst().complete();
    }
  }
}

/// Una charla abierta sobre el modelo (ver
/// `LanguageModelGate.holdForUser`). Soltarla dos veces no hace nada.
class LanguageModelHold {
  LanguageModelHold._(this._gate);

  final LanguageModelGate _gate;
  var _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _gate._dropHold();
  }
}
