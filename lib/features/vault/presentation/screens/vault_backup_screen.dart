import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' show Left, Right;
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_export_result.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_file_pick.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_outcome.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview_outcome.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_result.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_backup_providers.dart';
import 'package:sinapsis/features/vault/presentation/widgets/vault_merge_summaries.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Hacer una copia de la bóveda completa —la base y todos los archivos
/// originales— y traer la de otro dispositivo, para usar la misma en dos sin
/// sincronización automática entre ellos. Ver la decisión 1 en
/// docs/arquitectura.md: sin servidor propio, el camino es manual a propósito.
///
/// Traer una copia es FUSIONAR (F11): lo nuevo se suma, lo que las dos tienen
/// se une, y nada de lo que hay se borra. Antes se reemplazaba la bóveda
/// entera y había que reiniciar la app; ahora se ve qué traería, se confirma,
/// y la app sigue como estaba, con lo nuevo.
class VaultBackupScreen extends ConsumerStatefulWidget {
  const VaultBackupScreen({super.key});

  @override
  ConsumerState<VaultBackupScreen> createState() => _VaultBackupScreenState();
}

/// Qué está haciendo la pantalla con la copia elegida.
enum _MergeStage { idle, reading, merging }

class _VaultBackupScreenState extends ConsumerState<VaultBackupScreen> {
  var _exporting = false;
  var _stage = _MergeStage.idle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.vaultBackupTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(
                    icon: Icons.upload_outlined,
                    title: l10n.vaultBackupExportSectionTitle,
                    explanation: l10n.vaultBackupExportExplanation,
                    child: _exporting
                        ? _InProgress(label: l10n.vaultBackupExportInProgress)
                        : PrimaryButton(
                            label: l10n.vaultBackupExportAction,
                            onPressed: _export,
                          ),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 32),
                  _Section(
                    icon: Icons.merge_type_outlined,
                    title: l10n.vaultMergeSectionTitle,
                    explanation: l10n.vaultMergeExplanation,
                    child: switch (_stage) {
                      _MergeStage.reading => _InProgress(
                        label: l10n.vaultMergeReading,
                      ),
                      _MergeStage.merging => _InProgress(
                        label: l10n.vaultMergeInProgress,
                      ),
                      _MergeStage.idle => PrimaryButton(
                        label: l10n.vaultMergeAction,
                        onPressed: _chooseCopy,
                      ),
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _exporting = true);

    final result = await ref.read(exportVaultBackupUseCaseProvider)(
      const NoParams(),
    );
    if (!mounted) return;
    setState(() => _exporting = false);

    result.match((failure) => _showMessage(failure.localizedMessage(l10n)), (
      exportResult,
    ) {
      // Cancelar el selector de guardado no es un error: se deja la
      // pantalla tal como estaba, por si quiere intentarlo de nuevo.
      if (exportResult is! VaultBackupExportCompleted) return;

      _showMessage(
        l10n.vaultBackupExportSuccess(
          exportResult.path,
          formatFileSize(exportResult.sizeBytes),
        ),
      );
    });
  }

  Future<void> _chooseCopy() async {
    final l10n = AppLocalizations.of(context)!;

    final pickResult = await ref.read(pickVaultBackupFileUseCaseProvider)(
      const NoParams(),
    );
    if (!mounted) return;

    final pick = pickResult.getOrElse(
      (failure) => const VaultBackupFilePick.cancelled(),
    );
    switch (pick) {
      case VaultBackupFileCancelled():
        return;
      case VaultBackupFileInvalid():
        _showMessage(l10n.vaultMergeInvalidFile);
        return;
      case VaultBackupFileSelected(:final bytes):
        await _previewAndMerge(bytes);
    }
  }

  /// Lee la copia, dice qué traería y —si el usuario confirma— la fusiona.
  Future<void> _previewAndMerge(Uint8List bytes) async {
    setState(() => _stage = _MergeStage.reading);
    final read = await ref.read(previewVaultMergeUseCaseProvider)(bytes);
    if (!mounted) return;
    setState(() => _stage = _MergeStage.idle);

    final l10n = AppLocalizations.of(context)!;
    final VaultMergePreview preview;
    switch (read) {
      case Left(:final value):
        _showMessage(value.localizedMessage(l10n));
        return;
      case Right(value: VaultMergePreviewRejected(:final rejection)):
        _showMessage(vaultMergeRejectionMessage(l10n, rejection));
        return;
      case Right(value: VaultMergePreviewReady(preview: final ready)):
        preview = ready;
    }

    if (preview.hasNothingNew) {
      await _showNothingNew();
      return;
    }
    final confirmed = await _confirmMerge(preview);
    if (confirmed != true || !mounted) return;

    setState(() => _stage = _MergeStage.merging);
    final merged = await ref.read(mergeVaultBackupUseCaseProvider)(bytes);
    if (!mounted) return;
    setState(() => _stage = _MergeStage.idle);

    final after = AppLocalizations.of(context)!;
    switch (merged) {
      case Left(:final value):
        _showMessage(value.localizedMessage(after));
      case Right(value: VaultMergeMerged(:final result)):
        await _showDone(result);
      case Right(value: VaultMergeRejected(:final rejection)):
        _showMessage(vaultMergeRejectionMessage(after, rejection));
      case Right(value: VaultMergeReverted(:final gate)):
        _showMessage(after.vaultMergeReverted(gate));
    }
  }

  /// El resumen de lo que traería la copia, con la garantía de que nada de lo
  /// que hay se borra.
  Future<bool?> _confirmMerge(VaultMergePreview preview) {
    final l10n = AppLocalizations.of(context)!;
    final lines = vaultMergePreviewLines(l10n, preview);

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.vaultMergePreviewTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('•  $line'),
                ),
              if (preview.filesMissingInBackup > 0) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.vaultMergePreviewFilesMissing(
                    preview.filesMissingInBackup,
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                l10n.vaultMergePreviewSafety,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.vaultMergeConfirmAction),
          ),
        ],
      ),
    );
  }

  Future<void> _showNothingNew() {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.vaultMergePreviewNothingTitle),
        content: Text(l10n.vaultMergePreviewNothingMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.vaultMergeDoneClose),
          ),
        ],
      ),
    );
  }

  Future<void> _showDone(VaultMergeResult result) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.vaultMergeDoneTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in vaultMergeResultLines(l10n, result))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line),
              ),
          ],
        ),
        actions: [
          // Los conflictos que quedaron guardados se revisan en su pantalla.
          if (result.conflictsRecorded > 0)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push(RoutePaths.conflicts);
              },
              child: Text(l10n.vaultMergeDoneReview),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.vaultMergeDoneClose),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.explanation,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String explanation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          explanation,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _InProgress extends StatelessWidget {
  const _InProgress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 16),
        Text(label),
      ],
    );
  }
}
