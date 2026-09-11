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

  const factory Failure.unexpected({required String message}) =
      UnexpectedFailure;
}
