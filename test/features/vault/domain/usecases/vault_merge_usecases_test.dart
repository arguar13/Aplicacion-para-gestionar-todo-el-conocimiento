import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/schema_too_old_exception.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/vault/domain/entities/built_vault_backup.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_outcome.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview_outcome.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_rejection.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_result.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';
import 'package:sinapsis/features/vault/domain/usecases/merge_vault_backup_usecase.dart';
import 'package:sinapsis/features/vault/domain/usecases/preview_vault_merge_usecase.dart';

/// Los dos pasos de traer una copia (F11): ver qué traería y fusionarla.
///
/// Lo esperable no es un fallo sino un valor: una copia que no sirve, o una
/// fusión que se revirtió por una compuerta, son cosas que pasan y que el
/// usuario tiene que poder leer. Fallo es lo inesperado: el disco, la base.
class _Boom implements Exception {
  @override
  String toString() => 'Boom';
}

class _Service implements VaultBackupService {
  Exception? previewThrows;
  Exception? mergeThrows;
  VaultMergePreview preview = const VaultMergePreview(
    incomingItems: 1,
    newSources: 1,
    newNotes: 0,
    commonItems: 0,
  );
  VaultMergeResult result = const VaultMergeResult(itemsAdded: 1);
  String? previewed;
  String? merged;

  @override
  Future<VaultMergePreview> previewMerge(String zipPath) async {
    previewed = zipPath;
    final error = previewThrows;
    if (error != null) throw error;
    return preview;
  }

  @override
  Future<VaultMergeResult> mergeBackup(String zipPath) async {
    merged = zipPath;
    final error = mergeThrows;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<Uint8List> buildBackup() => throw UnimplementedError();

  @override
  Future<BuiltVaultBackup> buildBackupFile() => throw UnimplementedError();

  @override
  Future<void> discardBackup(BuiltVaultBackup backup) =>
      throw UnimplementedError();

  @override
  Future<bool> isValidBackup(String zipPath) => throw UnimplementedError();
}

void main() {
  const path = '/copias/sinapsis-backup.zip';
  late _Service service;

  setUp(() => service = _Service());

  group('PreviewVaultMergeUseCase', () {
    PreviewVaultMergeUseCase useCase() =>
        PreviewVaultMergeUseCase(backupService: service);

    test('una copia que se puede leer vuelve con lo que traería', () async {
      final outcome = (await useCase()(path)).getRight().toNullable()!;

      expect(outcome, isA<VaultMergePreviewReady>());
      expect((outcome as VaultMergePreviewReady).preview, service.preview);
      expect(service.previewed, path);
    });

    test(
      'de una versión más nueva: rechazada, con las dos versiones',
      () async {
        service.previewThrows = const VaultBackupTooNewException(
          backupVersion: 99,
          currentVersion: 20,
        );

        final outcome = (await useCase()(path)).getRight().toNullable()!;

        expect(
          outcome,
          const VaultMergePreviewOutcome.rejected(
            rejection: VaultMergeRejection.tooNew(
              backupVersion: 99,
              currentVersion: 20,
            ),
          ),
        );
      },
    );

    test('demasiado vieja: rechazada, con la versión mínima', () async {
      service.previewThrows = const SchemaTooOldException(
        from: 12,
        minimum: 15,
      );

      final outcome = (await useCase()(path)).getRight().toNullable()!;

      expect(
        outcome,
        const VaultMergePreviewOutcome.rejected(
          rejection: VaultMergeRejection.tooOld(
            backupVersion: 12,
            minimumVersion: 15,
          ),
        ),
      );
    });

    test('que no es una copia: rechazada', () async {
      service.previewThrows = const InvalidVaultBackupException('no');

      final outcome = (await useCase()(path)).getRight().toNullable()!;

      expect(
        outcome,
        const VaultMergePreviewOutcome.rejected(
          rejection: VaultMergeRejection.invalid(),
        ),
      );
    });

    test('lo inesperado es un fallo, no un rechazo', () async {
      service.previewThrows = _Boom();

      final either = await useCase()(path);

      expect(either.isLeft(), isTrue);
      expect(either.getLeft().toNullable(), isA<UnexpectedFailure>());
    });
  });

  group('MergeVaultBackupUseCase', () {
    MergeVaultBackupUseCase useCase() =>
        MergeVaultBackupUseCase(backupService: service);

    test('fusionada: vuelve con lo que se hizo', () async {
      service.result = const VaultMergeResult(itemsAdded: 4, itemsUpdated: 2);

      final outcome = (await useCase()(path)).getRight().toNullable()!;

      expect(
        outcome,
        const VaultMergeOutcome.merged(
          result: VaultMergeResult(itemsAdded: 4, itemsUpdated: 2),
        ),
      );
      expect(service.merged, path);
    });

    test('una compuerta que revierte: es un valor, con su nombre', () async {
      service.mergeThrows = const VaultMergeGateException('counts', 'achicó');

      final outcome = (await useCase()(path)).getRight().toNullable()!;

      expect(outcome, const VaultMergeOutcome.reverted(gate: 'counts'));
    });

    test('una copia que no sirve, en cualquiera de sus tres formas', () async {
      final cases = <Exception, VaultMergeRejection>{
        const VaultBackupTooNewException(
          backupVersion: 30,
          currentVersion: 20,
        ): const VaultMergeRejection.tooNew(
          backupVersion: 30,
          currentVersion: 20,
        ),
        const SchemaTooOldException(
          from: 10,
          minimum: 15,
        ): const VaultMergeRejection.tooOld(
          backupVersion: 10,
          minimumVersion: 15,
        ),
        const InvalidVaultBackupException('x'):
            const VaultMergeRejection.invalid(),
      };
      for (final entry in cases.entries) {
        service.mergeThrows = entry.key;

        final outcome = (await useCase()(path)).getRight().toNullable()!;

        expect(
          outcome,
          VaultMergeOutcome.rejected(rejection: entry.value),
          reason: '${entry.key}',
        );
      }
    });

    test('lo inesperado es un fallo', () async {
      service.mergeThrows = _Boom();

      final either = await useCase()(path);

      expect(either.isLeft(), isTrue);
      expect(either.getLeft().toNullable(), isA<UnexpectedFailure>());
    });
  });
}
