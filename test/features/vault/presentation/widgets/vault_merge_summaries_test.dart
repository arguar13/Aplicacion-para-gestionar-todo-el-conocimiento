import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_rejection.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_result.dart';
import 'package:sinapsis/features/vault/presentation/widgets/vault_merge_summaries.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Lo que la pantalla le dice al usuario de una fusión (F11), como texto: qué
/// traería una copia, qué se hizo, y por qué una no sirve. En los dos idiomas.
void main() {
  final es = AppLocalizationsEs();
  final en = AppLocalizationsEn();

  const empty = VaultMergePreview(
    incomingItems: 0,
    newSources: 0,
    newNotes: 0,
    commonItems: 0,
  );

  group('lo que traería una copia', () {
    test('solo lo que no es cero', () {
      final lines = vaultMergePreviewLines(
        es,
        empty.copyWith(newSources: 2, newRelations: 3),
      );

      expect(lines, [
        es.vaultMergePreviewItems(2),
        es.vaultMergePreviewRelations(3),
      ]);
    });

    test('una copia que no trae nada no tiene renglones', () {
      expect(vaultMergePreviewLines(es, empty), isEmpty);
    });

    test('de lo más importante a lo menos', () {
      final lines = vaultMergePreviewLines(
        es,
        empty.copyWith(
          newSources: 1,
          itemsToUpdate: 1,
          conflicts: 1,
          newRenditions: 1,
          newRelations: 1,
          newHighlights: 1,
          newFlashcards: 1,
          newSpaces: 1,
          newPropertyValues: 1,
          newConversations: 1,
          newFiles: 1,
          newFilesBytes: 1024,
        ),
      );

      expect(lines, hasLength(11));
      expect(lines.first, es.vaultMergePreviewItems(1));
      expect(lines[1], es.vaultMergePreviewUpdated(1));
      expect(lines[2], es.vaultMergePreviewConflicts(1));
      expect(lines.last, contains('1 kB'));
    });

    test('el singular y el plural, en los dos idiomas', () {
      expect(es.vaultMergePreviewItems(1), '1 elemento nuevo');
      expect(es.vaultMergePreviewItems(5), '5 elementos nuevos');
      expect(en.vaultMergePreviewItems(1), '1 new item');
      expect(en.vaultMergePreviewItems(5), '5 new items');
    });

    test('un archivo lleva lo que pesa', () {
      final lines = vaultMergePreviewLines(
        en,
        empty.copyWith(newFiles: 3, newFilesBytes: 3 * 1024 * 1024),
      );

      expect(lines.single, en.vaultMergePreviewFiles(3, '3.0 MB'));
    });
  });

  group('lo que hizo la fusión', () {
    test('lo que se sumó, lo que cambió, los conflictos y los archivos', () {
      final lines = vaultMergeResultLines(
        es,
        const VaultMergeResult(
          itemsAdded: 3,
          itemsUpdated: 2,
          conflictsRecorded: 1,
          filesCopied: 4,
        ),
      );

      expect(lines, [
        es.vaultMergeDoneAdded(3),
        es.vaultMergeDoneUpdated(2),
        es.vaultMergeDoneConflicts(1),
        es.vaultMergeDoneFiles(4),
      ]);
    });

    test('lo que es cero no se cuenta, salvo lo que se sumó', () {
      final lines = vaultMergeResultLines(
        es,
        const VaultMergeResult(conflictsRecorded: 2),
      );

      expect(lines, [es.vaultMergeDoneAdded(0), es.vaultMergeDoneConflicts(2)]);
    });

    test('una fusión que no cambió nada lo dice', () {
      expect(vaultMergeResultLines(es, const VaultMergeResult()), [
        es.vaultMergeDoneNothing,
      ]);
    });
  });

  group('por qué una copia no sirve', () {
    test('una versión más nueva dice las dos versiones', () {
      const rejection = VaultMergeRejection.tooNew(
        backupVersion: 99,
        currentVersion: 20,
      );

      final message = vaultMergeRejectionMessage(es, rejection);

      expect(message, contains('v99'));
      expect(message, contains('v20'));
      expect(message, contains('No se cambió nada'));
      expect(vaultMergeRejectionMessage(en, rejection), contains('v99'));
    });

    test('una demasiado vieja dice la mínima', () {
      const rejection = VaultMergeRejection.tooOld(
        backupVersion: 12,
        minimumVersion: 15,
      );

      final message = vaultMergeRejectionMessage(es, rejection);

      expect(message, contains('v12'));
      expect(message, contains('v15'));
    });

    test('la que no es una copia', () {
      const rejection = VaultMergeRejection.invalid();

      expect(
        vaultMergeRejectionMessage(es, rejection),
        es.vaultMergeInvalidFile,
      );
      expect(
        vaultMergeRejectionMessage(en, rejection),
        en.vaultMergeInvalidFile,
      );
    });
  });

  test('ningún texto habla ya de reemplazar ni de reiniciar', () {
    for (final l10n in [es, en]) {
      final all = [
        l10n.vaultMergeSectionTitle,
        l10n.vaultMergeExplanation,
        l10n.vaultMergeAction,
        l10n.vaultMergePreviewSafety,
        l10n.vaultMergeDoneTitle,
      ].join(' ').toLowerCase();

      expect(all, isNot(contains('reemplaz')));
      expect(all, isNot(contains('replace')));
      expect(all, isNot(contains('reinici')));
      expect(all, isNot(contains('restart')));
    }
  });
}
