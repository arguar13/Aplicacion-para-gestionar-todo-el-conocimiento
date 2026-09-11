import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/user.dart';
import 'package:sinapsis/core/error/failures.dart';

/// Contrato del dominio: `data` lo implementa, `presentation` solo conoce
/// esta interfaz (a través de `LoginUseCase`/`SignUpUseCase`), nunca
/// `AuthRepositoryImpl`.
abstract interface class AuthRepository {
  Future<Either<Failure, User>> login({
    required String email,
    required String password,
  });

  Future<Either<Failure, User>> signUp({
    required String name,
    required String email,
    required String password,
  });
}
