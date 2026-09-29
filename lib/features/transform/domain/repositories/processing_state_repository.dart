import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';

/// Los cambios de estado del procesamiento de una fuente, como operaciones
/// puntuales sobre la base.
///
/// Existe aparte de `LibraryRepository.save` a propósito: marcar "en curso" o
/// "fallido" guardando el elemento entero escribía la foto que se tenía en la
/// mano, y con ella pisaba cualquier cosa que el usuario hubiera cambiado
/// mientras tanto. Acá solo se tocan las columnas del procesamiento.
///
/// Los métodos lanzan si la base falla: quien los llama —la cola y el caso de
/// uso que procesa— ya atrapa cualquier error para que nunca corte la cola.
abstract interface class ProcessingStateRepository {
  /// Marca [itemId] en curso, borra el motivo de un fallo anterior y cuenta
  /// un intento más. Devuelve cuántos intentos lleva, contando este.
  Future<int> begin(String itemId);

  /// Marca [itemId] fallido por [reason]. Conserva los intentos.
  Future<void> fail(String itemId, ProcessingFailureReason reason);

  /// Tras un procesamiento exitoso: sin motivo de fallo y sin intentos.
  Future<void> succeed(String itemId);

  /// Deja [itemId] en espera desde cero —sin motivo ni intentos—, para que
  /// un reintento pedido por el usuario tenga sus propios intentos.
  Future<void> requeue(String itemId);

  /// Lo que quedó en curso de una sesión anterior: la app se cerró, o el
  /// sistema la congeló o la mató, a mitad de procesarlo.
  ///
  /// Vuelve a dejarlo en espera y devuelve los que no están en la papelera,
  /// en orden de captura. El que ya llevaba [maxAttempts] intentos pasa a
  /// fallido con [ProcessingFailureReason.interrupted] en vez de volver: si
  /// es él el que hace caer la app, reintentarlo en cada arranque sería un
  /// bucle. Los de [inFlight] —en curso en ESTA sesión— no se tocan.
  Future<List<String>> recoverInterrupted({
    required int maxAttempts,
    Set<String> inFlight = const {},
  });

  /// Lo que está en espera y no está en la papelera, en orden de captura.
  Future<List<String>> pendingIds();
}
