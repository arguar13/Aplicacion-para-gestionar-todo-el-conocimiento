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

  /// No hay internet: no se pudo ni llegar al proveedor (sin señal, sin datos,
  /// el nombre del servidor que no se resuelve).
  network,

  /// La espera venció: el proveedor no contestó a tiempo (o dejó de mandar
  /// datos) con la conexión andando. Pasa con textos largos o con el servicio
  /// lento; no es falta de internet.
  timeout,

  /// La respuesta se cortó a mitad: la conexión se cayó o el proveedor la
  /// cerró antes de terminarla. Se había llegado al proveedor.
  cutOff,

  /// El proveedor rechazó el pedido por mal armado (error 400) y no es la
  /// clave, el largo ni el modelo.
  badRequest,

  /// El pedido no entra en lo que el modelo lee de una vez.
  tooLong,

  /// No hay ninguna cuenta con clave para el proveedor elegido.
  noAccount,

  /// La IA de fondo llegó a su tope del día (`AiModelSettings
  /// .backgroundDailyCap`): lo que queda de cuota es para la persona.
  backgroundCap,

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

  /// Si es de los que pasan solos: probar de nuevo con la misma cuenta, un
  /// rato después, suele andar (F39). Lo demás —la clave, el pedido, la cuota
  /// del día— no cambia por esperar. El tope por minuto ([CloudModelFailure
  /// .rateLimited]) también pasa esperando, pero con la espera que pide el
  /// proveedor, así que lo trata aparte quien reintenta.
  bool get isTransient => switch (failure) {
    CloudModelFailure.network ||
    CloudModelFailure.timeout ||
    CloudModelFailure.cutOff ||
    CloudModelFailure.unavailable => true,
    _ => false,
  };

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
