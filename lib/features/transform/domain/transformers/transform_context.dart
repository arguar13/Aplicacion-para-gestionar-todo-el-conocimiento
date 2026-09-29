import 'dart:async';

import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Lo que un transformador recibe mientras trabaja: la cola que lo corre.
///
/// La cola tiene **dos carriles**, cada uno de a un elemento por vez: el
/// corto —traer una página, una publicación, los subtítulos de un video, el
/// texto que un documento ya trae— y el largo —transcribir horas de audio,
/// reconocer cientos de páginas escaneadas—. Todo arranca en el corto; lo
/// que tiene una parte larga pasa al largo con [enterLongLane], y en ese
/// momento libera el corto para el siguiente. Así un video de cuatro horas
/// nunca frena una página web (F21).
abstract interface class TransformContext {
  /// Un contexto sin cola: nunca se cancela, pasar al carril largo no espera
  /// nada y el avance no se publica en ningún lado. Lo que recibe un
  /// transformador que se usa por fuera de la cola —en una prueba, o a
  /// pedido—.
  static const TransformContext detached = _DetachedTransformContext();

  /// Si se pidió abandonar: el elemento se borró.
  bool get isCancelled;

  /// Se completa cuando se pide abandonar.
  Future<void> get whenCancelled;

  /// Lanza [ProcessingCancelledException] si se pidió abandonar: el punto de
  /// corte entre una parte y la siguiente del trabajo largo.
  void throwIfCancelled();

  /// Pasa al carril largo: libera el corto y espera su turno en el largo.
  ///
  /// Desde acá no rige el tope fijo del trabajo corto sino el de "sin
  /// avance": lo largo puede tardar horas mientras siga informando que
  /// avanza ([reportProgress]). Llamarlo dos veces no hace nada más.
  Future<void> enterLongLane();

  /// Informa cuánto va: [done] de [total] —páginas, segundos de audio—. Es
  /// lo que dibuja la barra de avance y lo que prueba que el trabajo largo
  /// sigue vivo.
  void reportProgress(int done, int total);
}

class _DetachedTransformContext implements TransformContext {
  const _DetachedTransformContext();

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => Completer<void>().future;

  @override
  void throwIfCancelled() {}

  @override
  Future<void> enterLongLane() async {}

  @override
  void reportProgress(int done, int total) {}
}

/// Un [TransformContext] sobre una [CancellationSignal], sin carriles: lo que
/// arma quien quiere cancelar algo que corre por fuera de la cola.
class CancellableTransformContext implements TransformContext {
  CancellableTransformContext(this.cancellation);

  final CancellationSignal cancellation;

  @override
  bool get isCancelled => cancellation.isCancelled;

  @override
  Future<void> get whenCancelled => cancellation.whenCancelled;

  @override
  void throwIfCancelled() => cancellation.throwIfCancelled();

  @override
  Future<void> enterLongLane() async {}

  @override
  void reportProgress(int done, int total) {}
}
