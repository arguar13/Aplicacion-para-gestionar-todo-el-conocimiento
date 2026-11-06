/// Lo que se hace con una entrada o un documento del Índice al mantenerlo
/// apretado (F46, paso 4): «Abrir en el original», «Preguntar al chat»,
/// «Copiar el título» y, en una imagen, «Renombrar». Con la hoja de ⋮ del
/// marco de lectura, la común de la app (`showReadingMore`): su título arriba
/// y las opciones en grupos.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_handoff.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/repositories/index_document_access.dart';
import 'package:sinapsis/features/index/domain/services/index_chapter.dart';
import 'package:sinapsis/features/index/presentation/index_opening.dart';
import 'package:sinapsis/features/index/presentation/providers/index_providers.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_rows.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_more_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre lo que se hace con [entry]. [number] es su numeración, si se ve.
///
/// Lo que hace falta del documento —su título, su copia del original— se lee
/// recién ahora, no mientras se recorre el Índice; si el documento ya no
/// está, no abre nada.
Future<void> showIndexEntryActions(
  BuildContext context,
  WidgetRef ref,
  IndexEntry entry, {
  String? number,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final facts = await ref
      .read(indexDocumentAccessProvider)
      .factsOf(entry.documentId);
  if (facts == null || !context.mounted) return;
  final title = indexEntryTitle(l10n, entry);
  final page = indexEntryPage(l10n, entry);
  final kind = switch (entry) {
    IndexEntry(isImage: true) => l10n.f46P4KindImage,
    IndexEntry(isWholeText: true) => l10n.f46P3WholeText,
    _ => l10n.f46P4KindChapter(entry.level),
  };

  final groups = <ReadingMenuGroup>[
    if (!entry.isImage)
      ReadingMenuGroup([
        _openOriginalEntry(context, ref, l10n, entry, facts),
        ReadingMenuEntry(
          key: const Key('index-action-ask-chat'),
          icon: Icons.forum_outlined,
          label: l10n.f46P4AskChat,
          detail: entry.isWholeText
              ? l10n.f46P4AskChatDocumentHint
              : l10n.f46P4AskChatChapterHint,
          onSelected: () =>
              unawaited(_askAboutEntry(context, ref, entry, facts.title)),
        ),
      ]),
    ReadingMenuGroup([
      if (entry.isImage && entry.imageId != null)
        ReadingMenuEntry(
          key: const Key('index-action-rename'),
          icon: Icons.edit_outlined,
          label: l10n.f46P4Rename,
          detail: l10n.f46P4RenameHint,
          onSelected: () => unawaited(_renameImage(context, ref, entry)),
        ),
      if (!entry.isWholeText)
        ReadingMenuEntry(
          key: const Key('index-action-copy'),
          icon: Icons.copy_outlined,
          label: l10n.f46P4CopyTitle,
          onSelected: () => unawaited(
            _copy(context, number == null ? title : '$number $title'),
          ),
        ),
    ]),
  ];

  await showReadingMore(
    context,
    info: ReadingDocumentInfo(
      title: number == null || entry.isImage ? title : '$number $title',
      kindLabel: [kind, ?page, facts.title].join(' · '),
      kindIcon: entry.isImage
          ? Icons.image_outlined
          : Icons.format_list_numbered,
    ),
    groups: groups,
  );
}

/// Abre lo que se hace con [document]: abrir su texto, abrirlo en el
/// original, preguntarle al chat por él y copiar su título.
Future<void> showIndexDocumentActions(
  BuildContext context,
  WidgetRef ref,
  IndexDocument document,
) async {
  final l10n = AppLocalizations.of(context)!;
  final facts = await ref
      .read(indexDocumentAccessProvider)
      .factsOf(document.id);
  if (facts == null || !context.mounted) return;
  final whole = IndexOpening(documentId: document.id);
  await showReadingMore(
    context,
    info: ReadingDocumentInfo(
      title: document.title,
      kindLabel: document.sourceKind.label(l10n),
      kindIcon: document.sourceKind.icon,
    ),
    groups: [
      ReadingMenuGroup([
        if (document.hasText)
          ReadingMenuEntry(
            key: const Key('index-action-open-text'),
            icon: Icons.chrome_reader_mode_outlined,
            label: l10n.f46P4OpenText,
            detail: l10n.f46P4OpenTextHint,
            onSelected: () => openIndexEntry(context, ref, whole),
          ),
        _openOriginalEntry(context, ref, l10n, null, facts, document.id),
        ReadingMenuEntry(
          key: const Key('index-action-ask-chat'),
          icon: Icons.forum_outlined,
          label: l10n.f46P4AskChat,
          detail: l10n.f46P4AskChatDocumentHint,
          onSelected: () => askInChat(
            context,
            ChatHandoff(
              question: l10n.f47P1AskAiDraft(document.title),
              send: false,
            ),
          ),
        ),
      ]),
      ReadingMenuGroup([
        ReadingMenuEntry(
          key: const Key('index-action-copy'),
          icon: Icons.copy_outlined,
          label: l10n.f46P4CopyTitle,
          onSelected: () => unawaited(_copy(context, document.title)),
        ),
      ]),
    ],
  );
}

/// «Abrir en el original»: un PDF en la página de [entry], una página web en
/// su título, lo demás desde el comienzo.
///
/// Abre la copia del original que guardó Procesado y, sin ella —«Pasar todo»
/// pasa solo el texto—, el original de su fuente en la Biblioteca, en el mismo
/// lugar y con el mismo visor que su detalle (F46, paso 5c); una fuente cuyo
/// original no se lee en un visor —un audio, un video— abre su ficha, que lo
/// muestra. Apagada, y diciendo por qué, solo sin copia y sin fuente —o con
/// la fuente en la papelera—.
ReadingMenuEntry _openOriginalEntry(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  IndexEntry? entry,
  IndexDocumentFacts facts, [
  String? documentId,
]) {
  final id = entry?.documentId ?? documentId!;
  final copy = facts.original;
  final source = facts.source;
  final library = copy == null && source != null && !source.inTrash
      ? source
      : null;
  final original = copy ?? library?.original;
  final pdfPage = original == IndexOriginalKind.pdf ? entry?.pdfPage : null;
  final heading =
      original == IndexOriginalKind.webPage &&
          entry != null &&
          !entry.isWholeText &&
          entry.title.isNotEmpty
      ? entry
      : null;

  final String detail;
  final VoidCallback? open;
  if (copy != null) {
    detail = pdfPage != null
        ? l10n.f46P4OriginalPdfPage(pdfPage)
        : heading != null
        ? l10n.f46P4OriginalHeading
        : l10n.f46P4OriginalStart;
    open = () => unawaited(
      _openOriginal(
        context,
        ref,
        id,
        heading,
        (occurrence) => RoutePaths.processedOriginal(
          id,
          page: pdfPage,
          heading: heading?.title,
          occurrence: occurrence,
        ),
      ),
    );
  } else if (library != null) {
    detail = library.original == null
        ? l10n.f46P5cSourceItem
        : pdfPage != null
        ? l10n.f46P5cSourcePdfPage(pdfPage)
        : heading != null
        ? l10n.f46P5cSourceHeading
        : l10n.f46P5cSourceStart;
    open = library.original == null
        ? () => unawaited(context.push(RoutePaths.itemDetail(library.itemId)))
        : () => unawaited(
            _openOriginal(
              context,
              ref,
              id,
              heading,
              (occurrence) => RoutePaths.libraryOriginal(
                library.itemId,
                page: pdfPage,
                heading: heading?.title,
                occurrence: occurrence,
              ),
            ),
          );
  } else {
    detail = source != null && source.inTrash
        ? l10n.f46P5cSourceInTrash
        : l10n.f46P4NoOriginal;
    open = null;
  }
  return ReadingMenuEntry(
    key: const Key('index-action-open-original'),
    icon: Icons.description_outlined,
    label: l10n.f46P4OpenOriginal,
    detail: detail,
    onSelected: open,
  );
}

/// Abre la dirección que arma [location] con cuántos títulos iguales a
/// [heading] vienen antes en el documento [documentId] —el segundo
/// «Referencias» es el segundo de la página—; sin [heading], cero.
Future<void> _openOriginal(
  BuildContext context,
  WidgetRef ref,
  String documentId,
  IndexEntry? heading,
  String Function(int occurrence) location,
) async {
  var occurrence = 0;
  if (heading != null) {
    final entries = await ref
        .read(indexRepositoryProvider)
        .watchEntries(documentId)
        .first;
    occurrence = indexHeadingOccurrence(entries, heading);
  }
  if (!context.mounted) return;
  unawaited(context.push(location(occurrence)));
}

/// «Preguntar al chat»: una conversación nueva sobre el capítulo, con su
/// texto —desde su título hasta el capítulo siguiente de su nivel— a medio
/// escribir, para que se pregunte lo que se quiera. El camino de siempre para
/// abrir el chat con algo (`askInChat`), como «Preguntar a la IA» del lector.
Future<void> _askAboutEntry(
  BuildContext context,
  WidgetRef ref,
  IndexEntry entry,
  String documentTitle,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final entries = await ref
      .read(indexRepositoryProvider)
      .watchEntries(entry.documentId)
      .first;
  final text = await ref
      .read(indexDocumentAccessProvider)
      .textOf(entry.documentId);
  if (!context.mounted) return;
  final span = indexChapterSpan(entries, entry);
  final passage = text == null || span == null
      ? ''
      : indexChapterPassage(
          text.content,
          span.start,
          span.end,
          markdown: text.markdown,
          title: entry.isWholeText ? null : entry.title,
        );
  if (passage.isEmpty) {
    _say(messenger, l10n.f46P4AskChatNoText);
    return;
  }
  final question = entry.isWholeText
      ? l10n.f46P4AskDraftWhole(documentTitle, passage)
      : l10n.f46P4AskDraftChapter(entry.title, documentTitle, passage);
  askInChat(context, ChatHandoff(question: question, send: false));
}

Future<void> _copy(BuildContext context, String text) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: text));
  _say(messenger, l10n.f46P4Copied);
}

