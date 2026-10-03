import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/schema_too_old_exception.dart';
import 'package:sinapsis/features/vault/domain/entities/built_vault_backup.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_target.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_result.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_backup_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/vault_backup_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// La pantalla de copia de seguridad (F11): traer una copia es FUSIONAR.
/// Se elige el archivo, se ve qué traería, se confirma, y la app sigue como
/// estaba —sin cerrar la base ni reiniciar—, con lo nuevo.
class _FakeService implements VaultBackupService {
  bool valid = true;
  Future<VaultMergePreview> Function(String) onPreview = (_) async =>
      const VaultMergePreview(
        incomingItems: 3,
        newSources: 2,
        newNotes: 1,
        commonItems: 0,
      );
  Future<VaultMergeResult> Function(String) onMerge = (_) async =>
      const VaultMergeResult(itemsAdded: 3);

  final previews = <String>[];
  final merges = <String>[];

  Exception? buildThrows;

  /// Si la prueba lo pone, armar la copia espera a que se complete.
  Completer<void>? buildHold;
  final discarded = <String>[];

  @override
  Future<BuiltVaultBackup> buildBackupFile() async {
    await buildHold?.future;
    final error = buildThrows;
    if (error != null) throw error;
    return const BuiltVaultBackup(
      path: '/tmp/sinapsis-backup-x/copia.zip',
      sizeBytes: 913 * 1024 * 1024,
    );
  }

  @override
  Future<void> discardBackup(BuiltVaultBackup backup) async {
    discarded.add(backup.path);
  }

  @override
  Future<bool> isValidBackup(String zipPath) async => valid;

  @override
  Future<VaultMergePreview> previewMerge(String zipPath) {
    previews.add(zipPath);
    return onPreview(zipPath);
  }

  @override
  Future<VaultMergeResult> mergeBackup(String zipPath) {
    merges.add(zipPath);
    return onMerge(zipPath);
  }
}

class _FakeGateway implements VaultBackupFileGateway {
  String? picked = '/copias/sinapsis-backup.zip';

  /// Cuántas veces se soltó lo que el selector dejó.
  int discards = 0;

  @override
  Future<String?> pickZip() async => picked;

  @override
  Future<void> discardPicked() async => discards++;

  /// Lo que el usuario elige al guardar; `null` es cancelar el selector.
  VaultBackupTarget? target = const VaultBackupTarget(
    location: '/elegido/copia.zip',
    fileName: 'copia.zip',
  );
  Exception? saveThrows;
  final saved = <String>[];

  @override
  Future<VaultBackupTarget?> chooseTarget({required String fileName}) async =>
      target;

  @override
  Future<String> save({
    required VaultBackupTarget target,
    required String sourcePath,
  }) async {
    final error = saveThrows;
    if (error != null) throw error;
    saved.add(sourcePath);
    return target.location;
  }
}

