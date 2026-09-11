import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/storage/file_opener.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/usecases/export_item_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/export/presentation/widgets/export_format_presentation.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/features/organize/presentation/widgets/relations_section.dart';
import 'package:sinapsis/features/organize/presentation/widgets/tag_editor.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un elemento por dentro: su contenido y, sobre todo, de dónde salió.
///
/// La procedencia tiene su propia sección con el mismo peso visual que el
/// contenido, y no es decoración: un texto sin origen sirve para leer, no
/// para trabajar. Poder volver al video, al artículo o al perfil de quien lo
/// escribió es la mitad del valor de haberlo guardado.
class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({required this.itemId, super.key});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final item = ref.watch(libraryItemProvider(itemId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          item.valueOrNull?.title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (item.valueOrNull != null) ...[
            _ExportButton(item: item.valueOrNull!),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.detailDelete,
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ],
      ),
      body: item.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _DetailError(error: error),
        data: (value) => value == null
            // El elemento dejó de existir — borrado acá o desde otro lado.
            // Se muestra un vacío breve mientras el `pop` de abajo saca de la
            // pantalla, en vez de seguir mostrando algo que ya no está.
            ? const SizedBox.shrink()
            : _DetailBody(item: value),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;

    // Borrar se lleva el contenido, la procedencia, los subrayados y las
    // notas, y no hay papelera de la que rescatarlo. Un paso intermedio es lo
    // mínimo para algo irreversible.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.detailDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.detailDelete),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await ref.read(libraryRepositoryProvider).delete(itemId);
    if (!context.mounted) return;

    // Mismo cuidado que en la captura: a un detalle se puede llegar por
    // enlace directo, y entonces no hay pila que desapilar.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.library);
    }
  }
}

/// El botón de exportar, con el formato como único paso: no hace falta
/// preguntar dónde guardarlo aparte, porque el selector de guardado del
/// sistema ya resuelve eso en el mismo gesto.
class _ExportButton extends ConsumerWidget {
  const _ExportButton({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return PopupMenuButton<ExportFormat>(
      icon: const Icon(Icons.ios_share),
      tooltip: l10n.detailExportTooltip,
      onSelected: (format) => _export(context, ref, format),
      itemBuilder: (context) => [
        for (final format in ExportFormat.values)
          PopupMenuItem(value: format, child: Text(format.label(l10n))),
      ],
    );
  }

  /// No distingue "canceló el diálogo de guardado" de "lo guardó": ver
  /// [ExportItemUseCase]. Solo avisa cuando algo salió mal de verdad.
  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    ExportFormat format,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    final result = await ref.read(exportItemUseCaseProvider)(
      ExportItemParams(item: item, format: format),
    );
    if (!context.mounted) return;

    result.match((failure) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
    }, (_) {});
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texts = item.renditions.whereType<TextRendition>().toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(item.title, style: theme.textTheme.headlineSmall),
            if (item.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                item.subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TagEditor(item: item),
            const SizedBox(height: 24),

            if (item.notes?.isNotEmpty ?? false) ...[
              _UserNote(note: item.notes!),
              const SizedBox(height: 24),
            ],

            if (texts.isEmpty)
              _NoContentYet(item: item)
            else
              for (final rendition in texts) ...[
                HighlightableText(
                  renditionId: rendition.id,
                  content: rendition.content,
                ),
                const SizedBox(height: 16),
              ],

            const SizedBox(height: 16),
            RelationsSection(item: item),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            _Provenance(item: item),
          ],
        ),
      ),
    );
  }
}

