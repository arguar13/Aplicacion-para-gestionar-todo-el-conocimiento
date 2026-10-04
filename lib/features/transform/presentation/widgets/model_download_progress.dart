import 'package:flutter/material.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El avance de la descarga de un modelo, igual en las tres pantallas
/// —lenguaje, relaciones, transcripción—: la barra, cuánto va, si sigue con
/// la app cerrada y cómo cancelarla (F29).
///
/// Cancelar se confirma: borra lo bajado, y en el modelo de lenguaje son
/// gigas que llevó una hora traer.
class ModelDownloadProgress extends StatelessWidget {
  const ModelDownloadProgress({
    required this.progress,
    required this.label,
    required this.continuesWithAppClosed,
    required this.onCancel,
    super.key,
  });

  /// De 0 a 1.
  final double progress;

  /// "Descargando… 47 %", con el texto de cada pantalla.
  final String label;

  /// Si la baja el gestor del sistema: entonces se puede cerrar la app.
  final bool continuesWithAppClosed;

  final VoidCallback onCancel;

  Future<void> _confirmCancel(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.modelDownloadCancelTitle),
        content: Text(l10n.modelDownloadCancelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.modelDownloadKeepGoing),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.modelDownloadCancel),
          ),
        ],
      ),
    );
    if (confirmed ?? false) onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 16),
        Text(label),
        if (continuesWithAppClosed) ...[
          const SizedBox(height: 8),
          Text(
            l10n.modelDownloadContinuesClosed,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextButton.icon(
          key: const Key('model-download-cancel'),
          onPressed: () => _confirmCancel(context),
          icon: const Icon(Icons.close),
          label: Text(l10n.modelDownloadCancel),
        ),
      ],
    );
  }
}

/// El texto para una descarga que no tuvo lugar en el dispositivo, o `null`
/// si [error] es otra cosa: cada pantalla dice lo suyo para el resto.
String? modelDownloadSpaceMessage(AppLocalizations l10n, Object error) {
  if (error is! InsufficientStorageException) return null;
  final required = error.requiredBytes;
  return required == null
      ? l10n.modelDownloadNoSpaceUnknown
      : l10n.modelDownloadNoSpace(formatFileSize(required, l10n.localeName));
}
