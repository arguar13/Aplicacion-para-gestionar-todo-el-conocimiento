import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
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
class ProcessingQueueNotifier extends StateNotifier<ProcessingQueueState> {
  ProcessingQueueNotifier({
    required ProcessItemUseCase processItem,
    required LibraryRepository repository,
    required AppLogger logger,
  }) : _processItem = processItem,
       _repository = repository,
       _logger = logger,
       super(const ProcessingQueueState.idle());

  final ProcessItemUseCase _processItem;
  final LibraryRepository _repository;
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

  /// Encola todo lo que quedó esperando de sesiones anteriores.
  ///
  /// Se llama al abrir la app: alguien pudo capturar cinco enlaces sin
  /// conexión y cerrar; al volver, eso tiene que completarse solo, sin que
  /// haya que acordarse de pedirlo.
  ///
  /// Los que fallaron NO entran acá. Un fallo puede ser permanente —un video
  /// borrado, una página que ya no existe— y reintentarlo en cada arranque
  /// sería gastar batería y datos para volver a fallar. Se reintentan a
  /// pedido, desde el elemento.
  Future<void> enqueuePending() async {
    final result = await _repository.list(
      const LibraryQuery(processingStates: {ProcessingState.pending}),
    );

    result.match(
      (failure) => _logger.error('No se pudo leer lo pendiente.', failure),
      (items) {
        for (final item in items) {
          enqueue(item.id);
        }
      },
    );
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
          final result = await _processItem(itemId);
          result.match(
            (failure) => _logger.warning('Quedó pendiente $itemId: $failure'),
            (_) {},
          );
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
final processingQueueProvider =
    StateNotifierProvider<ProcessingQueueNotifier, ProcessingQueueState>((ref) {
      return ProcessingQueueNotifier(
        processItem: ref.watch(processItemUseCaseProvider),
        repository: ref.watch(libraryRepositoryProvider),
        logger: ref.watch(appLoggerProvider),
      );
    });
