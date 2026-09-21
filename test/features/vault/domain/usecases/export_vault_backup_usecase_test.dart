import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/entities/built_vault_backup.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_export_result.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_target.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';
import 'package:sinapsis/features/vault/domain/usecases/export_vault_backup_usecase.dart';

/// Lo que pasó y en qué orden: dónde guardar, armar, guardar, soltar.
class _Log {
  final events = <String>[];
}

class _Service implements VaultBackupService {
  _Service(this._log);

  final _Log _log;
  Exception? buildThrows;

  @override
  Future<BuiltVaultBackup> buildBackupFile() async {
    _log.events.add('armar');
    final error = buildThrows;
    if (error != null) throw error;
    return const BuiltVaultBackup(
      path: '/trabajo/sinapsis-backup-x/copia.zip',
      sizeBytes: 913 * 1024 * 1024,
    );
  }

  @override
  Future<void> discardBackup(BuiltVaultBackup backup) async {
    _log.events.add('soltar ${backup.path}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Gateway implements VaultBackupFileGateway {
  _Gateway(this._log);

  final _Log _log;
  VaultBackupTarget? target = const VaultBackupTarget(
    location: 'content://tree/primary%3ADownload',
    fileName: 'elegido.zip',
  );
  Exception? saveThrows;
  String? askedFileName;
  String? savedFrom;
  VaultBackupTarget? savedTo;

  @override
  Future<VaultBackupTarget?> chooseTarget({required String fileName}) async {
    _log.events.add('elegir');
    askedFileName = fileName;
    return target;
  }

  @override
  Future<String> save({
    required VaultBackupTarget target,
    required String sourcePath,
  }) async {
    _log.events.add('guardar');
    savedFrom = sourcePath;
    savedTo = target;
    final error = saveThrows;
    if (error != null) throw error;
    return 'primary:Download/${target.fileName}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Exportar la copia (F12): se elige DÓNDE antes de armarla —armar una bóveda
/// grande lleva minutos y cancelar el selector no puede costar eso—, la copia
/// se arma y se guarda desde un archivo, y el temporal se suelta pase lo que
/// pase.
void main() {
  late _Log log;
  late _Service service;
  late _Gateway gateway;

  setUp(() {
    log = _Log();
    service = _Service(log);
    gateway = _Gateway(log);
  });

  ExportVaultBackupUseCase useCase() => ExportVaultBackupUseCase(
    backupService: service,
    gateway: gateway,
    clock: () => DateTime(2026, 9, 21, 13, 5, 7),
  );

  test('elige dónde ANTES de armar, arma, guarda y suelta', () async {
    final result = (await useCase()(const NoParams())).getRight().toNullable()!;

    expect(log.events, [
      'elegir',
      'armar',
      'guardar',
      'soltar /trabajo/sinapsis-backup-x/copia.zip',
    ]);
    expect(
      result,
      const VaultBackupExportResult.completed(
        path: 'primary:Download/elegido.zip',
        sizeBytes: 913 * 1024 * 1024,
      ),
    );
  });

  test('guarda lo que armó, en lo que se eligió', () async {
    await useCase()(const NoParams());

    expect(gateway.savedFrom, '/trabajo/sinapsis-backup-x/copia.zip');
    expect(gateway.savedTo, gateway.target);
  });

  test('propone un nombre con la fecha y la hora', () async {
    await useCase()(const NoParams());

    expect(gateway.askedFileName, 'sinapsis-backup-20260921-130507.zip');
  });

  test('si se cancela el selector, no arma nada: no cuesta minutos', () async {
    gateway.target = null;

    final result = (await useCase()(const NoParams())).getRight().toNullable()!;

    expect(result, const VaultBackupExportResult.cancelled());
    expect(log.events, ['elegir']);
  });

  test('si armarla falla, es un fallo de exportación y no se guarda', () async {
    service.buildThrows = const FileSystemException('sin espacio');

    final either = await useCase()(const NoParams());

    expect(either.isLeft(), isTrue);
    expect(either.getLeft().toNullable(), isA<Failure>());
    expect(log.events, ['elegir', 'armar']);
  });

  test(
    'si guardarla falla, es un fallo, y el temporal se suelta igual',
    () async {
      gateway.saveThrows = const FormatException('carpeta sin permiso');

      final either = await useCase()(const NoParams());

      expect(either.isLeft(), isTrue);
      expect(log.events.last, 'soltar /trabajo/sinapsis-backup-x/copia.zip');
    },
  );
}
