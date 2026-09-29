import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/transform/domain/repositories/processing_state_repository.dart';
import 'package:sinapsis/features/transform/domain/usecases/process_item_usecase.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue_state.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

/// Va trayendo el contenido de lo que quedó pendiente, de a uno.
///
/// **De a uno y no en paralelo**, a propósito. Capturar diez enlaces de golpe
/// —algo perfectamente normal al vaciar una lista de pendientes— dispararía
/// diez descargas simultáneas: una ráfaga contra los mismos servidores, que
/// invita a que corten el acceso, y diez transcripciones compitiendo por la
/// memoria de un teléfono. Secuencial tarda más en total y no molesta a
/// nadie; además, lo que se va completando aparece en la lista a medida que
/// termina, así que la espera se ve avanzar.
///
/// No bloquea nada: quien capturó ya tiene su elemento guardado, y la
/// interfaz se entera de cada cambio por el stream de la biblioteca.
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
  }) : _processItem = processItem,
       _processingStates = processingStates,
       _logger = logger,
       super(const ProcessingQueueState.idle());

  /// Cuántas veces se retoma algo que quedó a medias porque la app se cerró,
  /// antes de darlo por fallido. Tres cubre un cierre por accidente y un
  /// sistema que congela la app en segundo plano; más que eso es algo que
  /// la hace caer, y seguir reintentándolo en cada arranque sería un bucle.
  static const maxInterruptedAttempts = 3;

  final ProcessItemUseCase Function() _processItem;
  final ProcessingStateRepository Function() _processingStates;
  final AppLogger _logger;

  final _queue = Queue<String>();

  /// El que se está procesando ahora mismo.
  ///
  /// Se lleva aparte de [_queue] porque el elemento en curso ya salió de
  /// ella: mirar solo la cola daría por nuevo algo que en ese instante se
  /// está descargando.
  String? _current;

  var _isDraining = false;
  var _isDisposed = false;

  /// Si ya se recuperó lo que quedó a medias de una sesión anterior. Una vez
  /// por cola: lo que está "en curso" después de eso lo está de verdad, en
  /// esta sesión.
  var _recoveredInterrupted = false;

  /// Suma un elemento a la cola y arranca si no estaba andando.
  void enqueue(String itemId) {
    // Sin esta comprobación, capturar algo y volver a abrir la app encolaría
    // dos veces lo mismo y se descargaría dos veces.
    if (itemId == _current || _queue.contains(itemId)) return;

    _queue.add(itemId);

    // Lo que acaba de entrar cambia cuántos faltan. Sin este refresco, vaciar
    // una lista de diez pendientes mostraría "faltan 0" hasta que terminara
    // el primero, porque el contador solo se publica al sacar el siguiente de
    // la cola.
    final current = state;
    if (current is QueueWorking) {
      state = ProcessingQueueState.working(
        currentItemId: current.currentItemId,
        remaining: _queue.length,
      );
    }

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
        final current = _current;
        final interrupted = await states.recoverInterrupted(
          maxAttempts: maxInterruptedAttempts,
          inFlight: {?current},
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

  Future<void> _drain() async {
    if (_isDraining) return;
    _isDraining = true;

    try {
      while (_queue.isNotEmpty && !_isDisposed) {
        final itemId = _queue.removeFirst();
        _current = itemId;
        state = ProcessingQueueState.working(
          currentItemId: itemId,
          remaining: _queue.length,
        );

        try {
          // El caso de uso no lanza: traduce cualquier fallo a un `Left` y
          // deja el elemento marcado. Es lo que permite que un enlace roto no
          // corte la cola y los demás sigan procesándose.
          final result = await _processItem()(itemId);
          result.match(
            (failure) => _logger.warning('Quedó pendiente $itemId: $failure'),
            (_) {},
          );
          // Red de seguridad por si algo lanza igual —armar el caso de uso,
          // por ejemplo—: un solo elemento nunca puede cortar la cola.
          // ignore: avoid_catches_without_on_clauses
        } catch (e, stackTrace) {
          _logger.error('La cola no pudo procesar $itemId.', e, stackTrace);
        } finally {
          _current = null;
        }
      }
    } finally {
      _isDraining = false;
      if (!_isDisposed) state = const ProcessingQueueState.idle();
    }
  }

  @override
  void dispose() {
    // Corta el bucle en el próximo turno: sin esto, un `drain` en curso
    // seguiría escribiendo estado sobre un notifier ya descartado.
    _isDisposed = true;
    _queue.clear();
    super.dispose();
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
      );
    });
