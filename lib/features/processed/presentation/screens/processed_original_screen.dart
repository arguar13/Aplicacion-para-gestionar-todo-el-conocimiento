import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_view_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_reader_screen.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_view.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_more_menu.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_presentation.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_contents_sheet.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_more_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La copia del original de un documento procesado (F41, decisión H), en el
/// visor de siempre —el de PDF, el de páginas web o el lector—, con lo elegido
/// marcado encima: el resumen, la síntesis y las palabras clave con los
/// colores de estudiar, y los fragmentos con el de los cortes.
///
/// **Es la misma pantalla que el original de una fuente en la Biblioteca**
/// (F45, paso 7b, mejora 16, decisión H: [OriginalScreen] y [OriginalView]),
/// en **el marco de lectura** (F47, paso 1): en la fila de IA, las tres
/// fichas donde se marca, con la IA o a mano, tocando las oraciones o las
/// palabras en el visor (F43, paso 15, M5: `OriginalStudyBar`); y donde se
/// prende, se apaga y se oculta lo marcado. Es la pantalla completa del
/// original que el documento muestra en su vista previa
/// (`ProcessedOriginalSection`), que dice qué tiene marcado (mejora 15).
///
/// - **Contenido**: el texto, el resumen y la síntesis del documento —en el
///   mismo marco— y la fuente en la Biblioteca.
/// - **⋮**: «Descargar con lo marcado» y, en rojo, «Borrar la copia del
///   original» —de la fuente no se toca nada—.
///
/// **Lo que se pinta es del procesado, no de la fuente.** El visor mira la
/// copia por su propia clave (`processedOriginalStudyKeyFor`), como a
/// cualquier texto: lo estudiado de esa clave es lo del procesado
/// (`ProcessedOriginalStudyRepository`), y sus fragmentos, los cortes que se
/// marcan (`processedOriginalCutsProvider`). Así no se mezcla con lo estudiado
/// ni con lo resaltado de la fuente, y lo que se elige sobre la copia va al
/// procesado, nunca a la fuente: de la Biblioteca nada se toca.
///
/// Las marcas van en las posiciones del texto de la fuente, que es el de la
/// copia mientras su `content_hash` coincida. Si la fuente cambió su texto, no
/// se pinta nada y una línea dice por qué; un PDF o una página se ven igual, y
/// un Word, un EPUB o un texto —que el lector muestra por su texto— se abren
/// con otra app.
class ProcessedOriginalScreen extends ConsumerWidget {
  const ProcessedOriginalScreen({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final document = ref.watch(processedDocumentProvider(documentId));
    final title = document.valueOrNull?.title ?? '';
    final original = ref.watch(processedOriginalProvider(documentId));
    final found = original.valueOrNull;
    final view = found == null
        ? null
        : watchProcessedOriginalView(ref, documentId);
    final loaded = view?.valueOrNull;
    final text = loaded != null && loaded.exists ? loaded.text : null;
    final format = found == null
        ? OriginalFormat.reader
        : originalFormatOf(found);

    final Widget body;
    if (original.hasError) {
      final error = original.error;
      body = EmptyStateView(
        icon: Icons.error_outline,
        title: error is Failure
            ? error.localizedMessage(l10n)
            : l10n.globalErrorUnexpected,
      );
    } else if (original.isLoading && found == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (found == null) {
      body = EmptyStateView(
        icon: Icons.file_copy_outlined,
        title: l10n.processedOriginalMissing,
      );
    } else if (loaded == null) {
      body = view!.hasError
          ? EmptyStateView(
              icon: Icons.error_outline,
              title: l10n.globalErrorUnexpected,
            )
          : const Center(child: CircularProgressIndicator());
    } else if (!loaded.exists) {
      body = EmptyStateView(
        icon: Icons.file_copy_outlined,
        title: l10n.failureMissingOriginalFile,
      );
    } else {
      body = OriginalView(
        format: format,
        path: loaded.path,
        title: title,
        text: text,
        notice: text == null ? l10n.processedOriginalUnmarked : null,
      );
    }

    final value = document.valueOrNull;
    return OriginalScreen(
      title: title,
      format: format,
      body: body,
      study: text == null
          ? null
          : OriginalStudy(documentId: documentId, original: text),
      contents: [
        if (value != null)
          ReadingContentsSection(
            key: const Key('processed-original-parts'),
            title: l10n.f47P1ContentsDocument,
            entries: _partsOf(context, l10n, value),
          ),
      ],
      menu: value == null ? const [] : _menuOf(context, ref, l10n, value),
    );
  }

  /// El texto, el resumen y la síntesis del documento, en el mismo marco, y
  /// la fuente en la Biblioteca.
  List<ReadingOutlineEntry> _partsOf(
    BuildContext context,
    AppLocalizations l10n,
    ProcessedDocument document,
  ) {
    final counts = document.summary.partCounts;
    final source = document.source;
    return [
      for (final section in [
        ProcessedSection.text,
        ProcessedSection.summary,
        ProcessedSection.synthesis,
      ])
        if ((counts[section] ?? 0) > 0)
          ReadingOutlineEntry(
            key: Key('processed-original-open-${section.name}'),
            label: section.label(l10n),
            detail: section.countLabel(l10n, counts[section]!),
            onSelected: () => unawaited(
              context.push(
                RoutePaths.extractReading(extractKindOfSection(section)!, [
                  document.id,
                ]),
              ),
            ),
          ),
      if (source != null && !source.inTrash)
        ReadingOutlineEntry(
          key: const Key('processed-original-open-source'),
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
    final download = downloadMarkedOriginalAction(context, ref, document);
    final deleteCopy = deleteOriginalCopyAction(context, ref, document);
    return [
      ReadingMenuGroup([
        if (download != null)
          ReadingMenuEntry(
            key: const Key('processed-original-download-marked'),
            icon: Icons.download_outlined,
            label: l10n.f45S3DownloadMarked,
            detail: l10n.f45S3DownloadMarkedHint,
            onSelected: download,
          ),
      ]),
      ReadingMenuGroup([
        if (deleteCopy != null)
          ReadingMenuEntry(
            key: const Key('processed-original-delete-copy'),
            icon: Icons.delete_sweep_outlined,
            label: l10n.processedDeleteOriginalCopy,
            detail: l10n.processedDeleteOriginalCopyHint,
            destructive: true,
            onSelected: deleteCopy,
          ),
      ]),
    ];
  }
}

/// En qué visor se ve la copia: un PDF, una página web archivada o, todo lo
/// demás —un Word, un EPUB, un texto—, el lector.
OriginalFormat originalFormatOf(ProcessedOriginal original) =>
    switch (original.kind) {
      RenditionKind.pdf => OriginalFormat.pdf,
      RenditionKind.html => OriginalFormat.page,
      _ => OriginalFormat.reader,
    };
