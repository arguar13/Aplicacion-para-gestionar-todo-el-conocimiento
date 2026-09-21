import 'package:sinapsis/features/vault/domain/entities/vault_backup_target.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';

/// El selector de archivos de la copia, sin selector: devuelve la ruta que la
/// prueba le diga y anota cuántas veces le pidieron soltar lo que dejó.
class FakeVaultBackupFileGateway implements VaultBackupFileGateway {
  String? picked = '/copias/a.zip';

  /// Cuántas veces se soltó lo que el selector dejó.
  int discards = 0;

  @override
  Future<String?> pickZip() async => picked;

  @override
  Future<void> discardPicked() async => discards++;

  @override
  Future<VaultBackupTarget?> chooseTarget({required String fileName}) async =>
      null;

  @override
  Future<String> save({
    required VaultBackupTarget target,
    required String sourcePath,
  }) async => target.location;
}
