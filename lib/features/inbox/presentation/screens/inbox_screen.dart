import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/inbox/presentation/screens/extract_note_screen.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pick_living_note_dialog.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/suggestion_review_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La Bandeja de entrada: lo que el pipeline técnico ya terminó y nadie
/// decidió todavía qué hacer con eso —`ItemState.processed`—, de a un
/// elemento por vez, con hasta cuatro acciones de un toque —la 4ª,
/// revisar sugerencias, solo aparece si el modelo propuso alguna—.
///
/// Solo fuentes (`D3` en el plan de F3): una nota no se tría, su progreso
/// se mide con su madurez, no con este flujo.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pendingIds = ref.watch(inboxPendingIdsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inboxTitle),
        actions: [
          if (pendingIds != null && pendingIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  l10n.inboxPendingCount(pendingIds.length),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(context, ref, l10n, pendingIds),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<String>? pendingIds,
  ) {
    if (pendingIds == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (pendingIds.isEmpty) {
      return EmptyStateView(
        icon: Icons.inbox_outlined,
        title: l10n.inboxEmptyTitle,
        message: l10n.inboxEmptyBody,
      );
    }

    final item = ref.watch(libraryItemProvider(pendingIds.first)).valueOrNull;
    if (item == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _PendingItemCard(item: item);
  }
}

class _PendingItemCard extends ConsumerWidget {
  const _PendingItemCard({required this.item});

  final KnowledgeItem item;

  TextRendition? get _extractableRendition {
    final texts = item.renditions
        .whereType<TextRendition>()
        .where((r) => r.kind != RenditionKind.blocks)
        .toList();
    if (texts.isEmpty) return null;
    final primary = item.primaryRendition;
    if (primary is TextRendition && primary.kind != RenditionKind.blocks) {
      return primary;
    }
    return texts.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final rendition = _extractableRendition;
    final excerpt = rendition == null
        ? null
        : rendition.content.length > 280
        ? '${rendition.content.substring(0, 280)}…'
        : rendition.content;
    // Un duplicado queda afuera del diálogo de revisión genérico (D4, F7):
    // fusionar borra un elemento, y eso pide su propia confirmación
    // explícita en la pantalla de "Posibles duplicados", no un casillero
    // más entre sugerencias reversibles con un toque.
    final suggestions =
        (ref.watch(pendingSuggestionsProvider(item.id)).valueOrNull ?? const [])
            .where((s) => s is! DuplicateSuggestionEntry)
            .toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        item.source.kind.icon,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.source.kind.label(l10n),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(item.title, style: theme.textTheme.headlineSmall),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (excerpt != null)
                    Text(
                      excerpt,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          context.push(RoutePaths.itemDetail(item.id)),
                      icon: const Icon(Icons.open_in_full),
                      label: Text(l10n.inboxViewFull),
                    ),
                  ),
                  const Divider(height: 32),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _discard(context, ref),
                        icon: const Icon(Icons.archive_outlined),
                        label: Text(l10n.inboxActionDiscard),
                      ),
                      Tooltip(
                        message: rendition == null
                            ? l10n.inboxActionExtractDisabledTooltip
                            : '',
                        child: OutlinedButton.icon(
                          onPressed: rendition == null
                              ? null
                              : () => _extract(context, ref, rendition),
                          icon: const Icon(Icons.content_cut),
                          label: Text(l10n.inboxActionExtract),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _linkToLivingNote(context, ref),
                        icon: const Icon(Icons.link),
                        label: Text(l10n.inboxActionLink),
                      ),
                      if (suggestions.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () =>
                              _reviewSuggestions(context, ref, suggestions),
                          icon: const Icon(Icons.auto_awesome_outlined),
                          label: Text(l10n.inboxActionReviewSuggestions),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(inboxRepositoryProvider)
        .transitionState(itemId: item.id, to: ItemState.discarded);
    if (!context.mounted) return;
    final failure = result.getLeft().toNullable();
    if (failure != null) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
    }
  }

  Future<void> _extract(
    BuildContext context,
    WidgetRef ref,
    TextRendition rendition,
  ) async {
    await ref
        .read(inboxRepositoryProvider)
        .transitionState(itemId: item.id, to: ItemState.triaged);
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExtractNoteScreen(item: item, rendition: rendition),
      ),
    );
  }

  Future<void> _reviewSuggestions(
    BuildContext context,
    WidgetRef ref,
    List<Suggestion> suggestions,
  ) async {
    // Resuelto ANTES de transicionar: esta tarjeta se desmonta en cuanto
    // el elemento sale de `processed`, y con ella el `ref` de este
    // widget deja de servir —ver el porqué en `showSuggestionReviewDialog`—.
    final suggestionRepository = ref.read(suggestionRepositoryProvider);

    await ref
        .read(inboxRepositoryProvider)
        .transitionState(itemId: item.id, to: ItemState.triaged);
    if (!context.mounted) return;

    await showSuggestionReviewDialog(
      context,
      repository: suggestionRepository,
      suggestions: suggestions,
    );
  }

  Future<void> _linkToLivingNote(BuildContext context, WidgetRef ref) async {
    await ref
        .read(inboxRepositoryProvider)
        .transitionState(itemId: item.id, to: ItemState.triaged);
    if (!context.mounted) return;

    final noteId = await showDialog<String>(
      context: context,
      builder: (_) => PickLivingNoteDialog(excludeItemId: item.id),
    );
    if (noteId == null || !context.mounted) return;

    await ref
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: noteId,
          toItemId: item.id,
          kind: RelationKind.cites,
        );
  }
}
