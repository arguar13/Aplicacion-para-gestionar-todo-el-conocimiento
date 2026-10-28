import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/move_to_trash.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_readable.dart';
import 'package:sinapsis/features/processed/presentation/retriage.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_original_card.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_panel.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_study_slot.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_text_pages.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un documento procesado abierto (F41): lo que se sacó de una fuente.
///
/// - **Arriba, su fuente**: «Ver el original en la Biblioteca», y si la fuente
///   está en la papelera o se borró, lo dice. Al lado, «Volver a triar».
/// - **La copia del original**, si la tiene (decisión H): «Ver el original»
///   la abre en su visor con lo elegido marcado (`ProcessedOriginalCard`).
/// - **La tarjeta de estudiar** sobre su propio texto (decisión I), cuando lo
///   tenga: ver `ProcessedStudySlot`.
/// - **Sus secciones**, plegables y en el orden en que se leen, cada una con
///   sus partes editables. Se recorren las que el documento tiene: una
///   sección nueva entra sola.
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
          if (value != null && !value.inTrash)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.detailDelete,
              onPressed: () => _moveToTrash(context, ref),
            ),
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
          ProcessedOriginalCard(documentId: document.id),
          ProcessedStudySlot(document: document),
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
        ],
      ),
    );
  }
}

/// La fuente de la que salió: el enlace a ella, con lo que haga falta saber si
/// ya no está a la vista, y «Volver a triar».
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
