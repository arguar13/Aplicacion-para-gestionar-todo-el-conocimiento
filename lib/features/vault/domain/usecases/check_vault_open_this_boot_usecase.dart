import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/repositories/vault_repository.dart';

/// Si la bóveda quedó abierta en este encendido del dispositivo, para entrar
/// sin pedir la clave. Ver [VaultRepository.isOpenThisBoot].
class CheckVaultOpenThisBootUseCase implements UseCase<bool, NoParams> {
  const CheckVaultOpenThisBootUseCase(this._repository);

  final VaultRepository _repository;

  @override
  Future<Either<Failure, bool>> call(NoParams params) =>
      _repository.isOpenThisBoot();
}
