import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_file_pick.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';
import 'package:sinapsis/features/vault/domain/usecases/discard_picked_vault_backup_usecase.dart';
import 'package:sinapsis/features/vault/domain/usecases/pick_vault_backup_file_usecase.dart';

import '../../../../support/fake_vault_backup_file_gateway.dart';

class _Service implements VaultBackupService {
  _Service({this.valid = true});

  final bool valid;
  final checked = <String>[];

  @override
  Future<bool> isValidBackup(String zipPath) async {
    checked.add(zipPath);
    return valid;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Elegir la copia y soltar lo que el selector dejó (F12): la copia se lee del
/// disco, por su ruta, y el archivo que el selector armó en el teléfono no se
/// queda ahí después de usarlo.
void main() {
  late FakeVaultBackupFileGateway gateway;

  setUp(() => gateway = FakeVaultBackupFileGateway());

  group('PickVaultBackupFileUseCase', () {
    PickVaultBackupFileUseCase useCase(_Service service) =>
        PickVaultBackupFileUseCase(backupService: service, gateway: gateway);

    test(
      'una copia válida vuelve con su ruta, y no se suelta todavía',
      () async {
        final service = _Service();

        final pick = (await useCase(service)(
          const NoParams(),
        )).getRight().toNullable()!;

        expect(pick, const VaultBackupFilePick.selected(path: '/copias/a.zip'));
        expect(service.checked, ['/copias/a.zip']);
        // Falta fusionarla: la pantalla la suelta al terminar.
        expect(gateway.discards, 0);
      },
    );

    test('cancelar el selector no comprueba nada ni suelta nada', () async {
      gateway.picked = null;
      final service = _Service();

      final pick = (await useCase(service)(
        const NoParams(),
      )).getRight().toNullable()!;

      expect(pick, const VaultBackupFilePick.cancelled());
      expect(service.checked, isEmpty);
      expect(gateway.discards, 0);
    });

    test(
      'un archivo que no sirve se suelta en el momento: no se va a usar',
      () async {
        final service = _Service(valid: false);

        final pick = (await useCase(service)(
          const NoParams(),
        )).getRight().toNullable()!;

        expect(pick, const VaultBackupFilePick.invalid());
        expect(gateway.discards, 1);
      },
    );
  });

  group('DiscardPickedVaultBackupUseCase', () {
    test('le pide al selector que suelte lo que dejó', () async {
      final useCase = DiscardPickedVaultBackupUseCase(gateway: gateway);

      final result = await useCase(const NoParams());

      expect(result.isRight(), isTrue);
      expect(gateway.discards, 1);
    });
  });
}