void main() {
  final es = AppLocalizationsEs();
  late _FakeService service;
  late _FakeGateway gateway;

  setUp(() {
    service = _FakeService();
    gateway = _FakeGateway();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultBackupServiceProvider.overrideWithValue(service),
          vaultBackupFileGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: VaultBackupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapChoose(WidgetTester tester) async {
    await tester.tap(find.text(es.vaultMergeAction));
    await tester.pumpAndSettle();
  }

  group('la pantalla', () {
    testWidgets('ofrece traer una copia, no restaurarla', (tester) async {
      await pumpScreen(tester);

      expect(find.text(es.vaultMergeSectionTitle), findsOneWidget);
      expect(find.text(es.vaultMergeAction), findsOneWidget);
      // Sin el «reemplaza todo» de antes.
      expect(find.textContaining('Restaurar'), findsNothing);
      expect(find.textContaining('reemplaza'), findsNothing);
    });
  });

  group('elegir la copia', () {
    testWidgets('cancelar el selector no hace nada', (tester) async {
      gateway.picked = null;
      await pumpScreen(tester);

      await tapChoose(tester);

      expect(service.previews, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('un archivo que no es una copia lo dice, y no la lee', (
      tester,
    ) async {
      service.valid = false;
      await pumpScreen(tester);

      await tapChoose(tester);

      expect(find.text(es.vaultMergeInvalidFile), findsOneWidget);
      expect(service.previews, isEmpty);
    });
  });

  group('una copia que no sirve', () {
    testWidgets('de una versión más nueva: dice cuál y qué hacer', (
      tester,
    ) async {
      service.onPreview = (_) async => throw const VaultBackupTooNewException(
        backupVersion: 99,
        currentVersion: 20,
      );
      await pumpScreen(tester);

      await tapChoose(tester);

      expect(find.text(es.vaultMergeTooNew(99, 20)), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.merges, isEmpty);
    });

    testWidgets('demasiado vieja', (tester) async {
      service.onPreview = (_) async =>
          throw const SchemaTooOldException(from: 12, minimum: 15);
      await pumpScreen(tester);

      await tapChoose(tester);

      expect(find.text(es.vaultMergeTooOld(12, 15)), findsOneWidget);
    });

    testWidgets('que no es una copia', (tester) async {
      service.onPreview = (_) async =>
          throw const InvalidVaultBackupException('no');
      await pumpScreen(tester);

      await tapChoose(tester);

      expect(find.text(es.vaultMergeInvalidFile), findsOneWidget);
    });

    testWidgets('un fallo inesperado al leerla', (tester) async {
      service.onPreview = (_) async => throw StateError('disco');
      await pumpScreen(tester);

      await tapChoose(tester);

      expect(find.text(es.globalErrorUnexpected), findsOneWidget);
      expect(service.merges, isEmpty);
    });
  });

  group('la vista previa', () {
    testWidgets('una copia que no trae nada no se ofrece fusionar', (
      tester,
    ) async {
      service.onPreview = (_) async => const VaultMergePreview(
        incomingItems: 2,
        newSources: 0,
        newNotes: 0,
        commonItems: 2,
      );
      await pumpScreen(tester);

      await tapChoose(tester);

      expect(find.text(es.vaultMergePreviewNothingTitle), findsOneWidget);
      expect(find.text(es.vaultMergeConfirmAction), findsNothing);
      expect(service.merges, isEmpty);
    });

    testWidgets(
      'muestra qué traería, con la garantía de que no se borra nada',
      (tester) async {
        service.onPreview = (_) async => const VaultMergePreview(
          incomingItems: 5,
          newSources: 2,
          newNotes: 1,
          commonItems: 2,
          itemsToUpdate: 2,
          fieldsToUpdate: 3,
          conflicts: 1,
          newRelations: 4,
          newFiles: 2,
          newFilesBytes: 2048,
        );
        await pumpScreen(tester);

        await tapChoose(tester);

        expect(find.text(es.vaultMergePreviewTitle), findsOneWidget);
        expect(
          find.textContaining(es.vaultMergePreviewItems(3)),
          findsOneWidget,
        );
        expect(
          find.textContaining(es.vaultMergePreviewUpdated(2)),
          findsOneWidget,
        );
        expect(
          find.textContaining(es.vaultMergePreviewConflicts(1)),
          findsOneWidget,
        );
        expect(
          find.textContaining(es.vaultMergePreviewRelations(4)),
          findsOneWidget,
        );
        expect(find.textContaining('2 archivos originales'), findsOneWidget);
        expect(find.text(es.vaultMergePreviewSafety), findsOneWidget);
        // Lo que es cero no aparece.
        expect(find.textContaining('resaltado'), findsNothing);
        expect(find.textContaining('tarjeta'), findsNothing);
      },
    );

    testWidgets('avisa de los archivos que la copia menciona y no trae', (
      tester,
    ) async {
      service.onPreview = (_) async => const VaultMergePreview(
        incomingItems: 1,
        newSources: 1,
        newNotes: 0,
        commonItems: 0,
        filesMissingInBackup: 2,
      );
      await pumpScreen(tester);

      await tapChoose(tester);

      expect(find.text(es.vaultMergePreviewFilesMissing(2)), findsOneWidget);
    });

    testWidgets('cancelar no fusiona nada', (tester) async {
      await pumpScreen(tester);
      await tapChoose(tester);

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(service.previews, hasLength(1));
      expect(service.merges, isEmpty);
      expect(find.text(es.vaultMergeAction), findsOneWidget);
    });
  });

  group('exportar (F12)', () {
    Future<void> tapExport(WidgetTester tester) async {
      await tester.tap(find.text(es.vaultBackupExportAction));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'guarda desde el archivo que armó, y dice dónde y cuánto pesa',
      (tester) async {
        await pumpScreen(tester);

        await tapExport(tester);

        expect(gateway.saved, ['/tmp/sinapsis-backup-x/copia.zip']);
        expect(
          find.text(
            es.vaultBackupExportSuccess('/elegido/copia.zip', '913,0 MB'),
          ),
          findsOneWidget,
        );
        // Y el archivo temporal se suelta.
        expect(service.discarded, ['/tmp/sinapsis-backup-x/copia.zip']);
      },
    );

    testWidgets('si se cancela el selector, no arma nada ni avisa', (
      tester,
    ) async {
      gateway.target = null;
      await pumpScreen(tester);

      await tapExport(tester);

      expect(gateway.saved, isEmpty);
      expect(service.discarded, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(es.vaultBackupExportAction), findsOneWidget);
    });

    testWidgets('mientras arma, lo dice y no deja empezar otra', (
      tester,
    ) async {
      service.buildHold = Completer<void>();
      await pumpScreen(tester);

      await tester.tap(find.text(es.vaultBackupExportAction));
      await tester.pump();

      expect(find.text(es.vaultBackupExportInProgress), findsOneWidget);
      expect(find.text(es.vaultBackupExportAction), findsNothing);

      service.buildHold!.complete();
      await tester.pumpAndSettle();

      expect(find.text(es.vaultBackupExportInProgress), findsNothing);
      expect(gateway.saved, hasLength(1));
    });

    testWidgets('si armarla falla, lo dice y no guarda nada', (tester) async {
      service.buildThrows = const FileSystemException('sin espacio');
      await pumpScreen(tester);

      await tapExport(tester);

      expect(gateway.saved, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
      // Y se puede volver a intentar.
      expect(find.text(es.vaultBackupExportAction), findsOneWidget);
    });

    testWidgets('si guardarla falla, lo dice y suelta la copia igual', (
      tester,
    ) async {
      gateway.saveThrows = const FileSystemException('carpeta sin permiso');
      await pumpScreen(tester);

      await tapExport(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(service.discarded, ['/tmp/sinapsis-backup-x/copia.zip']);
    });
  });

  group('suelta la copia que dejó el selector (F12)', () {
    testWidgets('al fusionar', (tester) async {
      await pumpScreen(tester);
      await tapChoose(tester);
      expect(gateway.discards, 0, reason: 'todavía hay que decidir');

      await tester.tap(find.text(es.vaultMergeConfirmAction));
      await tester.pumpAndSettle();

      expect(service.merges, [gateway.picked]);
      expect(gateway.discards, 1);
    });

    testWidgets('al cancelar la confirmación', (tester) async {
      await pumpScreen(tester);
      await tapChoose(tester);

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(service.merges, isEmpty);
      expect(gateway.discards, 1);
    });

    testWidgets('cuando la copia no trae nada nuevo', (tester) async {
      service.onPreview = (_) async => const VaultMergePreview(
        incomingItems: 1,
        newSources: 0,
        newNotes: 0,
        commonItems: 1,
      );
      await pumpScreen(tester);

      await tapChoose(tester);

      expect(gateway.discards, 1);
    });

    testWidgets('cuando la copia se rechaza', (tester) async {
      service.onPreview = (_) async => throw const VaultBackupTooNewException(
        backupVersion: 99,
        currentVersion: 20,
      );
      await pumpScreen(tester);

      await tapChoose(tester);

      expect(gateway.discards, 1);
    });

    testWidgets('cuando la fusión falla', (tester) async {
      service.onMerge = (_) async => throw StateError('disco lleno');
      await pumpScreen(tester);
      await tapChoose(tester);

      await tester.tap(find.text(es.vaultMergeConfirmAction));
      await tester.pumpAndSettle();

      expect(gateway.discards, 1);
    });

    testWidgets('con un archivo que no es una copia, en el momento', (
      tester,
    ) async {
      service.valid = false;
      await pumpScreen(tester);

      await tapChoose(tester);

      expect(gateway.discards, 1);
      expect(service.previews, isEmpty);
    });

    testWidgets('si se cancela el selector no hay nada que soltar', (
      tester,
    ) async {
      gateway.picked = null;
      await pumpScreen(tester);

      await tapChoose(tester);

      expect(gateway.discards, 0);
    });
  });

  group('fusionar', () {
    testWidgets('confirmar fusiona esa misma copia y muestra lo que se hizo', (
      tester,
    ) async {
      service.onMerge = (_) async => const VaultMergeResult(
        itemsAdded: 3,
        itemsUpdated: 2,
        conflictsRecorded: 1,
        filesCopied: 4,
      );
      await pumpScreen(tester);
      await tapChoose(tester);

      await tester.tap(find.text(es.vaultMergeConfirmAction));
      await tester.pumpAndSettle();

      expect(service.merges, [gateway.picked]);
      expect(find.text(es.vaultMergeDoneTitle), findsOneWidget);
      expect(find.text(es.vaultMergeDoneAdded(3)), findsOneWidget);
      expect(find.text(es.vaultMergeDoneUpdated(2)), findsOneWidget);
      expect(find.text(es.vaultMergeDoneConflicts(1)), findsOneWidget);
      expect(find.text(es.vaultMergeDoneFiles(4)), findsOneWidget);
    });

    testWidgets(
      'la app sigue como estaba: se cierra el resultado y la pantalla queda',
      (tester) async {
        await pumpScreen(tester);
        await tapChoose(tester);
        await tester.tap(find.text(es.vaultMergeConfirmAction));
        await tester.pumpAndSettle();

        await tester.tap(find.text(es.vaultMergeDoneClose));
        await tester.pumpAndSettle();

        // Sin «cerrar Sinapsis»: no hay reinicio, ni base reemplazada.
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(VaultBackupScreen), findsOneWidget);
        expect(find.text(es.vaultMergeAction), findsOneWidget);
        expect(find.textContaining('Cerrar Sinapsis'), findsNothing);
      },
    );

    testWidgets(
      'con conflictos guardados ofrece revisarlos y va a su pantalla',
      (tester) async {
        service.onMerge = (_) async =>
            const VaultMergeResult(itemsAdded: 1, conflictsRecorded: 2);
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const VaultBackupScreen()),
            GoRoute(
              path: RoutePaths.conflicts,
              builder: (_, _) => const Scaffold(body: Text('LOS CONFLICTOS')),
            ),
          ],
        );
        addTearDown(router.dispose);
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              vaultBackupServiceProvider.overrideWithValue(service),
              vaultBackupFileGatewayProvider.overrideWithValue(gateway),
            ],
            child: MaterialApp.router(
              locale: const Locale('es'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapChoose(tester);
        await tester.tap(find.text(es.vaultMergeConfirmAction));
        await tester.pumpAndSettle();

        expect(find.text(es.vaultMergeDoneConflicts(2)), findsOneWidget);
        await tester.tap(find.text(es.vaultMergeDoneReview));
        await tester.pumpAndSettle();

        expect(find.text('LOS CONFLICTOS'), findsOneWidget);
      },
    );

    testWidgets('sin conflictos no ofrece revisar nada', (tester) async {
      await pumpScreen(tester);
      await tapChoose(tester);

      await tester.tap(find.text(es.vaultMergeConfirmAction));
      await tester.pumpAndSettle();

      expect(find.text(es.vaultMergeDoneReview), findsNothing);
    });

    testWidgets('mientras fusiona lo dice, y no deja empezar otra', (
      tester,
    ) async {
      final done = Completer<VaultMergeResult>();
      service.onMerge = (_) => done.future;
      await pumpScreen(tester);
      await tapChoose(tester);

      await tester.tap(find.text(es.vaultMergeConfirmAction));
      await tester.pump();

      expect(find.text(es.vaultMergeInProgress), findsOneWidget);
      expect(find.text(es.vaultMergeAction), findsNothing);

      done.complete(const VaultMergeResult(itemsAdded: 1));
      await tester.pumpAndSettle();
      expect(find.text(es.vaultMergeDoneTitle), findsOneWidget);
    });

    testWidgets('una compuerta que revierte la fusión: no se cambió nada', (
      tester,
    ) async {
      service.onMerge = (_) async =>
          throw const VaultMergeGateException('counts', 'una tabla achicó');
      await pumpScreen(tester);
      await tapChoose(tester);

      await tester.tap(find.text(es.vaultMergeConfirmAction));
      await tester.pumpAndSettle();

      expect(find.text(es.vaultMergeReverted('counts')), findsOneWidget);
      expect(find.text(es.vaultMergeDoneTitle), findsNothing);
      expect(find.text(es.vaultMergeAction), findsOneWidget);
    });

    testWidgets('un fallo inesperado al fusionar', (tester) async {
      service.onMerge = (_) async => throw StateError('disco lleno');
      await pumpScreen(tester);
      await tapChoose(tester);

      await tester.tap(find.text(es.vaultMergeConfirmAction));
      await tester.pumpAndSettle();

      expect(find.text(es.globalErrorUnexpected), findsOneWidget);
      expect(find.text(es.vaultMergeAction), findsOneWidget);
    });

    testWidgets(
      'si la copia deja de servir entre la vista previa y la fusión',
      (tester) async {
        service.onMerge = (_) async => throw const VaultBackupTooNewException(
          backupVersion: 30,
          currentVersion: 20,
        );
        await pumpScreen(tester);
        await tapChoose(tester);

        await tester.tap(find.text(es.vaultMergeConfirmAction));
        await tester.pumpAndSettle();

        expect(find.text(es.vaultMergeTooNew(30, 20)), findsOneWidget);
      },
    );
  });
}
