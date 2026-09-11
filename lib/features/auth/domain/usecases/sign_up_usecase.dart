import 'package:cristo_es_el_salvador/core/domain/entities/user.dart';
import 'package:cristo_es_el_salvador/core/error/failures.dart';
import 'package:cristo_es_el_salvador/core/usecase/usecase.dart';
import 'package:cristo_es_el_salvador/features/auth/domain/repositories/auth_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';

class SignUpUseCase implements UseCase<User, SignUpParams> {
  const SignUpUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, User>> call(SignUpParams params) {
    return _repository.signUp(
      name: params.name,
      email: params.email,
      password: params.password,
    );
  }
}

/// No incluye `confirmPassword`: eso es una validación de UI/Notifier
/// (¿coinciden las dos contraseñas escritas?), no un dato que la API
/// necesite — `AuthRepository.signUp`/`SignUpRemoteDataSource` nunca lo
/// piden.
@immutable
final class SignUpParams {
  const SignUpParams({
    required this.name,
    required this.email,
    required this.password,
  });

  final String name;
  final String email;
  final String password;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignUpParams &&
          other.name == name &&
          other.email == email &&
          other.password == password);

  @override
  int get hashCode => Object.hash(name, email, password);
}
