import 'dart:async';

/// La señal para abandonar el procesamiento de un elemento: se lo mandó a la
/// papelera, o se lo borró para siempre, mientras se procesaba.
///
/// Sin ella la cola seguía esperando lo que el usuario ya había descartado:
/// borrar el video trabado no destrababa nada (F21). Con ella la cola lo
/// suelta en el acto y pasa al siguiente; lo que quedó corriendo termina solo
/// —cada pedido a la red tiene su límite— y su resultado se descarta. El
/// trabajo largo que va por partes —transcribir por tramos, reconocer página
/// por página— la consulta entre parte y parte para cortar de verdad.
class CancellationSignal {
  final _cancelled = Completer<void>();

  /// Si ya se pidió abandonar.
  bool get isCancelled => _cancelled.isCompleted;

  /// Se completa cuando se pide abandonar.
  Future<void> get whenCancelled => _cancelled.future;

  /// Pide abandonar. Pedirlo dos veces no hace nada más.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  /// Lanza [ProcessingCancelledException] si ya se pidió abandonar: el punto
  /// de corte entre una parte y la siguiente del trabajo largo.
  void throwIfCancelled() {
    if (isCancelled) throw const ProcessingCancelledException();
  }
}

/// Se abandonó el procesamiento de un elemento porque se lo borró. No es un
/// fallo: el elemento no queda "fallido", queda en espera por si se lo
/// restaura.
class ProcessingCancelledException implements Exception {
  const ProcessingCancelledException();

  @override
  String toString() => 'Se abandonó el procesamiento: el elemento se borró.';
}

/// [source], hasta que [whenCancelled] se complete: entonces lanza
/// [ProcessingCancelledException] en el acto —aunque no esté llegando nada—
/// y deja de leer [source].
///
/// Soltar [source] NO se espera, ni al cancelar ni cuando quien lee deja de
/// leer: cancelar una descarga trabada esperando una respuesta que no llega,
/// o un motor nativo a mitad de un tramo, no se completa hasta que esa
/// espera termine —o nunca—, y quien lee no suelta lo que tenga a medias
/// hasta que la cancelación se complete. El origen se cierra solo cuando
/// despierta.
Stream<T> cancellableStream<T>(Stream<T> source, Future<void> whenCancelled) {
  late final StreamController<T> controller;
  StreamSubscription<T>? subscription;

  void release() {
    final released = subscription?.cancel();
    subscription = null;
    if (released != null) unawaited(released);
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      unawaited(
        whenCancelled.then((_) {
          if (controller.isClosed) return;
          release();
          controller.addError(const ProcessingCancelledException());
          unawaited(controller.close());
        }),
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: release,
  );
  return controller.stream;
}
