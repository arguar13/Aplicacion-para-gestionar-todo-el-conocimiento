import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/repositories/processing_state_repository.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/domain/transformers/transform_context.dart';
import 'package:sinapsis/features/transform/domain/usecases/process_item_usecase.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue_state.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

/// Va trayendo el contenido de lo que quedó pendiente, por **dos carriles**,
/// cada uno de a un elemento por vez.
///
/// **De a uno por carril y no todo en paralelo**, a propósito. Capturar diez
/// enlaces de golpe —algo perfectamente normal al vaciar una lista de
/// pendientes— dispararía diez descargas simultáneas: una ráfaga contra los
/// mismos servidores, que invita a que corten el acceso, y diez
/// transcripciones compitiendo por la memoria de un teléfono.
///
/// **Dos carriles y no uno** (F21): con una sola fila, un video de cuatro
/// horas transcribiéndose frenaba la página web que se guardó después. Todo
/// arranca en el carril corto; lo que tiene una parte larga pasa al largo
/// ([TransformContext.enterLongLane]) y libera el corto para el siguiente.
///
/// No bloquea nada: quien capturó ya tiene su elemento guardado, y la
/// interfaz se entera de cada cambio por el stream de la biblioteca —y del
/// avance de lo que está en curso, por el estado de esta cola—.
///
/// Sus dependencias se piden **al usarlas**, no al nacer: la cola vive en
/// memoria, y si naciera observando la cadena de proveedores que arma el
/// caso de uso, cualquier reconstrucción de uno de ellos —elegir otro modelo
/// de chat, por ejemplo— la descartaría con todo lo que tenía esperando.
class ProcessingQueueNotifier extends StateNotifier<ProcessingQueueState> {
  ProcessingQueueNotifier({
    required ProcessItemUseCase Function() processItem,
    required ProcessingStateRepository Function() processingStates,
    required AppLogger logger,
    LongWorkKeeper Function()? longWork,
  }) : _processItem = processItem,
       _processingStates = processingStates,
       _logger = logger,
       _longWork = longWork,
       super(const ProcessingQueueState());

  /// Cuántas veces se retoma algo que quedó a medias porque la app se cerró,
  /// antes de darlo por fallido. Tres cubre un cierre por accidente y un
  /// sistema que congela la app en segundo plano; más que eso es algo que
  /// la hace caer, y seguir reintentándolo en cada arranque sería un bucle.
  static const maxInterruptedAttempts = 3;

  final ProcessItemUseCase Function() _processItem;
  final ProcessingStateRepository Function() _processingStates;
  final AppLogger _logger;

  /// Lo que mantiene viva la app mientras hay trabajo largo (F21, decisión
  /// C). `null` en las pruebas que no lo miran.
  final LongWorkKeeper Function()? _longWork;

  /// El de [_longWork], pedido una sola vez, al primer uso: al descartarse,
  /// la cola suelta el que ya tiene, sin pedirle nada a un contenedor que
  /// quizá ya se descartó.
  LongWorkKeeper? _keeper;

  /// Lo que espera empezar, en orden.
  final _queue = Queue<String>();

  /// Lo que está en curso, en cualquiera de los dos carriles, con su avance.
  final _active = <String, ProcessingProgress>{};

  final _shortLane = _Lane();
  final _longLane = _Lane();

  var _isDraining = false;
  var _isDisposed = false;

  /// Si ya se recuperó lo que quedó a medias de una sesión anterior. Una vez
  /// por cola: lo que está "en curso" después de eso lo está de verdad, en
  /// esta sesión.
  var _recoveredInterrupted = false;

  /// Lo que sigue a la base para encolar lo que vuelve a quedar en espera.
  StreamSubscription<List<String>>? _pendingWatch;

  /// Suma un elemento a la cola y arranca si no estaba andando.
  void enqueue(String itemId) {
    // Sin esta comprobación, capturar algo y volver a abrir la app encolaría
    // dos veces lo mismo y se descargaría dos veces. Lo que está en curso ya
    // salió de la cola: mirar solo la cola daría por nuevo algo que en ese
    // instante se está descargando.
    if (_active.containsKey(itemId) || _queue.contains(itemId)) return;

    _queue.add(itemId);

    // Lo que acaba de entrar cambia cuántos faltan: se publica ya, no al
    // sacar el siguiente de la cola.
    _publish();
    unawaited(_drain());
  }

