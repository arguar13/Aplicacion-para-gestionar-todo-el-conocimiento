import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/generate_quiz_button.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/move_to_trash.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/notes/presentation/widgets/generate_derived_note_button.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_readable.dart';
import 'package:sinapsis/features/processed/presentation/retriage.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/processed_original_section.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_more_menu.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_panel.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_study_tools.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_text_pages.dart';
import 'package:sinapsis/features/processed/presentation/widgets/source_text_button.dart';
import 'package:sinapsis/features/transform/presentation/widgets/foreign_video_text_offers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un documento procesado abierto (F41): lo que se sacó de una fuente.
///
/// - **Arriba, su fuente**: «Ver el original en la Biblioteca», y si la fuente
///   está en la papelera o se borró, lo dice. Al lado, «Volver a triar» y, si
///   su texto tiene algo que hacer, «El texto de la fuente» (F45, paso 3): lo
///   que estaba en el «Más» de la fuente, ver `SourceTextButton`.
/// - **El original a la vista**, si tiene su copia (decisión H; F43, paso 15,
///   M3): incrustado como en el detalle de la Biblioteca, con lo marcado
///   encima y los botones de estudio arriba —donde se marca el resumen, la
///   síntesis y las palabras clave, con la IA o a mano (M5)—; su botón grande
///   abre el visor entero. Ver `ProcessedOriginalSection`.
/// - **Lo que la IA organizó** con el documento, con «Para revisar», «Ver»,
///   «Deshacer todo» y «Revisar con otro modelo», cuando hizo algo.
/// - **Sin «Estudiar el documento»** (F43, decisión J): el resumen, la
///   síntesis y las palabras clave se marcan en el original y se extraen en
///   Repasar. Lo que el documento ya trajo como sección se ve en ellas.
/// - **Sus secciones**, plegables y en el orden en que se leen, cada una con
///   sus partes editables. Se recorren las que el documento tiene: una
///   sección nueva entra sola.
/// - **«En Repasar»** (F43, M6), al empezar lo de estudiar: lo creado con el
///   documento —también lo que lo usó como fuente desde un cuaderno o un
///   tema—, sus tarjetas para hoy con «Empezar» y «Crear en Repasar», con el
///   documento ya elegido. Tocar una creación abre su visor, y «atrás» vuelve
///   acá.
/// - **Su Mapa y sus Tarjetas de repaso** (decisión K): el grafo local y la
///   sección de tarjetas de siempre, sobre el documento. Las tarjetas con IA
///   salen de su texto procesado, y las que ya tenía la fuente se ven en «De
///   la fuente», plegadas.
/// - **Arriba**, lo que la fuente ya no ofrece porque queda de consulta: la
///   nota derivada ✨, el quiz y, en «Más», «Organizar con IA», «Buscar fechas
///   con IA», «Descargar con lo marcado» y «Borrar la copia del original»
///   —todos sobre lo procesado—.
/// - **Escuchar**: el botón flotante lee el documento entero, como en el
///   detalle de un elemento, empezando por la página del texto que se mira.
///
/// Nunca trae el texto entero a la pantalla: el texto se pide de a una página
/// y lo demás de a tandas, sección por sección.
class ProcessedDocumentScreen extends ConsumerWidget {
  const ProcessedDocumentScreen({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final document = ref.watch(processedDocumentProvider(documentId));
    final value = document.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          value?.title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (value != null && !value.inTrash) ...[
            ..._studyActions(ref, value),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.detailDelete,
              onPressed: () => _moveToTrash(context, ref),
            ),
          ],
        ],
      ),
      body: document.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyStateView(
          icon: Icons.error_outline,
          title: error is Failure
              ? error.localizedMessage(l10n)
              : l10n.globalErrorUnexpected,
        ),
        data: (document) => document == null
            ? EmptyStateView(
                icon: Icons.summarize_outlined,
                title: l10n.processedDocumentNotFound,
              )
            : _DocumentBody(document: document),
      ),
    );
  }

  /// La nota derivada ✨ y el quiz del documento, que salen de su texto
  /// procesado (los dos preguntan primero si el elemento es un procesado: ver
  /// `readProcessedCardText`), y «Más».
  List<Widget> _studyActions(WidgetRef ref, ProcessedDocument document) {
    final item = ref.watch(libraryItemProvider(document.id)).valueOrNull;
    return [
      GenerateDerivedNoteButton(
        sourceTitle: document.title,
        itemId: document.id,
      ),
      if (item != null) GenerateQuizButton(item: item),
      ProcessedMoreMenu(document: document),
    ];
  }

  /// A la papelera, con «Deshacer», y de vuelta adonde se estaba: de la
  /// fuente no toca nada.
  Future<void> _moveToTrash(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final moved = await moveToTrashWithUndo(context, ref, [documentId]);
    if (moved && router.canPop()) router.pop();
  }
}

