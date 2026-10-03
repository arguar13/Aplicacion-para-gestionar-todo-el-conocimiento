import 'dart:async';
import 'dart:isolate';

import 'process_memory.dart';

export 'process_memory.dart' show MemoryMeasure;

/// Mide el pico de memoria del proceso MIENTRAS otro aislado —el de la prueba—
/// trabaja.
///
/// Se muestrea desde un aislado aparte a propósito: lo que se quiere medir es
/// justamente el trabajo que bloquea al aislado que lo hace —descomprimir una
/// entrada a disco es síncrono—, y un temporizador en ese mismo aislado no
/// correría hasta que terminara.
///
/// La memoria residente es del proceso entero, no del aislado, así que sirve
/// para el trabajo de cualquiera: el de este, o el de una base que corre en
/// su propio aislado.
class RssSampler {
  RssSampler._({
    required SendPort control,
    required ReceivePort result,
    required this.baseline,
  }) : _control = control,
       _result = result;

  final SendPort _control;
  final ReceivePort _result;

  /// La memoria residente al empezar, en bytes.
  final int baseline;

  /// Empieza a muestrear. Lo que se cree antes de llamarlo cuenta como punto
  /// de partida, no como crecimiento.
  ///
  /// [measure] elige qué memoria: la residente, la de siempre en las cifras
  /// de rendimiento, o la privada comprometida, la que hay que usar para
  /// afirmar que algo no pasó entero por la memoria —ver [MemoryMeasure]—.
  static Future<RssSampler> start({
    Duration every = const Duration(milliseconds: 2),
    MemoryMeasure measure = MemoryMeasure.residentSet,
  }) async {
    final ready = ReceivePort();
    final result = ReceivePort();
    await Isolate.spawn(_sample, (
      ready.sendPort,
      result.sendPort,
      every,
      measure,
    ));
    final control = await ready.first as SendPort;
    // El aislado ya nació: su costo no cuenta como crecimiento de lo medido.
    return RssSampler._(
      control: control,
      result: result,
      baseline: processMemory(measure),
    );
  }

  /// Termina y devuelve cuánto creció la memoria del proceso, como máximo,
  /// desde que empezó.
  Future<int> stop() async {
    _control.send(null);
    final peak = await _result.first as int;
    _result.close();
    return peak - baseline;
  }
}

void _sample((SendPort, SendPort, Duration, MemoryMeasure) args) {
  final (ready, result, every, measure) = args;
  final control = ReceivePort();
  var peak = processMemory(measure);

  void look() {
    final now = processMemory(measure);
    if (now > peak) peak = now;
  }

  final timer = Timer.periodic(every, (_) => look());
  control.listen((_) {
    timer.cancel();
    look();
    result.send(peak);
    control.close();
  });
  ready.send(control.sendPort);
}
