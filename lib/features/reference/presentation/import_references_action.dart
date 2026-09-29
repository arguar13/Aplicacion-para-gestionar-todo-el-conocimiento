import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_import_report.dart';
import 'package:sinapsis/features/reference/presentation/providers/reference_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Importa un `.bib` o un `.ris` (F15, D9/D13/D14): abre el selector con
/// varios a la vez —el archivo y sus PDFs adjuntos, elegidos juntos—, lo
/// importa entero y muestra el informe.
///
/// Cancelar el selector no avisa nada: es la respuesta más común, como en
/// cualquier otro selector de archivos de la app.
Future<void> importReferences(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  final List<CapturedFile> files;
  try {
    files = await ref.read(fileChooserProvider).pickMany();
  } on FileAccessDeniedException {
    if (!context.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.captureFileAccessDenied)));
    return;
  }
  if (files.isEmpty || !context.mounted) return;

  final result = await ref.read(importReferencesFileUseCaseProvider)(files);
  if (!context.mounted) return;

  final report = result.getRight().toNullable();
  if (report == null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.importReferencesFailed)));
    return;
  }

  final queue = ref.read(processingQueueProvider.notifier);
  for (final itemId in report.attachedItemIds) {
    queue.enqueue(itemId);
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _ImportReportDialog(report: report),
  );
}

class _ImportReportDialog extends StatelessWidget {
  const _ImportReportDialog({required this.report});

  final ReferenceImportReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.importReferencesReportTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.importReferencesCreatedCount(report.created)),
              Text(l10n.importReferencesUpdatedCount(report.updated)),
              Text(l10n.importReferencesUnchangedCount(report.unchanged)),
              Text(l10n.importReferencesAttachedCount(report.attached)),
              if (report.possibleDuplicates > 0)
                Text(
                  l10n.importReferencesDuplicatesCount(
                    report.possibleDuplicates,
                  ),
                ),
              if (report.skipped.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.importReferencesSkippedCount(report.skipped.length),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final skip in report.skipped)
                  Text(
                    l10n.importReferencesSkippedReason(skip.key, skip.reason),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.importReferencesCloseAction),
        ),
      ],
    );
  }
}
