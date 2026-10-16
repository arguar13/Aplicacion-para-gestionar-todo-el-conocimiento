/// Por qué un proveedor en la nube no contestó (F32). Cada caso pide algo
/// distinto: cambiar de cuenta, esperar, revisar la clave o la conexión.
enum CloudModelFailure {
  /// La clave no sirve: está mal copiada, se borró o se revocó.
  invalidKey,

  /// La clave sirve pero no tiene permiso para este modelo o esta región.
  forbidden,

  /// Se pasó del tope por minuto: hay que esperar unos segundos.
  rateLimited,

  /// Se terminó la cuota del día (o el saldo, en los pagos): con esta cuenta
  /// no hay más hasta que se renueve.
  quotaExhausted,

  /// El modelo elegido ya no existe o no está disponible con esta clave.
  modelNotFound,

  /// El proveedor está saturado o falló de su lado: suele pasar solo.
  unavailable,

  /// El proveedor no quiso contestar por sus reglas de contenido.
  blocked,

  /// No hay internet, o se cortó a mitad.
  network,

  /// El pedido no entra en lo que el modelo lee de una vez.
  tooLong,

  /// No hay ninguna cuenta con clave para el proveedor elegido.
  noAccount,

  /// Algo que no se esperaba: lo que dijo el proveedor está en
  /// [CloudModelException.detail].
  unknown,
}

/// Un pedido a un proveedor en la nube que no se pudo completar.
class CloudModelException implements Exception {
  const CloudModelException(
    this.failure, {
    this.detail,
    this.retryAfter,
    this.statusCode,
  });

  final CloudModelFailure failure;

  /// Lo que dijo el proveedor, para el registro; nunca la clave.
  final String? detail;

  /// Cuánto pide esperar el proveedor antes de volver a probar, si lo dice.
  final Duration? retryAfter;

  final int? statusCode;

  /// Si conviene probar con otra cuenta del mismo proveedor.
  bool get otherAccountMayWork =>
      failure == CloudModelFailure.quotaExhausted ||
      failure == CloudModelFailure.invalidKey ||
      failure == CloudModelFailure.forbidden;

  @override
  String toString() =>
      'CloudModelException(${failure.name}'
      '${statusCode == null ? '' : ', $statusCode'}'
      '${detail == null ? '' : ': $detail'})';
}
