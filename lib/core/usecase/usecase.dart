import 'package:cristo_es_el_salvador/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

/// Contrato que debe implementar cada caso de uso de `domain`.
/// [ResultType] es el resultado exitoso, [Params] los argumentos de entrada.
///
/// Se define como abstract class (en vez de un typedef de función) para que
/// cada caso de uso quede como un tipo nombrado e inyectable por Riverpod.
// ignore: one_member_abstracts
abstract interface class UseCase<ResultType, Params> {
  Future<Either<Failure, ResultType>> call(Params params);
}

/// Marcador para casos de uso que no requieren parámetros.
final class NoParams {
  const NoParams();
}