  /// Retoma todo lo que quedó esperando de sesiones anteriores.
  ///
  /// Se llama al abrir la app: alguien pudo capturar cinco enlaces sin
  /// conexión y cerrar; al volver, eso tiene que completarse solo, sin que
  /// haya que acordarse de pedirlo.
  ///
  /// Incluye lo que quedó **en curso**: la app se cerró, o el sistema la
  /// congeló o la mató, a mitad de procesarlo. Sin esto quedaba "Procesando"
  /// para siempre, porque nada lo volvía a encolar. El tope de
  /// [maxInterruptedAttempts] evita que algo que la hace caer se retome en
  /// cada arranque.
  ///
  /// Los que fallaron NO entran acá. Un fallo puede ser permanente —un video
  /// borrado, una página que ya no existe— y reintentarlo en cada arranque
  /// sería gastar batería y datos para volver a fallar. Se reintentan a
  /// pedido, desde el elemento ([retry]).
  Future<void> resume() async {
    try {
      final states = _processingStates();
      if (!_recoveredInterrupted) {
        final interrupted = await states.recoverInterrupted(
          maxAttempts: maxInterruptedAttempts,
          inFlight: _active.keys.toSet(),
        );
        _recoveredInterrupted = true;
        if (interrupted.isNotEmpty) {
          _logger.info(
            'Se retoman ${interrupted.length} elementos que quedaron a medias.',
          );
        }
      }

      for (final itemId in await states.pendingIds()) {
        if (_isDisposed) return;
        enqueue(itemId);
      }

      // De acá en más, la cola sigue a la base: lo que se restaura de la
      // papelera, lo que trae una copia de otro dispositivo o lo que vuelve a
      // quedar en espera entra solo, sin que quien lo cambió tenga que
      // avisar. `enqueue` no repite lo que ya está en la cola o en curso.
      _pendingWatch ??= states.watchPendingIds().listen(
        (ids) {
          for (final itemId in ids) {
            if (_isDisposed) return;
            enqueue(itemId);
          }
        },
        onError: (Object e, StackTrace stackTrace) =>
            _logger.error('Se dejó de seguir lo pendiente.', e, stackTrace),
      );
      // Lo que se retoma no puede, si la base falla, tumbar la app en el
      // arranque: se informa y la próxima apertura vuelve a intentarlo.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _logger.error('No se pudo retomar lo pendiente.', e, stackTrace);
    }
  }

  /// Vuelve a procesar [itemId] a pedido del usuario, desde cero: sin el
  /// motivo del fallo anterior y con sus propios intentos.
  Future<void> retry(String itemId) async {
    try {
      await _processingStates().requeue(itemId);
      // Si no se pudo dejar en espera, se procesa igual: el reintento es lo
      // que el usuario pidió, y el procesamiento vuelve a marcar su estado.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _logger.error('No se pudo dejar en espera $itemId.', e, stackTrace);
    }
    if (_isDisposed) return;
    enqueue(itemId);
  }

