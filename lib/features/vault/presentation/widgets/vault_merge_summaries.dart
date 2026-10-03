import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_rejection.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_result.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que traería una copia, en renglones para mostrarle al usuario antes de
/// fusionarla (F11): solo lo que no es cero, de lo más importante a lo menos.
List<String> vaultMergePreviewLines(
  AppLocalizations l10n,
  VaultMergePreview preview,
) => [
  if (preview.newItems > 0) l10n.vaultMergePreviewItems(preview.newItems),
  if (preview.itemsToUpdate > 0)
    l10n.vaultMergePreviewUpdated(preview.itemsToUpdate),
  if (preview.conflicts > 0) l10n.vaultMergePreviewConflicts(preview.conflicts),
  if (preview.newRenditions > 0)
    l10n.vaultMergePreviewRenditions(preview.newRenditions),
  if (preview.newRelations > 0)
    l10n.vaultMergePreviewRelations(preview.newRelations),
  if (preview.newHighlights > 0)
    l10n.vaultMergePreviewHighlights(preview.newHighlights),
  if (preview.newFlashcards > 0)
    l10n.vaultMergePreviewFlashcards(preview.newFlashcards),
  if (preview.newSpaces > 0) l10n.vaultMergePreviewSpaces(preview.newSpaces),
  if (preview.newPropertyValues > 0)
    l10n.vaultMergePreviewValues(preview.newPropertyValues),
  if (preview.newConversations > 0)
    l10n.vaultMergePreviewConversations(preview.newConversations),
  if (preview.newFiles > 0)
    l10n.vaultMergePreviewFiles(
      preview.newFiles,
      formatFileSize(preview.newFilesBytes, l10n.localeName),
    ),
];

/// Lo que hizo una fusión, en renglones para mostrar cuando termina.
List<String> vaultMergeResultLines(
  AppLocalizations l10n,
  VaultMergeResult result,
) {
  if (result.changedNothing) return [l10n.vaultMergeDoneNothing];
  return [
    l10n.vaultMergeDoneAdded(result.itemsAdded),
    if (result.itemsUpdated > 0)
      l10n.vaultMergeDoneUpdated(result.itemsUpdated),
    if (result.conflictsRecorded > 0)
      l10n.vaultMergeDoneConflicts(result.conflictsRecorded),
    if (result.filesCopied > 0) l10n.vaultMergeDoneFiles(result.filesCopied),
  ];
}

/// Por qué una copia no se puede fusionar, dicho para el usuario.
String vaultMergeRejectionMessage(
  AppLocalizations l10n,
  VaultMergeRejection rejection,
) => switch (rejection) {
  VaultMergeTooNew(:final backupVersion, :final currentVersion) =>
    l10n.vaultMergeTooNew(backupVersion, currentVersion),
  VaultMergeTooOld(:final backupVersion, :final minimumVersion) =>
    l10n.vaultMergeTooOld(backupVersion, minimumVersion),
  VaultMergeInvalid() => l10n.vaultMergeInvalidFile,
};
