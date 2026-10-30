import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_view_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_marks_line.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_view.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_first_page_preview.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/embedded_file_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/mobile_page_width.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_first_page_preview.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El original de un documento procesado, a la vista en su pantalla (F43,
/// paso 15, M3): como el detalle de la Biblioteca muestra el suyo
/// (`EmbeddedFileViewer`), sin tener que tocar nada para verlo.
///
/// - **El original**, en el mismo marco que en la Biblioteca y con lo mismo
///   adentro —la primera página quieta de un PDF o de un documento, la página
///   web archivada—, con lo marcado encima. El botón grande del centro y un
///   toque en la hoja abren el visor de siempre a pantalla completa
///   (`ProcessedOriginalScreen`).
/// - **Las fichas de estudio van adentro** (F45, paso 7b, mejora 15): el
///   resumen, la síntesis y las palabras clave se marcan, se prenden y se
///   apagan en el original entero, donde se tocan las oraciones. Acá, debajo
///   de la vista previa, un renglón dice qué tiene marcado
///   ([OriginalMarksLine]); si la fuente cambió su texto, por qué no hay
///   marcas.
/// - **Debajo, una línea** con qué es la copia, cuánto ocupa y cuándo se
///   copió. Borrarla sigue en «Más» (decisión K).
///
/// Sin copia del original no dibuja nada: el documento queda como estaba.
class ProcessedOriginalSection extends ConsumerWidget {
  const ProcessedOriginalSection({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final original = ref
        .watch(processedOriginalProvider(documentId))
        .valueOrNull;
    if (original == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final view = watchProcessedOriginalView(ref, documentId);
    final loaded = view.valueOrNull;
    final text = loaded?.text;
    void expand() =>
        unawaited(context.push(RoutePaths.processedOriginal(documentId)));

    return Padding(
      key: const Key('processed-original-section'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _frame(context, l10n, original, view, expand),
          const SizedBox(height: 8),
          if (text != null) ...[
            OriginalMarksLine(
              study: OriginalStudy(documentId: documentId, original: text),
            ),
            const SizedBox(height: 4),
          ] else if (loaded != null && loaded.exists) ...[
            _Line(
              key: const Key('processed-original-unmarked'),
              icon: Icons.info_outline,
              text: l10n.processedOriginalUnmarked,
            ),
            const SizedBox(height: 4),
          ],
          _Details(original: original),
        ],
      ),
    );
  }

  /// El original en su marco, como en la Biblioteca.
  Widget _frame(
    BuildContext context,
    AppLocalizations l10n,
    ProcessedOriginal original,
    AsyncValue<ProcessedOriginalView> view,
    VoidCallback expand,
  ) {
    final loaded = view.valueOrNull;
    if (loaded == null) {
      return view.hasError
          ? _Line(icon: Icons.error_outline, text: l10n.globalErrorUnexpected)
          : const EmbeddedViewerFrame(
              tall: true,
              child: Center(child: CircularProgressIndicator()),
            );
    }
    if (!loaded.exists) {
      return _Line(
        key: const Key('processed-original-missing'),
        icon: Icons.file_copy_outlined,
        text: l10n.failureMissingOriginalFile,
      );
    }
    final text = loaded.text;
    // En la web el almacén no tiene rutas de archivo: el PDF y la página se
    // ven en el visor entero, como en la Biblioteca.
    if (kIsWeb && original.kind != RenditionKind.document) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          key: const Key('processed-open-original'),
          onPressed: expand,
          icon: const Icon(Icons.visibility_outlined),
          label: Text(l10n.processedOriginalOpen),
        ),
      );
    }
    return switch (original.kind) {
      RenditionKind.pdf => EmbeddedViewerFrame(
        tall: true,
        onExpand: expand,
        bigButtonLabel: l10n.detailReadAsBook,
        child: PdfFirstPagePreview(
          path: loaded.path,
          text: text,
          onTap: expand,
        ),
      ),
      RenditionKind.html => EmbeddedViewerFrame(
        tall: true,
        onExpand: expand,
        bigButtonLabel: l10n.detailViewWebPage,
        // Como en el teléfono, también en la computadora (F45, paso 4,
        // decisión D).
        child: MobilePageWidth(
          child: WebPageViewerView(path: loaded.path, text: text, mobile: true),
        ),
      ),
      _ when text == null => EmbeddedViewerFrame(
        child: OriginalUnreadable(path: loaded.path),
      ),
      _ => EmbeddedViewerFrame(
        tall: true,
        onExpand: expand,
        bigButtonLabel: l10n.detailReadAsBook,
        child: _DocumentPreview(text: text, onTap: expand),
      ),
    };
  }
}

/// La primera página de un Word, un EPUB o un texto, con lo marcado.
class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({required this.text, required this.onTap});

  final StudyText text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DocumentFirstPagePreview(
    content: text.content,
    markdown: text.markdown,
    study: text,
    onTap: onTap,
  );
}

/// Qué es la copia, cuánto ocupa y cuándo se copió: «PDF · 26 kB · copiado
/// el 28 oct 2026».
class _Details extends StatelessWidget {
  const _Details({required this.original});

  final ProcessedOriginal original;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final date = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(original.copiedAt.toLocal());
    return _Line(
      key: const Key('processed-original-details'),
      icon: Icons.file_copy_outlined,
      text: l10n.processedOriginalCardDetails(
        originalKindLabel(l10n, original),
        formatFileSize(original.sizeBytes, l10n.localeName),
        date,
      ),
    );
  }
}

/// Una línea tenue con su ícono.
class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Qué es la copia, para quien la mira: un PDF, una página web archivada o un
/// documento —un Word, un EPUB, un texto—.
String originalKindLabel(AppLocalizations l10n, ProcessedOriginal original) =>
    switch (original.kind) {
      RenditionKind.pdf => l10n.processedOriginalKindPdf,
      RenditionKind.html => l10n.processedOriginalKindPage,
      _ => l10n.processedOriginalKindDocument,
    };
