import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';

/// Suelta lo que el selector dejó al elegir una copia: en el teléfono, una
/// copia entera del `.zip` en el almacenamiento temporal de la app, que no
/// tiene por qué quedarse ahí una vez fusionada —o descartada—.
///
/// Es un paso aparte de fusionar porque la pantalla lo pide en cada final
/// posible —se fusionó, no servía, se canceló— y ninguno de esos casos de uso
/// tiene por qué saber del almacenamiento del selector.
class DiscardPickedVaultBackupUseCase implements UseCase<Unit, NoParams> {
  const DiscardPickedVaultBackupUseCase({
    required VaultBackupFileGateway gateway,
  }) : _gateway = gateway;

  final VaultBackupFileGateway _gateway;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    await _gateway.discardPicked();
    return right(unit);
  }
}
