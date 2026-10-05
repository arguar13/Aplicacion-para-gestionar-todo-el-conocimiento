import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/storage/file_opener.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';
import 'package:sinapsis/features/attachments/presentation/providers/attachment_cap.dart';
import 'package:sinapsis/features/attachments/presentation/providers/attachment_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/image_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La sección «Contenido» de un elemento (F30, decisión D): lo que se bajó
/// de su página, en su formato original, agrupado por tipo —documentos,
/// audios, videos, imágenes— y con el texto de cada archivo a un toque.
///
/// Arriba, lo que falta: lo que la cola todavía baja, lo que quedó afuera
/// del tope por elemento, sin lugar o sin poder bajarse, con «Bajar el
/// resto». Sin nada bajado ni nada que bajar, no dibuja nada.
///
/// Nada se abre solo: un archivo se abre cuando la persona lo toca, con la
/// app del teléfono que corresponda.
class ItemContentSection extends ConsumerWidget {
  const ItemContentSection({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachments =
        ref.watch(attachmentsProvider(item.id)).valueOrNull ?? const [];
    final downloads =
        ref.watch(attachmentDownloadsProvider(item.id)).valueOrNull ?? const [];
    final remaining = [
      for (final d in downloads)
        if (d.status != AttachmentDownloadStatus.done) d,
    ];
    if (attachments.isEmpty && remaining.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = l10n.localeName;
    final totalBytes = attachments.fold<int>(
      0,
      (sum, a) => sum + (a.sizeBytes ?? 0),
    );
    final groups = {
      for (final group in AttachmentGroup.displayOrder)
        group: [
          for (final a in attachments)
            if (a.group == group) a,
        ],
    }..removeWhere((_, list) => list.isEmpty);

    return Card(
      key: const Key('item-content-section'),
      // El espacio de arriba va con la sección: sin ella, no queda un hueco.
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.contentSectionTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                if (attachments.isNotEmpty)
                  Text(
                    l10n.contentSummary(
                      attachments.length,
                      formatFileSize(totalBytes, locale),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            _Pending(item: item, remaining: remaining),
            for (final MapEntry(key: group, value: list) in groups.entries) ...[
              const SizedBox(height: 12),
              _GroupHeader(group: group, count: list.length),
              const SizedBox(height: 4),
              if (group == AttachmentGroup.images)
                _ImageGrid(images: list)
              else
                for (final attachment in list)
                  _FileTile(attachment: attachment),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lo que falta del «Contenido»: lo que se baja, lo que quedó afuera, sin
/// lugar o sin poder bajarse.
class _Pending extends ConsumerWidget {
  const _Pending({required this.item, required this.remaining});

  final KnowledgeItem item;
  final List<AttachmentDownload> remaining;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (remaining.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = l10n.localeName;

    int count(AttachmentDownloadStatus status) =>
        remaining.where((d) => d.status == status).length;
    final pending = count(AttachmentDownloadStatus.pending);
    final leftOut = remaining
        .where((d) => d.status == AttachmentDownloadStatus.leftOut)
        .toList();
    final noSpace = count(AttachmentDownloadStatus.noSpace);
    final failed = count(AttachmentDownloadStatus.failed);
    final leftOutBytes = leftOut.fold<int>(
      0,
      (sum, d) => sum + (d.expectedBytes ?? 0),
    );
    final cap = ref.watch(attachmentCapProvider);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pending > 0) ...[
            Text(l10n.contentDownloading(pending), style: style),
            const SizedBox(height: 4),
            const LinearProgressIndicator(),
          ],
          if (leftOut.isNotEmpty)
            Text(
              [
                l10n.contentLeftOut(
                  leftOut.length,
                  formatFileSize(cap, locale),
                ),
                if (leftOutBytes > 0)
                  l10n.contentLeftOutSize(formatFileSize(leftOutBytes, locale)),
              ].join(' '),
              style: style,
            ),
          if (noSpace > 0) Text(l10n.contentNoSpace(noSpace), style: style),
          if (failed > 0) Text(l10n.contentFailed(failed), style: style),
          if (pending == 0 && (leftOut.isNotEmpty || noSpace > 0 || failed > 0))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('content-download-rest'),
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.contentDownloadRest),
                onPressed: () => _downloadRest(context, ref),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _downloadRest(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    await ref.read(attachmentRepositoryProvider).requestRest(item.id);
    await ref.read(processingQueueProvider.notifier).retry(item.id);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.contentDownloadRestStarted)),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.count});

  final AttachmentGroup group;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = switch (group) {
      AttachmentGroup.documents => l10n.contentGroupDocuments,
      AttachmentGroup.audios => l10n.contentGroupAudios,
      AttachmentGroup.videos => l10n.contentGroupVideos,
      AttachmentGroup.images => l10n.contentGroupImages,
      AttachmentGroup.others => l10n.contentGroupOthers,
    };
    return Row(
      children: [
        Icon(_groupIcon(group), size: 18, color: theme.colorScheme.secondary),
        const SizedBox(width: 6),
        Text(
          '$name · $count',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.secondary,
          ),
        ),
      ],
    );
  }
}

IconData _groupIcon(AttachmentGroup group) => switch (group) {
  AttachmentGroup.documents => Icons.description_outlined,
  AttachmentGroup.audios => Icons.headphones_outlined,
  AttachmentGroup.videos => Icons.movie_outlined,
  AttachmentGroup.images => Icons.image_outlined,
  AttachmentGroup.others => Icons.insert_drive_file_outlined,
};

/// Un documento, un audio, un video u otro archivo: su nombre, de dónde
/// salió, cuánto pesa y si tiene texto. Tocarlo ofrece abrirlo o leer su
/// texto.
class _FileTile extends ConsumerWidget {
  const _FileTile({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(_groupIcon(attachment.group)),
      title: Text(
        attachment.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(_details(attachment, l10n)),
      onTap: () => showAttachmentActions(context, ref, attachment),
    );
  }
}

/// "PDF · 2,7 MB · Con texto · De archive.org".
String _details(Attachment attachment, AppLocalizations l10n) {
  final extension = attachment.fileName.contains('.')
      ? attachment.fileName.split('.').last.toUpperCase()
      : null;
  final host = Uri.tryParse(attachment.originUrl ?? '')?.host;
  return [
    ?extension,
    if (attachment.sizeBytes case final size?)
      formatFileSize(size, l10n.localeName),
    if (attachment.canHaveText && attachment.hasText)
      l10n.contentHasText
    else if (attachment.canHaveText && attachment.textAttempted)
      l10n.contentNoText
    else if (attachment.canHaveText)
      l10n.contentTextPending,
    if (host != null && host.isNotEmpty) l10n.contentFrom(host),
  ].join(' · ');
}

/// Las fotos, en miniatura: cada una se decodifica al tamaño en que se ve,
/// no entera.
class _ImageGrid extends ConsumerWidget {
  const _ImageGrid({required this.images});

  final List<Attachment> images;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(fileStoreProvider);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 6.0;
        final columns = (constraints.maxWidth / 110).floor().clamp(3, 6);
        final side = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final image in images)
              SizedBox.square(
                dimension: side,
                child: Tooltip(
                  message: image.displayName,
                  child: InkWell(
                    onTap: () => showAttachmentActions(context, ref, image),
                    borderRadius: BorderRadius.circular(8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: FutureBuilder<String?>(
                        future: files.localPathOf(image.relativePath),
                        builder: (context, snapshot) {
                          final path = snapshot.data;
                          if (path == null ||
                              image.fileName.toLowerCase().endsWith('.svg')) {
                            return _ImagePlaceholder(attachment: image);
                          }
                          return Image.file(
                            File(path),
                            fit: BoxFit.cover,
                            cacheWidth: (side * ratio).round(),
                            errorBuilder: (_, _, _) =>
                                _ImagePlaceholder(attachment: image),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// Lo que se puede hacer con un archivo del «Contenido»: verlo —una foto,
/// adentro de la app—, abrirlo con la app del teléfono y leer su texto.
Future<void> showAttachmentActions(
  BuildContext context,
  WidgetRef ref,
  Attachment attachment,
) async {
  final l10n = AppLocalizations.of(context)!;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              attachment.displayName,
              style: Theme.of(sheetContext).textTheme.titleMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _details(attachment, l10n),
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          if (attachment.kind == RenditionKind.image &&
              !attachment.fileName.toLowerCase().endsWith('.svg'))
            ListTile(
              leading: const Icon(Icons.zoom_in),
              title: Text(attachment.displayName, maxLines: 1),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _viewImage(context, ref, attachment);
              },
            ),
          ListTile(
            key: const Key('content-open'),
            leading: const Icon(Icons.open_in_new),
            title: Text(l10n.contentOpen),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _open(context, ref, attachment);
            },
          ),
          if (attachment.hasText)
            ListTile(
              key: const Key('content-read-text'),
              leading: const Icon(Icons.article_outlined),
              title: Text(l10n.contentReadText),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _readText(context, ref, attachment);
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> _viewImage(
  BuildContext context,
  WidgetRef ref,
  Attachment attachment,
) async {
  final path = await ref
      .read(fileStoreProvider)
      .localPathOf(attachment.relativePath);
  if (path == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text(attachment.displayName, overflow: TextOverflow.ellipsis),
        ),
        body: ImageViewerView(path: path),
      ),
    ),
  );
}

Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  Attachment attachment,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final path = await ref
      .read(fileStoreProvider)
      .resolve(attachment.relativePath);
  final result = await ref.read(fileOpenerProvider).open(path);
  final message = switch (result) {
    FileOpenResult.done => null,
    FileOpenResult.noAppAvailable => l10n.contentNoAppToOpen,
    FileOpenResult.fileNotFound ||
    FileOpenResult.failed => l10n.contentOpenFailed,
  };
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

Future<void> _readText(
  BuildContext context,
  WidgetRef ref,
  Attachment attachment,
) async {
  final text = await ref
      .read(attachmentRepositoryProvider)
      .textOf(attachment.id);
  if (text == null || !context.mounted) return;
  final name = attachment.fileName.toLowerCase();
  final markdown =
      name.endsWith('.epub') || name.endsWith('.docx') || name.endsWith('.md');
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DocumentReaderScreen(
        title: attachment.displayName,
        content: text,
        markdown: markdown,
      ),
    ),
  );
}
