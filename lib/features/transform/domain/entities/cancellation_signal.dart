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
