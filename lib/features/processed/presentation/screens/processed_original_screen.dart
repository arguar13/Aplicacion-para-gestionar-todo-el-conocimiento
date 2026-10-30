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
import 'package:sinapsis/features/processed/presentation/providers/processed_original_view_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_bar.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/mobile_page_width.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La copia del original de un documento procesado (F41, decisión H), en el
/// visor de siempre —el de PDF, el de páginas web o el lector—, con lo elegido
/// marcado encima: el resumen, la síntesis y las palabras clave con los
/// colores de estudiar, y los fragmentos con el de los cortes.
///
/// **Arriba, los botones de estudio** (F43, paso 15, M5: `OriginalStudyBar`):
/// el original es donde se marca, con la IA o a mano, tocando las oraciones o
/// las palabras en el visor; y donde se prende, se apaga y se oculta lo
/// marcado. Es la pantalla completa del original que el documento muestra
/// incrustado (`ProcessedOriginalSection`).
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
    final view = watchProcessedOriginalView(ref, documentId);
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
          _StudyBarPanel(
            study: OriginalStudy(documentId: documentId, original: text),
          ),
        Expanded(
          child: switch (original.kind) {
            RenditionKind.pdf => PdfViewerView(
              path: loaded.path,
              text: text,
              title: title,
            ),
            // Como en el teléfono, también en la computadora (F45, paso 4,
            // decisión D).
            RenditionKind.html => MobilePageWidth(
              child: WebPageViewerView(
                path: loaded.path,
                text: text,
                title: title,
                readAloud: text != null,
                mobile: true,
              ),
            ),
            _ when text == null => ProcessedOriginalUnreadable(
              path: loaded.path,
            ),
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

/// Los botones de estudio arriba del visor, sobre el color de la barra. Con
/// la letra grande pueden ocupar varios renglones: se desplazan dentro de un
/// alto acotado y el original sigue a la vista.
class _StudyBarPanel extends StatelessWidget {
  const _StudyBarPanel({required this.study});

  final OriginalStudy study;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.42),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: OriginalStudyBar(study: study),
        ),
      ),
    );
  }
}

/// Un Word, un EPUB o un texto cuyo texto ya no es el de la fuente: el lector
/// no tiene qué mostrar, y se ofrece abrirlo con otra app. Acá y en el
/// documento (`ProcessedOriginalSection`).
class ProcessedOriginalUnreadable extends ConsumerWidget {
  const ProcessedOriginalUnreadable({required this.path, super.key});

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
