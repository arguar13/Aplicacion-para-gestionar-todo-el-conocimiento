import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/user.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/auth/domain/repositories/auth_repository.dart';

class LoginUseCase implements UseCase<User, LoginParams> {
  const LoginUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, User>> call(LoginParams params) {
    return _repository.login(email: params.email, password: params.password);
  }
}

@immutable
final class LoginParams {
  const LoginParams({required this.email, required this.password});

  final String email;
  final String password;

  // Igualdad de valor: sin esto, dos LoginParams con los mismos datos son
  // instancias distintas para `==`, lo que rompe el matching por valor de
  // mocktail en los tests (y cualquier otra comparación razonable).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LoginParams &&
          other.email == email &&
          other.password == password);

  @override
  int get hashCode => Object.hash(email, password);
}
