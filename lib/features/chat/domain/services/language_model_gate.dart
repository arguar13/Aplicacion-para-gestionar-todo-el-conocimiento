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
/// - **De a uno.** Nunca dos trabajos usan el modelo a la vez.
/// - **La persona primero.** Cuando se libera el turno, lo toma quien espera
///   de parte de la persona ([runForUser]) antes que la cola de la IA
///   ([runInBackground]). Y si la cola está escribiendo cuando la persona
///   lo pide, **se la corta** (F30): el trabajo de la cola dice cómo
///   cortarse (`onPreempt`) —su respuesta a medias se descarta y lo repite
///   entero cuando la persona termine—. Antes la persona esperaba lo que
///   tardara el paso en curso, que podía ser un minuto.
/// - **El chat a la vista es uso** (F30). Con la pantalla del chat abierta,
///   la cola no empieza nada aunque todavía no haya ningún mensaje: la
///   persona está por escribir.
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
/// Lo peor que espera la persona es lo que tarde en cortarse el paso de la
/// IA que ya estaba corriendo: si estaba leyendo el pedido —el «prefill»,
/// que el motor hace de una vez—, eso; si ya escribía, casi nada. La cola
/// pide el turno de nuevo para cada llamada.
///
/// **Los vínculos también esperan** (F30): el modelo de vínculos no usa este
/// turno —es otro modelo, más chico—, pero compite por el procesador y la
/// memoria. Antes de cada tanda, espera a que la persona no esté usando el
/// de lenguaje ([whenUserIdle]).
class LanguageModelGate {
  LanguageModelGate({
    this.idleRelease = kChatIdleRelease,
    void Function(Object error, StackTrace stackTrace)? onError,
    DateTime Function()? clock,
  }) : _onError = onError,
       _clock = clock ?? DateTime.now;

  /// Cuánto retiene el modelo una charla sin uso: ver [kChatIdleRelease].
  final Duration idleRelease;

  /// Dónde se registra un fallo al cerrar la sesión de una charla sin uso:
  /// pasa solo, sin nadie que lo espere. Sin esto, se lanza en la zona.
  final void Function(Object error, StackTrace stackTrace)? _onError;

  final DateTime Function() _clock;

  var _busy = false;

  /// Cuándo se soltó el modelo por última vez; `null` si nunca se usó.
  DateTime? _lastUse;

  /// Si el que tiene el turno ahora es la persona.
  var _busyForUser = false;

  /// Cómo cortar el trabajo de la cola que tiene el turno ahora; `null` si
  /// no lo tiene la cola, o si ya se lo cortó.
  void Function()? _preemptBackground;

  final _idleWaiters = <Completer<void>>[];

  /// Las charlas que retienen el modelo ahora: las soltadas por falta de uso
  /// no están.
  final _holding = <LanguageModelHold>{};
  final _userWaiting = Queue<Completer<void>>();
  final _backgroundWaiting = Queue<Completer<void>>();
  var _chatVisible = false;

  /// Si la persona está usando el modelo: corriendo, esperando su turno, con
  /// una charla en uso o con el chat a la vista.
  bool get isUserActive =>
      (_busy && _busyForUser) ||
      _holding.isNotEmpty ||
      _userWaiting.isNotEmpty ||
      _chatVisible;

  /// Si nadie usa el modelo ni espera para usarlo: ni la persona ni la cola.
  bool get isIdle => !_busy && !isUserActive && _backgroundWaiting.isEmpty;

  /// Cuánto hace que nadie usa el modelo: `null` si alguien lo usa o espera
  /// para usarlo ([isIdle] es falso) o si nunca se usó.
  Duration? get unusedFor {
    final last = _lastUse;
    if (!isIdle || last == null) return null;
    return _clock().difference(last);
  }

  /// Corre [work] con el modelo solo si nadie lo usa ni espera para usarlo
  /// ahora: si no, no lo corre y da `false`. Para soltar la memoria del
  /// modelo (F30) sin cruzarse con nadie y sin hacer esperar a nadie.
  Future<bool> runIfFree(Future<void> Function() work) async {
    if (_busy || _userWaiting.isNotEmpty || _backgroundWaiting.isNotEmpty) {
      return false;
    }
    _busy = true;
    _busyForUser = false;
    try {
      await work();
      return true;
    } finally {
      _release();
    }
  }

