import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_export_result.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_file_pick.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_import_result.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_backup_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Exportar e importar la bóveda completa —la base y todos los archivos
/// originales—, para usar la misma en dos dispositivos sin sincronización
/// automática entre ellos. Ver la decisión 1 en docs/arquitectura.md: sin
/// servidor propio, el camino es manual a propósito.
class VaultBackupScreen extends ConsumerStatefulWidget {
  const VaultBackupScreen({super.key});

  @override
  ConsumerState<VaultBackupScreen> createState() => _VaultBackupScreenState();
}

class _VaultBackupScreenState extends ConsumerState<VaultBackupScreen> {
  var _exporting = false;
  var _importing = false;

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
                    icon: Icons.download_outlined,
                    title: l10n.vaultBackupImportSectionTitle,
                    explanation: l10n.vaultBackupImportExplanation,
                    child: _importing
                        ? _InProgress(label: l10n.vaultBackupImportInProgress)
                        : PrimaryButton(
                            label: l10n.vaultBackupImportAction,
                            onPressed: _import,
                          ),
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

  Future<void> _import() async {
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
        _showMessage(l10n.vaultBackupImportInvalidFile);
        return;
      case VaultBackupFileSelected(:final bytes):
        await _confirmAndRestore(bytes);
    }
  }

  Future<void> _confirmAndRestore(Uint8List bytes) async {
    final l10n = AppLocalizations.of(context)!;

    // Reemplazar toda la bóveda es irreversible: no hay papelera de la que
    // rescatarla, igual que borrar un elemento en el detalle.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.vaultBackupImportConfirmTitle),
        content: Text(l10n.vaultBackupImportConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.vaultBackupImportConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _importing = true);

    // La conexión que la app tiene abierta apunta al archivo que estamos
    // por reemplazar: hay que cerrarla antes de escribir encima, no
    // después. `invalidate` dispara `onDispose` (que cierra la conexión) y
    // deja el provider listo para abrir una nueva si algo lo lee de nuevo
    // antes de que la app termine de cerrarse.
    await ref.read(appDatabaseProvider).close();
    ref.invalidate(appDatabaseProvider);

    final result = await ref.read(restoreVaultBackupUseCaseProvider)(bytes);
    if (!mounted) return;
    setState(() => _importing = false);

    result.match(
      (failure) =>
          _showMessage(failure.localizedMessage(AppLocalizations.of(context)!)),
      (importResult) {
        if (importResult is! VaultBackupImportCompleted) return;
        _showRestoredDialog();
      },
    );
  }

  Future<void> _showRestoredDialog() async {
    final l10n = AppLocalizations.of(context)!;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.vaultBackupImportSuccessTitle),
        content: Text(l10n.vaultBackupImportSuccessMessage),
        actions: [
          TextButton(
            // La base que la app tenía abierta ya no existe: no hay forma
            // sana de seguir usando esta sesión sin reabrir el proceso
            // entero. Es la misma razón por la que un instalador de
            // Windows pide reiniciar después de reemplazar sus propios
            // archivos en uso.
            onPressed: () => exit(0),
            child: Text(l10n.vaultBackupImportCloseAppAction),
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
