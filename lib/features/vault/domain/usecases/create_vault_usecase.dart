import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/entities/pin_policy.dart';
import 'package:sinapsis/features/vault/domain/repositories/vault_repository.dart';

/// Crea la bóveda del dispositivo.
///
/// La comprobación de que las dos claves escritas coinciden vive acá y no
/// en la pantalla: es una regla de la operación, no de la interfaz. Una
/// pantalla distinta —o una prueba automatizada— tiene que toparse con la
/// misma exigencia sin volver a implementarla.
class CreateVaultUseCase implements UseCase<Unit, CreateVaultParams> {
  const CreateVaultUseCase(this._repository);

  final VaultRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(CreateVaultParams params) async {
    if (params.pin != params.confirmation) {
      return left(
        const Failure.validation(message: 'Las claves no coinciden.'),
      );
    }

    if (!PinPolicy.isValid(params.pin)) {
      return left(
        const Failure.validation(
          message: 'La clave no cumple la longitud mínima.',
        ),
      );
    }

    return _repository.create(pin: params.pin);
  }
}

@immutable
final class CreateVaultParams {
  const CreateVaultParams({required this.pin, required this.confirmation});

  final String pin;
  final String confirmation;

  // Igualdad por valor, igual que en el resto de los params de la app: sin
  // esto, dos instancias con los mismos datos son distintas para `==` y se
  // rompe el emparejamiento por valor de mocktail en los tests.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CreateVaultParams &&
          other.pin == pin &&
          other.confirmation == confirmation);

  @override
  int get hashCode => Object.hash(pin, confirmation);
}
