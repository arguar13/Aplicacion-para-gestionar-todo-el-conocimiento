import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/presentation/providers/extract_providers.dart';
import 'package:sinapsis/features/creations/extract/presentation/widgets/extract_study_chips.dart';
import 'package:sinapsis/features/creations/extract/presentation/widgets/extract_viewer.dart';
import 'package:sinapsis/features/library/presentation/widgets/move_to_trash.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_section_edit_screen.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_more_menu.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_panel.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_presentation.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_contents_sheet.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_more_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La sección de un documento procesado que muestra la lectura de [kind]: el
/// texto, el resumen o la síntesis.
ProcessedSection processedSectionShowing(StudyCreationKind kind) =>
    switch (kind) {
      StudyCreationKind.summary => ProcessedSection.summary,
      StudyCreationKind.synthesis => ProcessedSection.synthesis,
      _ => ProcessedSection.text,
    };

/// La lectura de [section] de un documento procesado.
StudyCreationKind? extractKindOfSection(ProcessedSection section) =>
    switch (section) {
      ProcessedSection.text => StudyCreationKind.fullText,
      ProcessedSection.summary => StudyCreationKind.summary,
      ProcessedSection.synthesis => StudyCreationKind.synthesis,
      ProcessedSection.keywords ||
      ProcessedSection.notes ||
      ProcessedSection.fragments ||
      ProcessedSection.images => null,
    };

/// **«Texto», «Resumen» o «Síntesis» de un documento procesado, en el marco
/// de lectura** (F45, mejora 12; F47, paso 1): exactamente el mismo lector que
/// el de «Lo creado» —el mismo cuerpo ([ExtractViewer]), lo mismo arriba y en
/// el mismo orden—, rotulado «Texto · 6 páginas» en vez de «Resumen · 12
/// oraciones». Es una vista del texto procesado: no crea nada en «Lo creado».
///
/// - **El texto, limpio**: los enlaces como palabras, sin su dirección, y sin
///   `![](…)`; las palabras clave en rosa, si se resaltan.
/// - **IA**: las fichas Resumir · Sintetizar · Palabras clave sobre el
///   documento mismo —crearlo o verlo de un toque—, Preguntar a la IA y
///   Podcast.
/// - **Contenido**: las otras partes del documento —el texto, el resumen, la
///   síntesis—, el original y la fuente en la Biblioteca, y «Leer: Todo ·
///   Resumen · Síntesis · Palabras clave».
/// - **⋮**: «Editar el texto» —o las oraciones—, que abre la edición de
///   siempre de a una página; «Copiar todo» en el resumen y la síntesis;
///   «Descargar con lo marcado»; y, en rojo, el documento procesado a la
///   papelera, con «Deshacer». La fuente de la Biblioteca no se toca.
/// - **Escuchar**, abajo: **un solo dictado de voz**, el mismo en los tres,
///   sin el botón flotante.
///
/// Con varios documentos —lo que abre una ficha de la fila de IA de una
/// creación con varias fuentes— van uno debajo del otro, cada uno con su
/// título, y ⋮ queda con lo de todos.
class ProcessedReaderScreen extends ConsumerWidget {
  const ProcessedReaderScreen({
    required this.kind,
    required this.documentIds,
    super.key,
  });

  final StudyCreationKind kind;
  final List<String> documentIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final read = ExtractRead(
      kind: kind,
      documentIds: documentIds,
      readableId:
          'procesado-lectura:${kind.storageKey}:${documentIds.join(',')}',
    );
    final section = processedSectionShowing(kind);
    final single = documentIds.length == 1;
    final document = single
        ? ref.watch(processedDocumentProvider(documentIds.single)).valueOrNull
        : null;
    final title =
        document?.title ??
        (single ? '' : l10n.f47P1ReaderSeveral(documentIds.length));
    final count = document?.summary.partCounts[section];

