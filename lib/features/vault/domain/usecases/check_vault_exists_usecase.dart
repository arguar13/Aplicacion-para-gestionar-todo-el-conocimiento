import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/repositories/vault_repository.dart';

/// ¿Hay una bóveda creada en este dispositivo?
///
/// Es la primera pregunta que hace la app al arrancar: de la respuesta
/// depende si el usuario va a crear la bóveda o a desbloquearla.
class CheckVaultExistsUseCase implements UseCase<bool, NoParams> {
  const CheckVaultExistsUseCase(this._repository);

  final VaultRepository _repository;

  @override
  Future<Either<Failure, bool>> call(NoParams params) => _repository.exists();
}
