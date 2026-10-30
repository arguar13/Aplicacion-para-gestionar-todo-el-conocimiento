import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/export/presentation/providers/marked_download_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_view_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_download_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Borrar la copia del original, quedarme con el texto» (F41, decisión K):
/// qué hacer al tocarlo, o `null` si no se ofrece.
///
/// Es lo que en la fuente era «Borrar archivo, quedarme con el texto», que
/// salió de ahí porque de la Biblioteca nada se borra (decisión G): acá libera
/// el espacio de la copia propia (decisión H) y **nunca** toca el archivo de
/// la fuente. Ver `DropOriginalCopy`: sin sección Texto, el texto se guarda
/// ahí antes, para que el documento no quede mudo.
///
/// No se ofrece sin copia, ni con la fuente en la papelera o borrada: procesar
/// se arma contra la fuente viva, y sin ella la copia es lo único que queda de
/// su original. No pregunta antes —como soltar un archivo en la fuente—: la
/// copia va a la papelera de la app y el aviso trae «Deshacer».
VoidCallback? deleteOriginalCopyAction(
  BuildContext context,
  WidgetRef ref,
  ProcessedDocument document,
) {
  final source = document.source;
  final original = ref
      .watch(processedOriginalProvider(document.id))
      .valueOrNull;
  if (original == null || source == null || source.inTrash) return null;
  return () => unawaited(_dropOriginalCopy(context, source.itemId));
}

Future<void> _dropOriginalCopy(
  BuildContext context,
  String sourceItemId,
) async {
  final l10n = AppLocalizations.of(context)!;
  // Lo que se usa después de esperar se toma ahora: el aviso puede tocarse
  // cuando la pantalla ya no está.
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final process = container.read(processSourceUseCaseProvider);
  final result = await container.read(dropOriginalCopyProvider)(sourceItemId);
  messenger.hideCurrentSnackBar();
  result.match(
    (failure) => messenger.showSnackBar(
      SnackBar(content: Text(failure.localizedMessage(l10n))),
    ),
    (dropped) {
      // El texto con que se estudia cambia de la copia a las páginas.
      container.invalidate(processedStudyTextProvider);
      messenger.showSnackBar(
        AppSnackBar(
          content: Text(
            dropped.keptText
                ? l10n.processedOriginalCopyDroppedKeptText
                : l10n.processedOriginalCopyDropped,
          ),
          action: SnackBarAction(
            label: l10n.contentTrashUndo,
            onPressed: () async {
              final undone = await process.undo(dropped.outcome.undo);
              container.invalidate(processedStudyTextProvider);
              undone.match(
                (failure) => messenger.showSnackBar(
                  SnackBar(content: Text(failure.localizedMessage(l10n))),
                ),
                (_) {},
              );
            },
          ),
        ),
      );
    },
  );
}

/// «Descargar con lo marcado» (F38; F45, paso 3): qué hacer al tocarlo, o
/// `null` si no se ofrece.
///
/// Es el «Descargar» de la tarjeta «Estudiar el documento» de la Biblioteca,
/// que salió (F45, paso 3): ahí se marcaba el original de la fuente, y ahora
/// se marca la copia del original del documento procesado. Baja esa copia en
/// su formato con el resumen, la síntesis y las palabras clave del procesado
/// resaltados, con la misma hoja de siempre (`showStudyDownloadSheet`), que
/// arranca con lo que se ve resaltado.
///
/// Se ofrece con la copia, con su texto en correspondencia —lo marcado se
/// pinta sobre él— y en un formato que se sabe marcar.
VoidCallback? downloadMarkedOriginalAction(
  BuildContext context,
  WidgetRef ref,
  ProcessedDocument document,
) {
  final original = ref
      .watch(processedOriginalProvider(document.id))
      .valueOrNull;
  if (original == null) return null;
  final text = watchProcessedOriginalView(ref, document.id).valueOrNull?.text;
  final item = ref.watch(libraryItemProvider(document.id)).valueOrNull;
  if (text == null || item == null) return null;
  final kind = document.summary.sourceKind;
  final format = ref
      .watch(
        markedDownloadFormatProvider((kind: kind, path: original.relativePath)),
      )
      .valueOrNull;
  if (format == null) return null;
  // Lo que baja es la copia: su archivo, con el nombre del documento y el
  // formato de la fuente de la que salió.
  final copy = item.copyWith(
    source: item.source.copyWith(
      kind: kind,
      originalFilePath: original.relativePath,
    ),
  );
  return () => unawaited(
    showStudyDownloadSheet(context, item: copy, text: text, format: format),
  );
}

/// Lo que se baja o se suelta de un documento procesado, a un toque más (F41,
/// decisión K): lo que no crea nada. Lo que se crea —también organizar y
/// buscar fechas con la IA, que estaban acá— va en «Crear» (F45, paso 7b,
/// mejora 14).
enum ProcessedMoreAction {
  /// Ver [downloadMarkedOriginalAction].
  downloadMarkedOriginal,

  /// Ver [deleteOriginalCopyAction].
  deleteOriginalCopy,
}

/// «Más» en la barra del documento procesado. Sin nada que ofrecer, no se
/// dibuja.
class ProcessedMoreMenu extends ConsumerWidget {
  const ProcessedMoreMenu({required this.document, super.key});

  final ProcessedDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final download = downloadMarkedOriginalAction(context, ref, document);
    final deleteCopy = deleteOriginalCopyAction(context, ref, document);
    final actions = [
      if (download != null) ProcessedMoreAction.downloadMarkedOriginal,
      if (deleteCopy != null) ProcessedMoreAction.deleteOriginalCopy,
    ];
    if (actions.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<ProcessedMoreAction>(
      key: const Key('processed-more'),
      tooltip: l10n.sourcePanelMoreTitle,
      onSelected: (action) => unawaited(switch (action) {
        ProcessedMoreAction.downloadMarkedOriginal => Future.sync(
          () => download!(),
        ),
        ProcessedMoreAction.deleteOriginalCopy => Future.sync(
          () => deleteCopy!(),
        ),
      }),
      itemBuilder: (context) => [
        for (final action in actions)
          PopupMenuItem(
            key: Key('processed-more-${action.name}'),
            value: action,
            child: _MenuRow(action: action),
          ),
      ],
    );
  }
}

/// Una opción de «Más»: ícono, nombre y para qué sirve. Sin `ListTile`: las
/// pruebas del documento cuentan filas por ese widget.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.action});

  final ProcessedMoreAction action;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final (icon, title, hint) = switch (action) {
      ProcessedMoreAction.downloadMarkedOriginal => (
        Icons.download_outlined,
        l10n.f45S3DownloadMarked,
        l10n.f45S3DownloadMarkedHint,
      ),
      ProcessedMoreAction.deleteOriginalCopy => (
        Icons.delete_sweep_outlined,
        l10n.processedDeleteOriginalCopy,
        l10n.processedDeleteOriginalCopyHint,
      ),
    };
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
