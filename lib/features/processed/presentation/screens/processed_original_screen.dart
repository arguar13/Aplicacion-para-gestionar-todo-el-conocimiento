import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/storage/file_opener.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La copia del original de un documento procesado (F41, decisión H), en el
/// visor de siempre —el de PDF, el de páginas web o el lector—, con lo elegido
/// marcado encima: el resumen, la síntesis y las palabras clave con los
/// colores de estudiar, y los fragmentos con el de los cortes.
///
/// **Lo que se pinta es del procesado, no de la fuente.** El visor mira la
/// copia por su propia clave (`processedOriginalStudyKeyFor`), como a
/// cualquier texto: lo estudiado de esa clave es lo elegido del procesado
/// (`ProcessedOriginalStudyRepository`), y sus fragmentos, los cortes que se
/// marcan (`processedOriginalCutsProvider`). Así no se mezcla con lo estudiado
/// ni con lo resaltado de la fuente, y nada de lo que se haga sobre la copia
/// cae en ella: de la Biblioteca nada se toca.
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
    final title =
        ref.watch(processedDocumentProvider(documentId)).valueOrNull?.title ??
        '';
    final original = ref.watch(processedOriginalProvider(documentId));

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: original.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyStateView(
          icon: Icons.error_outline,
          title: error is Failure
              ? error.localizedMessage(l10n)
              : l10n.globalErrorUnexpected,
        ),
        data: (original) => original == null
            ? EmptyStateView(
                icon: Icons.file_copy_outlined,
                title: l10n.processedOriginalMissing,
              )
            : _OriginalBody(
                documentId: documentId,
                original: original,
                title: title,
              ),
      ),
    );
  }
}

/// Lo que el visor necesita de la copia: dónde está su archivo, si sigue ahí,
/// y —si lo elegido se puede marcar— su texto, con la clave de la copia.
typedef ProcessedOriginalView = ({String path, bool exists, StudyText? text});

/// Qué pedirle a [processedOriginalViewProvider]: el documento y con qué texto
/// de la fuente se corresponde ahora la copia (`null` si con ninguno).
typedef ProcessedOriginalViewKey = ({String documentId, String? sourceKey});

/// El archivo de la copia y su texto —el de la fuente con que se corresponde,
/// mientras sea el mismo—. Se rehace solo si cambia con qué texto se
/// corresponde o la copia misma, no con cada parte que se toca: un libro no se
/// vuelve a leer por una oración editada.
final processedOriginalViewProvider = FutureProvider.autoDispose
    .family<ProcessedOriginalView, ProcessedOriginalViewKey>((ref, key) async {
      final original = await ref.watch(
        processedOriginalProvider(key.documentId).future,
      );
      if (original == null) {
        throw StateError('El documento ya no tiene la copia del original.');
      }
      final files = ref.watch(fileStoreProvider);
      final exists = await files.exists(original.relativePath);
      final path = await files.resolve(original.relativePath);
      final sourceKey = key.sourceKey;
      final sourceItemId = await ref.watch(
        processedDocumentProvider(
          key.documentId,
        ).selectAsync((document) => document?.summary.sourceItemId),
      );
      if (sourceKey == null || sourceItemId == null) {
        return (path: path, exists: exists, text: null);
      }
      final source = await ref
          .read(processedRepositoryProvider)
          .sourceText(sourceItemId, renditionId: sourceKey);
      final text = source.toNullable();
      return (
        path: path,
        exists: exists,
        text: text == null
            ? null
            : (
                itemId: key.documentId,
                renditionId: processedOriginalStudyKeyFor(key.documentId),
                content: text.text,
                markdown: _isMarkdown(original),
              ),
      );
    });

/// Si el texto de la copia es Markdown, como lo arma la app al extraerlo: el
/// de una página y el de un Word o un EPUB sí; el de un PDF o un `.txt`, tal
/// cual (ver `extractedTextIsMarkdown`).
bool _isMarkdown(ProcessedOriginal original) => switch (original.kind) {
  RenditionKind.pdf => false,
  RenditionKind.html => true,
  _ => original.mimeType != 'text/plain',
};

