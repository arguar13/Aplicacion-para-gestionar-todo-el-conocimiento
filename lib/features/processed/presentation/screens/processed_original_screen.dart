import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_view_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La copia del original de un documento procesado (F41, decisión H), en el
/// visor de siempre —el de PDF, el de páginas web o el lector—, con lo elegido
/// marcado encima: el resumen, la síntesis y las palabras clave con los
/// colores de estudiar, y los fragmentos con el de los cortes.
///
/// **Es la misma pantalla que el original de una fuente en la Biblioteca**
/// (F45, paso 7b, mejora 16, decisión H: [OriginalScreen] y [OriginalView]):
/// arriba, las tres fichas donde se marca, con la IA o a mano, tocando las
/// oraciones o las palabras en el visor (F43, paso 15, M5: `OriginalStudyBar`);
/// y donde se prende, se apaga y se oculta lo marcado. Es la pantalla completa
/// del original que el documento muestra en su vista previa
/// (`ProcessedOriginalSection`), que ya no lleva las fichas (mejora 15).
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

    return OriginalScreen(
      title: title,
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

    return OriginalView(
      format: originalFormatOf(original),
      path: loaded.path,
      title: title,
      text: text,
      study: text == null
          ? null
          : OriginalStudy(documentId: documentId, original: text),
      notice: text == null ? l10n.processedOriginalUnmarked : null,
    );
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