class _DocumentBody extends ConsumerStatefulWidget {
  const _DocumentBody({required this.document});

  final ProcessedDocument document;

  @override
  ConsumerState<_DocumentBody> createState() => _DocumentBodyState();
}

class _DocumentBodyState extends ConsumerState<_DocumentBody> {
  ProcessedReadable? _readable;

  /// Por dónde empieza a leer quien no eligió: la página del texto que se
  /// mira. Un método y no una función nueva en cada construcción: el lector
  /// reconoce el documento por, entre otras cosas, este lugar
  /// (`ReadableDocument.startAt`).
  ReadablePlace? _startAt() {
    // El lector lo pregunta al empezar, y puede ser después de cerrar la
    // pantalla: ahí se lee desde el principio.
    final readable = _readable;
    if (readable == null || !mounted) return null;
    final page = ref.read(processedTextPageProvider(widget.document.id));
    final partId = textPageIdAt(readable, page);
    return partId == null
        ? null
        : (sourceKey: processedPartReadKey(partId), offset: 0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final document = widget.document;
    _readable = ref.watch(processedReadableProvider(document.id)).valueOrNull;
    final readable = _readable?.document.withStartAt(_startAt);
    final sections = document.summary.sections;

    return ReadableRegion(
      document: readable,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (document.inTrash) ...[
            _TrashedBanner(documentId: document.id),
            const SizedBox(height: 12),
          ],
          _SourceCard(document: document),
          const SizedBox(height: 12),
          // Un video con el texto en otro idioma (F45, paso 4).
          ForeignVideoTextNotice.processed(documentId: document.id),
          ProcessedOriginalSection(documentId: document.id),
          ProcessedAiLine(document: document),
          if (document.summary.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.processedDocumentEmpty,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final section in sections) ...[
            ProcessedSectionPanel(
              key: Key('processed-section-${section.name}'),
              document: document,
              section: section,
              readable: readable,
            ),
            const SizedBox(height: 12),
          ],
          ProcessedStudyTools(document: document),
        ],
      ),
    );
  }
}

/// La fuente de la que salió: el enlace a ella, con lo que haga falta saber si
/// ya no está a la vista, «Volver a triar» y «El texto de la fuente».
class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.document});

  final ProcessedDocument document;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final source = document.source;
    final kind = document.summary.sourceKind;

    final (String? title, String? notice) = switch (source) {
      null => (null, l10n.processedSourceGone),
      ProcessedSourceLink(inTrash: true) => (
        source.title,
        l10n.processedSourceInTrash,
      ),
      _ => (source.title, null),
    };

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(kind.icon, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kind.label(l10n),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (title != null)
                        Text(title, style: theme.textTheme.titleMedium),
                      if (notice != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          notice,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (source != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (source.inTrash)
                    FilledButton.tonalIcon(
                      key: const Key('processed-open-trash'),
                      onPressed: () => context.push(RoutePaths.trash),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l10n.processedOpenTrash),
                    )
                  else
                    FilledButton.tonalIcon(
                      key: const Key('processed-open-source'),
                      onPressed: () =>
                          context.push(RoutePaths.itemDetail(source.itemId)),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(l10n.processedOpenSource),
                    ),
                  // Una fuente en la papelera no se procesa: primero se
                  // restaura.
                  RetriageButton(
                    sourceItemId: source.itemId,
                    disabledReason: source.inTrash
                        ? l10n.processedRetriageSourceInTrash
                        : null,
                  ),
                  // Con la fuente en la papelera, primero se restaura: como
                  // volver a triarla.
                  if (!source.inTrash && offersSourceTextActions(kind))
                    SourceTextButton(sourceItemId: source.itemId),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// El documento está en la papelera: se puede leer igual, y se restaura de un
/// toque.
class _TrashedBanner extends ConsumerWidget {
  const _TrashedBanner({required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.delete_outline, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.processedDocumentInTrash,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              key: const Key('processed-restore'),
              style: TextButton.styleFrom(
                foregroundColor: colors.onErrorContainer,
              ),
              onPressed: () => unawaited(_restore(context, ref)),
              child: Text(l10n.trashRestore),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(libraryRepositoryProvider).restoreMany([
      documentId,
    ]);
    final failure = result.getLeft().toNullable();
    if (failure != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
    }
  }
}