class _OriginalBody extends ConsumerWidget {
  const _OriginalBody({
    required this.documentId,
    required this.original,
    required this.title,
  });

  final String documentId;
  final ProcessedOriginal original;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final marks = ref.watch(processedOriginalMarksProvider(documentId));
    if (!marks.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final view = ref.watch(
      processedOriginalViewProvider((
        documentId: documentId,
        sourceKey: marks.value?.sourceKey,
      )),
    );
    final loaded = view.valueOrNull;
    if (loaded == null) {
      return view.hasError
          ? EmptyStateView(
              icon: Icons.error_outline,
              title: l10n.globalErrorUnexpected,
            )
          : const Center(child: CircularProgressIndicator());
    }
    if (!loaded.exists) {
      return EmptyStateView(
        icon: Icons.file_copy_outlined,
        title: l10n.failureMissingOriginalFile,
      );
    }
    final text = loaded.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (text == null)
          _Notice(message: l10n.processedOriginalUnmarked)
        else
          _LayerChips(renditionId: text.renditionId),
        Expanded(
          child: switch (original.kind) {
            RenditionKind.pdf => PdfViewerView(
              path: loaded.path,
              text: text,
              title: title,
            ),
            RenditionKind.html => WebPageViewerView(
              path: loaded.path,
              text: text,
              title: title,
              readAloud: text != null,
            ),
            _ when text == null => _Unreadable(path: loaded.path),
            _ => DocumentReaderView(
              title: title,
              content: text.content,
              markdown: text.markdown,
              study: text,
              showStudyBar: false,
            ),
          },
        ),
      ],
    );
  }
}

/// Una línea arriba del visor que dice por qué no hay marcas.
class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      key: const Key('processed-original-notice'),
      color: colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 20, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Qué se marca sobre la copia —el resumen, la síntesis y las palabras clave,
/// cada uno con su color de estudiar—, con su interruptor. Los fragmentos se
/// ven siempre: son lo que se cortó de acá. Cambia la vista de la copia, no la
/// de la fuente: la clave es la de la copia.
class _LayerChips extends ConsumerWidget {
  const _LayerChips({required this.renditionId});

  final String renditionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final palette = StudyPalette.of(theme.brightness);
    final view = ref.watch(studyViewProvider(renditionId));
    final notifier = ref.read(studyViewProvider(renditionId).notifier);

    Widget chip(
      String label,
      Color color,
      StudyView next, {
      required bool on,
    }) => FilterChip(
      avatar: CircleAvatar(backgroundColor: color, radius: 7),
      label: Text(label),
      selected: on,
      showCheckmark: false,
      onSelected: (_) => notifier.state = next,
    );

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Semantics(
          container: true,
          label: l10n.processedOriginalLayers,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              chip(
                l10n.processedSectionSummary,
                palette.summary,
                StudyView(
                  summary: !view.summary,
                  synthesis: view.synthesis,
                  keywords: view.keywords,
                ),
                on: view.summary,
              ),
              chip(
                l10n.processedSectionSynthesis,
                palette.synthesis,
                StudyView(
                  summary: view.summary,
                  synthesis: !view.synthesis,
                  keywords: view.keywords,
                ),
                on: view.synthesis,
              ),
              chip(
                l10n.processedSectionKeywords,
                palette.keyword,
                StudyView(
                  summary: view.summary,
                  synthesis: view.synthesis,
                  keywords: !view.keywords,
                ),
                on: view.keywords,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un Word, un EPUB o un texto cuyo texto ya no es el de la fuente: el lector
/// no tiene qué mostrar, y se ofrece abrirlo con otra app.
class _Unreadable extends ConsumerWidget {
  const _Unreadable({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return EmptyStateView(
      icon: Icons.description_outlined,
      title: l10n.processedOriginalUnreadable,
      actionLabel: l10n.processedOriginalOpenWith,
      onAction: () => unawaited(_open(context, ref)),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(fileOpenerProvider).open(path);
    final message = switch (result) {
      FileOpenResult.done => null,
      FileOpenResult.noAppAvailable => l10n.contentNoAppToOpen,
      FileOpenResult.fileNotFound ||
      FileOpenResult.failed => l10n.contentOpenFailed,
    };
    if (message == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
