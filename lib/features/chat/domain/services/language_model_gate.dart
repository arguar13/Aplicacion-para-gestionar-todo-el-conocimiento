import 'dart:async';
import 'dart:collection';

/// Cuánto retiene el modelo una charla sin uso (F27): sin un mensaje en este
/// rato, y sin la pantalla del chat a la vista, la charla suelta el modelo y
/// la cola de la IA puede seguir.
///
/// Dos minutos porque lo que cuesta cada lado es muy distinto. Retener de más
/// es frenar una pasada de horas con el cargador mientras el teléfono duerme
/// con el chat abierto. Soltar de menos solo cuesta que el próximo mensaje
/// reabra la sesión y le vuelva a dar lo conversado (unos segundos de
/// lectura del modelo, no de respuesta). Leer una respuesta larga no cuenta
/// como «sin uso»: con la pantalla a la vista la charla no se suelta nunca.
const kChatIdleRelease = Duration(minutes: 2);

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
/// - **Una charla en uso es uso.** Una conversación deja su sesión abierta
///   entre mensajes; si la cola abriera la suya en el medio, le cerraría la
///   sesión a la charla. Mientras haya una en uso ([holdForUser]), la cola no
///   empieza nada. **En uso** quiere decir de verdad: con un mensaje en los
///   últimos [idleRelease], o con la pantalla del chat a la vista
///   ([chatVisible]). Pasado ese rato sin nada de eso, la charla cierra su
///   sesión y suelta el modelo ([LanguageModelHold]); si la persona vuelve a
///   escribir, la retoma. Así una charla que quedó abierta con el teléfono
///   bloqueado no frena la cola para siempre.
///
/// Lo peor que espera la persona es lo que tarde el paso de la IA que ya
/// estaba corriendo —una sola llamada al modelo, no una pasada entera—: la
/// cola pide el turno de nuevo para cada llamada.
class LanguageModelGate {
  LanguageModelGate({
    this.idleRelease = kChatIdleRelease,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _onError = onError;

  /// Cuánto retiene el modelo una charla sin uso: ver [kChatIdleRelease].
  final Duration idleRelease;

  /// Dónde se registra un fallo al cerrar la sesión de una charla sin uso:
  /// pasa solo, sin nadie que lo espere. Sin esto, se lanza en la zona.
  final void Function(Object error, StackTrace stackTrace)? _onError;

  var _busy = false;

  /// Las charlas que retienen el modelo ahora: las soltadas por falta de uso
  /// no están.
  final _holding = <LanguageModelHold>{};
  final _userWaiting = Queue<Completer<void>>();
  final _backgroundWaiting = Queue<Completer<void>>();
  var _chatVisible = false;

  /// Si la persona está usando el modelo: corriendo, esperando su turno o con
  /// una charla en uso.
  bool get isUserActive => _holding.isNotEmpty || _userWaiting.isNotEmpty;

  /// Si la pantalla del chat está a la vista: en primer plano, sin otra
  /// pantalla encima y con la app abierta. Mientras lo esté, ninguna charla
  /// suelta el modelo por falta de uso; al dejar de estarlo, empieza a
  /// contar [idleRelease]. Lo avisa la pantalla.
  bool get chatVisible => _chatVisible;

  set chatVisible(bool visible) {
    if (visible == _chatVisible) return;
    _chatVisible = visible;
    for (final hold in _holding) {
      hold._restartIdle();
    }
  }

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
  /// espera, y sin una charla en uso.
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

  /// Una charla abierta: mientras esté en uso, la cola de la IA no empieza
  /// nada. Los mensajes de la charla van igual por [runForUser], y cada uno
  /// avisa el uso ([LanguageModelHold.touch]).
  ///
  /// [onIdle] es lo que hace la charla al soltar el modelo por falta de uso:
  /// cerrar su sesión, para que la cola pueda abrir la suya. Corre en un
  /// turno de la persona —nada usa el modelo mientras tanto—, y recién al
  /// terminar el modelo pasa a la cola.
  LanguageModelHold holdForUser({Future<void> Function()? onIdle}) {
    final hold = LanguageModelHold._(this, onIdle);
    _holding.add(hold);
    hold._restartIdle();
    return hold;
  }

  /// [hold] lleva [idleRelease] sin uso y sin la pantalla a la vista: cierra
  /// su sesión en un turno de la persona y suelta el modelo, salvo que en el
  /// medio la persona haya vuelto a usarla.
  Future<void> _idleOut(LanguageModelHold hold) async {
    hold._closing = true;
    try {
      await runForUser(() async => hold._onIdle?.call());
      // La sesión es de `flutter_gemma`, que falla de formas sin un tipo
      // propio. Si no se pudo cerrar, el modelo se suelta igual: la charla
      // ya no la va a usar —la reabre al próximo mensaje—.
    } on Object catch (e, stackTrace) {
      final onError = _onError;
      if (onError == null) rethrow;
      onError(e, stackTrace);
    } finally {
      hold._closing = false;
    }
    if (hold._released) return;
    if (hold._touchedWhileClosing) {
      hold
        .._touchedWhileClosing = false
        .._restartIdle();
      return;
    }
    _holding.remove(hold);
    if (!_busy) _handOver();
  }

  void _dropHold(LanguageModelHold hold) {
    if (!_holding.remove(hold)) return;
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
    } else if (_holding.isEmpty && _backgroundWaiting.isNotEmpty) {
      _busy = true;
      _backgroundWaiting.removeFirst().complete();
    }
  }
}

/// Una charla abierta sobre el modelo (ver
/// `LanguageModelGate.holdForUser`). Retiene el modelo mientras esté en uso;
/// pasado `LanguageModelGate.idleRelease` sin uso y sin la pantalla del chat
/// a la vista, lo suelta sola ([isIdle]). [touch] la vuelve a poner en uso.
/// Soltarla dos veces no hace nada.
class LanguageModelHold {
  LanguageModelHold._(this._gate, this._onIdle);

  final LanguageModelGate _gate;
  final Future<void> Function()? _onIdle;
  Timer? _idleTimer;
  var _released = false;
  var _closing = false;
  var _touchedWhileClosing = false;

  /// Si soltó el modelo por falta de uso: la próxima vez que se use, la
  /// charla tiene que reabrir su sesión.
  bool get isIdle => !_released && !_gate._holding.contains(this);

  /// La persona usó la charla —mandó un mensaje, llegó la respuesta—: vuelve
  /// a retener el modelo, si lo había soltado, y el rato sin uso empieza de
  /// nuevo.
  void touch() {
    if (_released) return;
    if (_closing) {
      // La sesión se está cerrando: el mensaje que llega espera su turno
      // detrás del cierre y la reabre. La charla sigue en uso.
      _touchedWhileClosing = true;
      return;
    }
    _gate._holding.add(this);
    _restartIdle();
  }

  void release() {
    if (_released) return;
    _released = true;
    _idleTimer?.cancel();
    _gate._dropHold(this);
  }

  void _restartIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_released || !_gate._holding.contains(this) || _gate._chatVisible) {
      return;
    }
    _idleTimer = Timer(_gate.idleRelease, () {
      _idleTimer = null;
      unawaited(_gate._idleOut(this));
    });
  }
}