/// Lo que escribió el usuario sobre esto, separado del contenido.
///
/// Va destacado y arriba: es lo único de la pantalla que no vino de afuera, y
/// suele ser la razón por la que se guardó.
class _UserNote extends StatelessWidget {
  const _UserNote({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(note, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// El aviso de que el contenido todavía no llegó.
///
/// En los dos casos —esperando o fallido— dice explícitamente que el enlace
/// ya está guardado. Sin esa aclaración, una pantalla vacía se lee como "no
/// se guardó nada" y el usuario vuelve a capturarlo, o peor, deja de confiar
/// en la app.
class _NoContentYet extends ConsumerWidget {
  const _NoContentYet({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final failed = item.processingState == ProcessingState.failed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              switch (item.processingState) {
                ProcessingState.pending => Icons.schedule,
                ProcessingState.processing => Icons.hourglass_empty,
                ProcessingState.failed => Icons.error_outline,
                ProcessingState.ready => Icons.info_outline,
              },
              size: 20,
              color: failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _emptyStateMessage(l10n, item: item, failed: failed),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        if (failed) ...[
          const SizedBox(height: 12),
          // Reintentar es a pedido y no automático en cada arranque: un fallo
          // puede ser permanente —un video borrado, una página que ya no
          // existe— y volver a intentarlo solo gastaría batería y datos para
          // fallar de nuevo. Quien sabe si vale la pena es el usuario.
          FilledButton.tonalIcon(
            onPressed: () =>
                ref.read(processingQueueProvider.notifier).enqueue(item.id),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l10n.detailRetry),
          ),
        ],
      ],
    );
  }
}

class _Provenance extends ConsumerWidget {
  const _Provenance({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final source = item.source;

    // La fecha se formatea con el idioma activo: "11 sept 2026" en español y
    // "Sep 11, 2026" en inglés, en vez de un formato fijo que se lee raro en
    // uno de los dos.
    final locale = Localizations.localeOf(context).toString();
    final captured = DateFormat.yMMMd(locale).format(source.capturedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.detailProvenance,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _ProvenanceRow(icon: source.kind.icon, text: source.kind.label(l10n)),
        if (source.authorName != null)
          _ProvenanceRow(
            icon: Icons.person_outline,
            text: l10n.detailAuthor(source.authorName!),
          ),
        _ProvenanceRow(
          icon: Icons.event_outlined,
          text: l10n.detailCapturedOn(captured),
        ),
        // Para un PDF o un libro no hay ningún enlace al que volver: el
        // archivo **es** la fuente. Sin esta fila, el detalle no diría en
        // ninguna parte que la copia original está a salvo, y el usuario
        // tendría que confiar en que sí.
        if (source.originalFilePath != null) ...[
          _ProvenanceRow(
            icon: Icons.folder_outlined,
            text: l10n.detailOriginalFile(
              originalFileNameOf(source.originalFilePath!),
            ),
          ),
          TextButton.icon(
            onPressed: () =>
                _openOriginalFile(context, ref, source.originalFilePath!),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(l10n.detailOpenFile),
          ),
        ],
        if (source.url != null) ...[
          const SizedBox(height: 12),
          _OriginalLink(url: source.url!),
        ],
      ],
    );
  }

  /// Pide al almacén la ruta absoluta y se la pasa a la app del sistema.
  ///
  /// Solo avisa cuando algo sale mal: si se abrió, el sistema ya está
  /// mostrando el archivo y una confirmación encima sería ruido.
  Future<void> _openOriginalFile(
    BuildContext context,
    WidgetRef ref,
    String relativePath,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    final absolutePath = await ref
        .read(fileStoreProvider)
        .resolve(relativePath);
    final result = await ref.read(fileOpenerProvider).open(absolutePath);
    if (!context.mounted) return;

    final message = switch (result) {
      FileOpenResult.done => null,
      FileOpenResult.fileNotFound => l10n.detailOpenFileNotFound,
      FileOpenResult.noAppAvailable => l10n.detailOpenFileNoApp,
      FileOpenResult.failed => l10n.detailOpenFileFailed,
    };
    if (message == null) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ProvenanceRow extends StatelessWidget {
  const _ProvenanceRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El enlace al original, seleccionable y copiable.
///
/// Se copia en vez de abrirse: abrirlo exigiría un complemento nativo que hoy
/// no se puede probar en este proyecto, y ofrecer un botón que a veces no
/// hace nada es peor que ofrecer uno que siempre funciona. Copiar y pegar
/// resuelve el caso completo mientras tanto.
class _OriginalLink extends StatelessWidget {
  const _OriginalLink({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            url,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(l10n.detailLinkCopied)));
          },
          icon: const Icon(Icons.copy, size: 18),
          label: Text(l10n.detailCopyLink),
        ),
      ],
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final message = error is Failure
        ? (error as Failure).localizedMessage(l10n)
        : l10n.globalErrorUnexpected;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Qué decir cuando todavía no hay contenido.
///
/// El mensaje cambia según de dónde vino el elemento, y no es un matiz: a
/// quien guardó un enlace le importa saber que el enlace está a salvo, y a
/// quien guardó un PDF le importa saber que el archivo está a salvo. Decirle
/// "el enlace sigue guardado" a alguien que nunca guardó un enlace suena a
/// mensaje equivocado, y hace dudar de si su documento sigue ahí.
String _emptyStateMessage(
  AppLocalizations l10n, {
  required KnowledgeItem item,
  required bool failed,
}) {
  final fromFile = item.source.originalFilePath != null;

  if (failed) {
    return fromFile
        ? l10n.detailExtractionFailedFile
        : l10n.detailExtractionFailed;
  }

  return fromFile ? l10n.detailNoContentYetFile : l10n.detailNoContentYet;
}

/// El nombre con el que el usuario reconoce su archivo.
///
/// En el almacén cada archivo vive en una carpeta con el identificador de su
/// fuente, así que el último tramo de la ruta ya es el nombre original: no
/// hay nada que recortar ni que adivinar.
String originalFileNameOf(String storedPath) => p.basename(storedPath);
