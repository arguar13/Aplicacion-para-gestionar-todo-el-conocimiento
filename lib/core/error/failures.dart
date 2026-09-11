import 'package:freezed_annotation/freezed_annotation.dart';

part 'failures.freezed.dart';

/// Errores de dominio devueltos por los `UseCase` como `Left(Failure)`.
/// Las capas `data` traducen sus `Exception`s a un [Failure] concreto en el
/// repositorio; `presentation` nunca ve un `Exception` ni un `DioException`.
@freezed
sealed class Failure with _$Failure {
  const factory Failure.server({required String message, int? statusCode}) =
      ServerFailure;

  const factory Failure.network({required String message}) = NetworkFailure;

  const factory Failure.unauthorized({required String message}) =
      UnauthorizedFailure;

  /// Rechazo de negocio del backend que no es "credenciales/sesión", sino
  /// un dato inválido en la petición (p. ej. registrar con un correo que
  /// ya existe). Distinta de [ServerFailure]: esta sí tiene un mensaje
  /// pensado para mostrarse tal cual en un campo del formulario.
  const factory Failure.validation({required String message}) =
      ValidationFailure;

  const factory Failure.cache({required String message}) = CacheFailure;

  /// Un archivo que no entra en memoria.
  ///
  /// Es su propia variante y no una [ValidationFailure] porque el usuario
  /// necesita saber **cuál** es el límite para poder hacer algo al respecto.
  /// Todas las validaciones comparten un solo mensaje traducido —"revisá los
  /// datos"— y frente a un video de un giga eso no explica nada ni sugiere
  /// qué hacer.
  const factory Failure.fileTooLarge({
    required String message,
    required int maxBytes,
  }) = FileTooLargeFailure;

  const factory Failure.unexpected({required String message}) =
      UnexpectedFailure;

  /// No se pudo escribir en una carpeta que el propio usuario eligió —
  /// exportar un paquete, guardar un archivo—.
  ///
  /// Aparte de [CacheFailure] porque el remedio es distinto: aquella es
  /// sobre el almacenamiento propio de la app, y acá lo único que tiene
  /// sentido sugerir es elegir otra carpeta o revisar sus permisos.
  const factory Failure.exportFailed({required String message}) =
      ExportFailedFailure;
}
