import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/schema_too_old_exception.dart';
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
  Future<VaultMergePreview> Function(Uint8List) onPreview = (_) async =>
      const VaultMergePreview(
        incomingItems: 3,
        newSources: 2,
        newNotes: 1,
        commonItems: 0,
      );
  Future<VaultMergeResult> Function(Uint8List) onMerge = (_) async =>
      const VaultMergeResult(itemsAdded: 3);

  final previews = <Uint8List>[];
  final merges = <Uint8List>[];

  @override
  Future<Uint8List> buildBackup() async => Uint8List(0);

  @override
  Future<bool> isValidBackup(Uint8List zipBytes) async => valid;

  @override
  Future<VaultMergePreview> previewMerge(Uint8List zipBytes) {
    previews.add(zipBytes);
    return onPreview(zipBytes);
  }

  @override
  Future<VaultMergeResult> mergeBackup(Uint8List zipBytes) {
    merges.add(zipBytes);
    return onMerge(zipBytes);
  }
}

class _FakeGateway implements VaultBackupFileGateway {
  Uint8List? picked = Uint8List.fromList([1, 2, 3]);

  @override
  Future<Uint8List?> pickZip() async => picked;

  @override
  Future<String?> saveZip({
    required String fileName,
    required Uint8List bytes,
  }) async => null;
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