    return ReadingFrame(
      key: Key('processed-reader-${kind.storageKey}'),
      info: ReadingDocumentInfo(
        title: title,
        kindLabel: count == null
            ? section.label(l10n)
            : '${section.label(l10n)} · ${section.countLabel(l10n, count)}',
        kindIcon: section.icon,
      ),
      showTitle: false,
      body: ExtractViewer(
        read: read,
        title: title,
        kicker: section == ProcessedSection.text
            ? (extract) => _textKicker(l10n, ref, extract.documentId)
            : null,
      ),
      aiRow: (context, trailing) =>
          ExtractStudyChips(read: read, trailing: trailing),
      onSummarize: () =>
          unawaited(tapExtractStudy(context, ref, read, StudyMarkKind.summary)),
      contents: [
        if (document != null)
          ReadingContentsSection(
            key: const Key('processed-reader-parts'),
            title: l10n.f47P1ContentsDocument,
            entries: _partsOf(context, l10n, document),
          ),
      ],
      menu: document == null ? const [] : _menuOf(context, ref, l10n, document),
      ownPlayer: (context) => ExtractPlayer(read: read, title: title),
      ownReadableId: read.readableId,
    );
  }

  /// «TEXTO · 6 PÁGINAS»: el texto se cuenta por páginas, como en el
  /// documento.
  String _textKicker(AppLocalizations l10n, WidgetRef ref, String id) {
    final pages =
        ref
            .read(processedDocumentProvider(id))
            .valueOrNull
            ?.summary
            .partCounts[ProcessedSection.text] ??
        0;
    return '${ProcessedSection.text.label(l10n)} · '
        '${ProcessedSection.text.countLabel(l10n, pages)}';
  }

  /// Las otras partes que se leen —el texto, el resumen, la síntesis—, el
  /// original y la fuente.
  List<ReadingOutlineEntry> _partsOf(
    BuildContext context,
    AppLocalizations l10n,
    ProcessedDocument document,
  ) {
    final counts = document.summary.partCounts;
    final source = document.source;
    return [
      for (final other in [
        ProcessedSection.text,
        ProcessedSection.summary,
        ProcessedSection.synthesis,
      ])
        if (other != processedSectionShowing(kind) && (counts[other] ?? 0) > 0)
          ReadingOutlineEntry(
            key: Key('processed-reader-open-${other.name}'),
            label: other.label(l10n),
            detail: other.countLabel(l10n, counts[other]!),
            // Una lectura en lugar de la otra: «atrás» vuelve al documento.
            onSelected: () => context.pushReplacement(
              RoutePaths.extractReading(extractKindOfSection(other)!, [
                document.id,
              ]),
            ),
          ),
      ReadingOutlineEntry(
        key: const Key('processed-reader-open-original'),
        label: l10n.f47P1OpenOriginal,
        onSelected: () =>
            unawaited(context.push(RoutePaths.processedOriginal(document.id))),
      ),
      if (source != null && !source.inTrash)
        ReadingOutlineEntry(
          key: const Key('processed-reader-open-source'),
          label: l10n.processedOpenSource,
          detail: source.title,
          onSelected: () =>
              unawaited(context.push(RoutePaths.itemDetail(source.itemId))),
        ),
    ];
  }

  List<ReadingMenuGroup> _menuOf(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ProcessedDocument document,
  ) {
    final section = processedSectionShowing(kind);
    final download = downloadMarkedOriginalAction(context, ref, document);
    final hasParts = (document.summary.partCounts[section] ?? 0) > 0;
    return [
      ReadingMenuGroup([
        if (hasParts && !document.inTrash)
          ReadingMenuEntry(
            key: const Key('processed-reader-edit'),
            icon: Icons.edit_note_outlined,
            label: section == ProcessedSection.text
                ? l10n.f47P1MoreEditText
                : l10n.f47P1MoreEditSentences,
            onSelected: () => unawaited(
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ProcessedSectionEditScreen(
                    documentId: document.id,
                    section: section,
                  ),
                ),
              ),
            ),
          ),
        if (hasParts && section != ProcessedSection.text)
          ReadingMenuEntry(
            key: const Key('processed-reader-copy'),
            icon: Icons.copy_outlined,
            label: l10n.f47P1MoreCopyAll,
            onSelected: () => unawaited(
              copyProcessedSection(context, ref, document.id, section),
            ),
          ),
      ]),
      ReadingMenuGroup([
        if (download != null)
          ReadingMenuEntry(
            key: const Key('processed-reader-download-marked'),
            icon: Icons.download_outlined,
            label: l10n.f45S3DownloadMarked,
            detail: l10n.f45S3DownloadMarkedHint,
            onSelected: download,
          ),
      ]),
      ReadingMenuGroup([
        if (!document.inTrash)
          ReadingMenuEntry(
            key: const Key('processed-reader-trash'),
            icon: Icons.delete_outline,
            label: l10n.f47P1MoreTrashProcessed,
            detail: l10n.f47P1MoreTrashProcessedHint,
            destructive: true,
            onSelected: () => unawaited(_trash(context, ref, document.id)),
          ),
      ]),
    ];
  }

  /// A la papelera, con «Deshacer», y de vuelta al documento.
  Future<void> _trash(BuildContext context, WidgetRef ref, String id) async {
    final navigator = Navigator.of(context);
    final moved = await moveToTrashWithUndo(context, ref, [id]);
    if (moved && navigator.canPop()) navigator.pop();
  }
}
