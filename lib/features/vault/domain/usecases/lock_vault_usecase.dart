import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/repositories/vault_repository.dart';

/// "Bloquear bóveda": la próxima vez pide la clave. Ver
/// [VaultRepository.lock].
class LockVaultUseCase implements UseCase<Unit, NoParams> {
  const LockVaultUseCase(this._repository);

  final VaultRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) => _repository.lock();
}
