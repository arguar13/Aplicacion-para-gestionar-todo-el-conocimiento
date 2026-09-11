import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/entities/unlock_result.dart';
import 'package:sinapsis/features/vault/domain/repositories/vault_repository.dart';

/// Intenta abrir la bóveda.
///
/// No valida la longitud del PIN antes de mandarlo: al desbloquear, un PIN
/// corto es simplemente un PIN equivocado, y tratarlo distinto le contaría
/// a quien lo intenta algo sobre la clave guardada. Además tiene que contar
/// como intento fallido igual que cualquier otro, para que el límite de
/// intentos no se pueda esquivar probando siempre claves demasiado cortas.
class UnlockVaultUseCase implements UseCase<UnlockResult, UnlockVaultParams> {
  const UnlockVaultUseCase(this._repository);

  final VaultRepository _repository;

  @override
  Future<Either<Failure, UnlockResult>> call(UnlockVaultParams params) =>
      _repository.unlock(pin: params.pin);
}

@immutable
final class UnlockVaultParams {
  const UnlockVaultParams({required this.pin});

  final String pin;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UnlockVaultParams && other.pin == pin);

  @override
  int get hashCode => pin.hashCode;
}