  /// Vuelve a extraer el texto de [itemId] a pedido del usuario (F22): con
  /// el motor y los lectores de hoy, aunque ya tenga texto. Deja la marca
  /// en la base —sobrevive a que se cierre la app— y lo pone en espera; el
  /// procesamiento reemplaza el texto viejo en su lugar y reubica los
  /// subrayados (ver `ProcessItemUseCase`).
  ///
  /// Sin la marca no se encola: procesarlo así lo daría por completo sin
  /// hacer nada.
  Future<void> reextract(String itemId) async {
    try {
      final states = _processingStates();
      await states.save(
        itemId,
        ProcessingCheckpointKind.reextract,
        position: 0,
        content: '',
      );
      await states.requeue(itemId);
      // Cualquier falla de la base: se avisa en el registro y no se encola.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _logger.error(
        'No se pudo pedir volver a extraer $itemId.',
        e,
        stackTrace,
      );
      return;
    }
    if (_isDisposed) return;
    enqueue(itemId);
  }

  /// Saca de la cola, en orden, lo que va entrando al carril corto. Cada
  /// elemento corre por su cuenta ([_run]): el bucle solo espera a que el
  /// carril corto se libere —cuando el elemento termina, o cuando pasa al
  /// largo— para sacar el siguiente.
  Future<void> _drain() async {
    if (_isDraining) return;
    _isDraining = true;

    try {
      while (_queue.isNotEmpty && !_isDisposed) {
        await _shortLane.acquire();
        if (_isDisposed || _queue.isEmpty) {
          _shortLane.release();
          break;
        }

        final itemId = _queue.removeFirst();
        _active[itemId] = const ProcessingProgress();
        _publish();
        unawaited(_run(itemId));
      }
    } finally {
      _isDraining = false;
    }
  }

  Future<void> _run(String itemId) async {
    final context = _QueueTransformContext(
      shortLane: _shortLane,
      longLane: _longLane,
      onLaneChanged: (lane) => _update(itemId, lane: lane),
      onProgress: (done, total) => _update(itemId, done: done, total: total),
    );

    // Si el usuario lo manda a la papelera —desde el detalle, desde la
    // lista, al fusionar duplicados: desde donde sea— mientras se procesa, se
    // lo suelta en el acto y el carril queda libre. Se escucha la base y no
    // a quien borra: así ningún camino de borrado se puede olvidar de avisar.
    StreamSubscription<bool>? removal;
    try {
      removal = _processingStates().watchRemoved(itemId).listen((removed) {
        if (removed) context.cancellation.cancel();
      }, onError: (Object _) {});

      // El caso de uso no lanza: traduce cualquier fallo a un `Left` y deja
      // el elemento marcado. Es lo que permite que un enlace roto no corte
      // la cola y los demás sigan procesándose.
      final result = await _processItem().process(itemId, context: context);
      result.match(
        (failure) => _logger.warning('Quedó pendiente $itemId: $failure'),
        (_) {},
      );
      // Red de seguridad por si algo lanza igual —armar el caso de uso, por
      // ejemplo—: un solo elemento nunca puede cortar la cola.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _logger.error('La cola no pudo procesar $itemId.', e, stackTrace);
    } finally {
      await removal?.cancel();
      // Suelta el carril que tenga —el corto, el largo, o su lugar en la
      // fila del largo— para el siguiente.
      context.release();
      _active.remove(itemId);
      _publish();
    }
  }

  void _update(String itemId, {ProcessingLane? lane, int? done, int? total}) {
    final current = _active[itemId];
    if (current == null) return;
    _active[itemId] = current.copyWith(
      lane: lane ?? current.lane,
      done: done ?? current.done,
      total: total ?? current.total,
    );
    _publish();
  }

  void _publish() {
    if (_isDisposed) return;
    state = ProcessingQueueState(
      active: Map.unmodifiable(_active),
      waiting: _queue.length,
    );
    _keepAliveWhileLong();
  }

  /// Mientras algo esté en el carril largo, la app se mantiene viva con el
  /// avance de lo que corre ahí; si no, se suelta.
  void _keepAliveWhileLong() {
    final keeper = _keeper ??= _longWork?.call();
    if (keeper == null) return;

    final long = _active.values.where((p) => p.lane == ProcessingLane.long);
    if (long.isEmpty) {
      keeper.idle();
    } else {
      final current = long.first;
      keeper.working(done: current.done, total: current.total);
    }
  }

  @override
  void dispose() {
    // Corta el bucle en el próximo turno: sin esto, un `drain` en curso
    // seguiría escribiendo estado sobre un notifier ya descartado.
    _isDisposed = true;
    _queue.clear();
    _keeper?.idle();
    unawaited(_pendingWatch?.cancel());
    super.dispose();
  }
}