  /// Cierra ya las sesiones de las charlas abiertas, como si llevaran un rato
  /// sin uso: el próximo mensaje de cada una la reabre con lo conversado.
  /// Para soltar la memoria del modelo cuando Android avisa que falta (F30).
  Future<void> closeIdleConversations() async {
    for (final hold in List.of(_holding)) {
      hold._idleTimer?.cancel();
      hold._idleTimer = null;
      if (!hold._closing) await _idleOut(hold);
    }
  }

  /// Completa cuando la persona no esté usando el modelo de lenguaje (ver
  /// [isUserActive]); en el acto, si ya no lo usa. Para el trabajo de fondo
  /// que no usa este turno pero compite con él: los vínculos.
  Future<void> whenUserIdle() {
    if (!isUserActive) return Future.value();
    final waiter = Completer<void>();
    _idleWaiters.add(waiter);
    return waiter.future;
  }

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
    if (!visible && !_busy) _handOver();
    _wakeIdleWaiters();
  }

  /// Corre [work] de parte de la persona: pasa antes que la cola de la IA y,
  /// si la cola está escribiendo, la corta ([preempt]). Sin [preempt] —para
  /// lo que no apura, como cerrar una charla o cargar el modelo de
  /// antemano—, espera a que termine.
  Future<T> runForUser<T>(
    Future<T> Function() work, {
    bool preempt = true,
  }) async {
    if (_busy) {
      final turn = Completer<void>();
      _userWaiting.add(turn);
      if (preempt) {
        final cut = _preemptBackground;
        _preemptBackground = null;
        cut?.call();
      }
      await turn.future;
    } else {
      _busy = true;
    }
    _busyForUser = true;
    try {
      return await work();
    } finally {
      _release();
    }
  }

  /// Corre [work] para la cola de la IA: solo cuando nadie más lo usa ni
  /// espera, sin una charla en uso y sin el chat a la vista.
  ///
  /// [onPreempt] es cómo cortarlo si la persona pide el modelo mientras
  /// corre: tiene que hacer que [work] termine pronto —con un error, para
  /// que quien lo pidió lo repita—. Sin [onPreempt], corre hasta el final.
  Future<T> runInBackground<T>(
    Future<T> Function() work, {
    void Function()? onPreempt,
  }) async {
    if (_busy || isUserActive) {
      final turn = Completer<void>();
      _backgroundWaiting.add(turn);
      await turn.future;
    } else {
      _busy = true;
    }
    _busyForUser = false;
    _preemptBackground = onPreempt;
    try {
      return await work();
    } finally {
      _preemptBackground = null;
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
      await runForUser(() async => hold._onIdle?.call(), preempt: false);
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
    _wakeIdleWaiters();
  }

  void _dropHold(LanguageModelHold hold) {
    if (!_holding.remove(hold)) return;
    if (!_busy) _handOver();
    _wakeIdleWaiters();
  }

  /// Pasa el turno: primero a la persona; a la cola, solo si la persona no
  /// lo está usando.
  void _release() {
    _busy = false;
    _busyForUser = false;
    _lastUse = _clock();
    _handOver();
    _wakeIdleWaiters();
  }

  void _handOver() {
    if (_userWaiting.isNotEmpty) {
      _busy = true;
      _busyForUser = true;
      _userWaiting.removeFirst().complete();
    } else if (_holding.isEmpty &&
        !_chatVisible &&
        _backgroundWaiting.isNotEmpty) {
      _busy = true;
      _busyForUser = false;
      _backgroundWaiting.removeFirst().complete();
    }
  }

  /// Avisa a quienes esperaban que la persona soltara el modelo
  /// ([whenUserIdle]), si ya lo soltó.
  void _wakeIdleWaiters() {
    if (isUserActive || _idleWaiters.isEmpty) return;
    final waiters = List.of(_idleWaiters);
    _idleWaiters.clear();
    for (final waiter in waiters) {
      waiter.complete();
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
