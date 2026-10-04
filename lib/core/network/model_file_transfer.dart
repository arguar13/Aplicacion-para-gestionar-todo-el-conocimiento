import 'dart:io';

import 'package:dio/dio.dart';

/// Cómo llega al dispositivo un archivo de modelo —de cientos de megas a
/// varios gigas— (F29).
///
/// Hay dos, detrás de esta misma interfaz:
///
/// - `SystemModelFileTransfer`, en Android: se lo pide al **gestor de
///   descargas del sistema**, que baja en su propio proceso. Sigue aunque se
///   cierre la app o se reinicie el teléfono, retoma solo y muestra su
///   notificación; la app, al volver, se engancha a la descarga en curso por
///   el número que dejó anotado.
/// - `InAppModelFileTransfer`, en el escritorio y en las pruebas: baja en el
///   proceso de la app, retomando por rango (`ResumableDownload`).
///
/// Las dos dejan el archivo entero con su nombre definitivo, y nunca un
/// archivo cortado con ese nombre.
abstract interface class ModelFileTransfer {
  /// Si la descarga sigue con la app cerrada: la hace el sistema, no la app,
  /// así que no hace falta mantener la app viva mientras dura.
  bool get continuesWithAppClosed;

  /// Lleva el archivo de [url] hasta [target], entero, y devuelve su tamaño.
  ///
  /// Quien llama dice que [target] **no** está entero: si existe con ese
  /// nombre —lo dejó una versión anterior, sin marca de terminado—, se toma
  /// como lo bajado hasta ahora o se descarta, según la transferencia.
  ///
  /// - Si ya hay una descarga de [target] en curso —en esta sesión o, con el
  ///   gestor del sistema, desde una anterior—, se engancha a esa: nunca hay
  ///   dos escribiendo el mismo archivo.
  /// - [expectedBytes], si se sabe, es lo que pesa entero: para saber si hay
  ///   lugar antes de empezar y para descartar lo que no coincide.
  /// - [verify] recibe el archivo entero antes de que tome su nombre
  ///   definitivo; si lanza, el archivo se borra y la descarga falla con eso.
  /// - [label] dice qué modelo es, para la notificación del sistema (ver
  ///   `LongWorkDetail`).
  ///
  /// Falla con [InsufficientStorageException] sin lugar, con
  /// [ModelDownloadHttpException] si el servidor dijo que no, con
  /// [ModelDownloadCancelledException] si se canceló ([cancel]), y con lo
  /// que lance la red o el disco.
  Future<int> fetch({
    required String url,
    required File target,
    Map<String, String> headers = const {},
    int? expectedBytes,
    String? label,
    Future<void> Function(File whole)? verify,
    void Function(int received, int? total)? onProgress,
  });

  /// Si hay una descarga de [target] en curso ahora: de esta sesión o, con
  /// el gestor del sistema, una que siguió con la app cerrada —terminada,
  /// fallada o a medias— que la app todavía no recogió.
  Future<bool> isInFlight(File target);

  /// Corta la descarga de [target], si hay una, y borra lo bajado: quien la
  /// estaba esperando recibe [ModelDownloadCancelledException].
  Future<void> cancel(File target);
}

/// No hay lugar para bajar el modelo: hacen falta [requiredBytes] y quedan
/// [availableBytes]. Cualquiera de los dos es `null` si no se sabe: cuando
/// lo dice el sistema a mitad de la descarga, sin decir cuánto.
class InsufficientStorageException implements Exception {
  const InsufficientStorageException({this.requiredBytes, this.availableBytes});

  final int? requiredBytes;
  final int? availableBytes;

  @override
  String toString() =>
      'Sin lugar para el modelo'
      '${requiredBytes == null ? '' : ': hacen falta $requiredBytes bytes'}'
      '${availableBytes == null ? '' : ' y quedan $availableBytes'}.';
}

/// El servidor contestó [statusCode] y no hay vuelta: 401/403 —repositorio
/// protegido, token vencido—, 404, o lo que quede después de que el gestor
/// del sistema agotó sus reintentos.
class ModelDownloadHttpException implements Exception {
  const ModelDownloadHttpException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'El servidor contestó $statusCode.';
}

/// La descarga se canceló a pedido: no es un error que mostrar.
class ModelDownloadCancelledException implements Exception {
  const ModelDownloadCancelledException();

  @override
  String toString() => 'Descarga cancelada.';
}

/// La descarga falló por algo que no es del servidor ni de lugar —el
/// sistema no pudo retomarla, o se perdió—: se puede volver a intentar.
class ModelDownloadFailedException implements Exception {
  const ModelDownloadFailedException(this.detail);

  /// Solo para el registro, nunca para mostrar.
  final String detail;

  @override
  String toString() => 'La descarga falló: $detail.';
}

/// Si [error] dice que hace falta autenticarse para bajar el modelo: un 401
/// o un 403, de la descarga en la app (dio) o de la del sistema.
bool isModelDownloadAuthError(Object error) {
  final status = switch (error) {
    DioException(:final response?) => response.statusCode,
    ModelDownloadHttpException(:final statusCode) => statusCode,
    _ => null,
  };
  return status == 401 || status == 403;
}