/// Un carril: de a un elemento por vez, y los que esperan, en orden.
class _Lane {
  final _waiting = Queue<Completer<void>>();
  var _busy = false;

  /// Espera turno. Si [cancellation] pide abandonar mientras espera, deja su
  /// lugar en la fila y lanza [ProcessingCancelledException].
  Future<void> acquire([CancellationSignal? cancellation]) async {
    if (!_busy) {
      _busy = true;
      return;
    }

    final turn = Completer<void>();
    _waiting.add(turn);
    if (cancellation == null) return turn.future;

    await Future.any([turn.future, cancellation.whenCancelled]);
    if (turn.isCompleted) {
      // Le tocó el turno —aunque justo se haya pedido abandonar: quien lo
      // llamó se entera por la señal, y suelta el carril al terminar—.
      return;
    }
    _waiting.remove(turn);
    throw const ProcessingCancelledException();
  }

  /// Pasa el turno al siguiente que espera, o deja el carril libre.
  void release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _busy = false;
    }
  }
}

/// El [TransformContext] que la cola le da a cada elemento: su señal de
/// cancelación, sus carriles y cómo publica su avance.
class _QueueTransformContext implements TransformContext {
  _QueueTransformContext({
    required _Lane shortLane,
    required _Lane longLane,
    required void Function(ProcessingLane lane) onLaneChanged,
    required void Function(int done, int total) onProgress,
  }) : _shortLane = shortLane,
       _longLane = longLane,
       _onLaneChanged = onLaneChanged,
       _onProgress = onProgress;

  final _Lane _shortLane;
  final _Lane _longLane;
  final void Function(ProcessingLane lane) _onLaneChanged;
  final void Function(int done, int total) _onProgress;

  final cancellation = CancellationSignal();

  /// Qué carril tiene tomado ahora: nace con el corto, que la cola le dio.
  _Lane? _held;
  var _enteredLong = false;
  var _released = false;

  @override
  bool get isCancelled => cancellation.isCancelled;

  @override
  Future<void> get whenCancelled => cancellation.whenCancelled;

  @override
  void throwIfCancelled() => cancellation.throwIfCancelled();

  @override
  Future<void> enterLongLane() async {
    if (_enteredLong || _released) return;
    _enteredLong = true;

    // Libera el corto para el siguiente, y espera turno en el largo.
    _held = null;
    _shortLane.release();
    _onLaneChanged(ProcessingLane.waitingForLong);

    await _longLane.acquire(cancellation);
    if (_released) {
      // La cola ya lo soltó —se abandonó mientras esperaba y justo le tocó—:
      // devuelve el turno que no va a usar.
      _longLane.release();
      return;
    }
    _held = _longLane;
    _onLaneChanged(ProcessingLane.long);
  }

  @override
  void reportProgress(int done, int total) => _onProgress(done, total);

  /// Suelta lo que tenga tomado. Una vez.
  void release() {
    if (_released) return;
    _released = true;
    if (!_enteredLong) {
      _shortLane.release();
    } else {
      _held?.release();
    }
    _held = null;
  }
}

/// Deliberadamente NO autoDispose: la cola tiene que seguir trabajando
/// aunque el usuario cambie de pantalla. Descartarla al desmontar la lista
/// dejaría las descargas a medio camino cada vez que alguien abre un detalle.
///
/// Y deliberadamente sin `ref.watch`: ver [ProcessingQueueNotifier].
final processingQueueProvider =
    StateNotifierProvider<ProcessingQueueNotifier, ProcessingQueueState>((ref) {
      return ProcessingQueueNotifier(
        processItem: () => ref.read(processItemUseCaseProvider),
        processingStates: () => ref.read(processingStateRepositoryProvider),
        logger: ref.read(appLoggerProvider),
        longWork: () => ref.read(longWorkKeeperProvider),
      );
    });

/// Cuánto va un elemento, si está en curso: lo que dibuja la barra de avance.
final processingProgressProvider = Provider.family<ProcessingProgress?, String>(
  (ref, itemId) => ref.watch(
    processingQueueProvider.select((state) => state.active[itemId]),
  ),
);