/// «Renombrar» una imagen (decisión E): su título nuevo, que el Índice
/// muestra en vivo.
Future<void> _renameImage(
  BuildContext context,
  WidgetRef ref,
  IndexEntry entry,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(indexRepositoryProvider);
  final title = await showDialog<String>(
    context: context,
    builder: (context) => IndexRenameImageDialog(initial: entry.title),
  );
  if (title == null || title == entry.title) return;
  final result = await repository.renameImage(entry.imageId!, title);
  _say(
    messenger,
    result.isRight() ? l10n.f46P4Renamed : l10n.f46P4RenameFailed,
  );
}

void _say(ScaffoldMessengerState messenger, String text) => messenger
  ..hideCurrentSnackBar()
  ..showAppSnackBar(AppSnackBar(content: Text(text)));

/// El diálogo de «Renombrar» una imagen: su título, listo para cambiarlo.
/// «Guardar» —o Enter— devuelve el nuevo, sin espacios en los bordes; vacío
/// no se puede guardar, porque una imagen no se queda sin título.
class IndexRenameImageDialog extends StatefulWidget {
  const IndexRenameImageDialog({required this.initial, super.key});

  final String initial;

  @override
  State<IndexRenameImageDialog> createState() => _IndexRenameImageDialogState();
}

class _IndexRenameImageDialogState extends State<IndexRenameImageDialog> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _title => _controller.text.trim();

  void _save() {
    if (_title.isEmpty) return;
    Navigator.of(context).pop(_title);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final material = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.f46P4RenameTitle),
      content: TextField(
        key: const Key('index-rename-field'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: l10n.f46P4RenameLabel),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(material.cancelButtonLabel),
        ),
        FilledButton(
          key: const Key('index-rename-save'),
          onPressed: _title.isEmpty ? null : _save,
          child: Text(l10n.f46P4RenameSave),
        ),
      ],
    );
  }
}
