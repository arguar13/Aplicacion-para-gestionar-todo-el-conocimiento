import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pick_living_note_dialog.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/suggested_property_chips.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/swipe_card.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/review_suggestions_action.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/suggestion_review_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La última fuente que se resolvió, para poder devolverla a la Bandeja.
class _LastAction {
  const _LastAction({required this.itemId, required this.title});

  final String itemId;
  final String title;
}

/// La Bandeja de entrada como un mazo de tarjetas: lo que el pipeline técnico
/// ya terminó y nadie decidió todavía qué hacer con eso
/// —`ItemState.processed`—, de a una fuente por vez.
///
/// Cada tarjeta se resuelve con un gesto —izquierda descarta, derecha la deja
/// triada, arriba la abre para extraer notas— o con la tecla equivalente
/// (flechas), o con su botón; los tres caminos hacen exactamente lo mismo. Las
/// propiedades que el modelo sugirió son chips: tocar uno lo acepta, tocarlo de
/// nuevo lo deshace. Lo último que se hizo se deshace con el botón, con
/// Ctrl+Z o desde el aviso, y devuelve la fuente a la Bandeja.
///
/// Solo fuentes (`D3` en el plan de F3): una nota no se tría, su progreso se
/// mide con su madurez, no con este flujo.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  _LastAction? _last;

  /// La fuente que se está viendo, para que las teclas sepan sobre cuál
  /// actúan.
  KnowledgeItem? _current;

  void _showSnack(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  /// Pasa la fuente a [to] y la recuerda para deshacer. Devuelve si salió bien.
  Future<bool> _transition(KnowledgeItem item, ItemState to) async {
    final result = await ref
        .read(inboxRepositoryProvider)
        .transitionState(itemId: item.id, to: to);
    if (!mounted) return false;

    final failure = result.getLeft().toNullable();
    if (failure != null) {
      _showSnack(failure.localizedMessage(AppLocalizations.of(context)!));
      return false;
    }

    setState(() => _last = _LastAction(itemId: item.id, title: item.title));
    return true;
  }

  Future<void> _discard(KnowledgeItem item) async {
    if (!await _transition(item, ItemState.discarded)) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    _showSnack(
      l10n.inboxDiscardedSnack(item.title),
      action: SnackBarAction(label: l10n.inboxUndo, onPressed: _undo),
    );
  }

  Future<void> _triage(KnowledgeItem item) async {
    if (!await _transition(item, ItemState.triaged)) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    _showSnack(
      l10n.inboxTriagedSnack(item.title),
      action: SnackBarAction(label: l10n.inboxUndo, onPressed: _undo),
    );
  }

  /// Abre la fuente para sacarle notas: la deja triada y, si tiene texto,
  /// abre la vista de lectura para destilar; si no, su detalle.
  Future<void> _extract(KnowledgeItem item) async {
    if (!await _transition(item, ItemState.triaged)) return;
    if (!mounted) return;

    if (extractableRendition(item) == null) {
      await context.push(RoutePaths.itemDetail(item.id));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReadingScreen(itemId: item.id)),
    );
  }

  /// Devuelve la última fuente a la Bandeja.
  Future<void> _undo() async {
    final last = _last;
    if (last == null) return;

    final result = await ref
        .read(inboxRepositoryProvider)
        .transitionState(itemId: last.itemId, to: ItemState.processed);
    if (!mounted) return;

    final failure = result.getLeft().toNullable();
    if (failure != null) {
      _showSnack(failure.localizedMessage(AppLocalizations.of(context)!));
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _last = null);
  }

  Future<void> _reviewSuggestions(
    KnowledgeItem item,
    List<Suggestion> suggestions,
  ) async {
    // Resuelto ANTES de transicionar: esta tarjeta se desmonta en cuanto el
    // elemento sale de `processed`, y con ella el `ref` de este widget deja de
    // servir —ver el porqué en `showSuggestionReviewDialog`—.
    final suggestionRepository = ref.read(suggestionRepositoryProvider);

    await ref
        .read(inboxRepositoryProvider)
        .transitionState(itemId: item.id, to: ItemState.triaged);
    if (!mounted) return;

    await showSuggestionReviewDialog(
      context,
      repository: suggestionRepository,
      suggestions: suggestions,
    );
  }

  Future<void> _linkToLivingNote(KnowledgeItem item) async {
    await ref
        .read(inboxRepositoryProvider)
        .transitionState(itemId: item.id, to: ItemState.triaged);
    if (!mounted) return;

    final noteId = await showDialog<String>(
      context: context,
      builder: (_) => PickLivingNoteDialog(excludeItemId: item.id),
    );
    if (noteId == null || !mounted) return;

    await ref
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: noteId,
          toItemId: item.id,
          kind: RelationKind.cites,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pendingIds = ref.watch(inboxPendingIdsProvider).valueOrNull;
    final last = _last;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inboxTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: last == null
                ? l10n.inboxUndo
                : '${l10n.inboxUndo}: ${last.title}',
            onPressed: last == null ? null : _undo,
          ),
          const ReviewSuggestionsAction(),
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
      // Las teclas hacen lo mismo que los gestos y los botones, sobre la
      // fuente que se está viendo. Ctrl+Z (o Cmd+Z) deshace lo último, y tiene
      // que andar también cuando eso dejó la Bandeja vacía.
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _withCurrent(_discard),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _withCurrent(_triage),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              _withCurrent(_extract),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        },
        child: Focus(autofocus: true, child: _buildBody(l10n, pendingIds)),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, List<String>? pendingIds) {
    if (pendingIds == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (pendingIds.isEmpty) {
      _current = null;
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
    _current = item;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _PendingItemCard(
        // Una tarjeta por fuente: el estado de la anterior —lo arrastrado, los
        // chips aceptados— no se hereda.
        key: ValueKey(item.id),
        item: item,
        onDiscard: () => _discard(item),
        onTriage: () => _triage(item),
        onExtract: () => _extract(item),
        onLink: () => _linkToLivingNote(item),
        onReviewSuggestions: (suggestions) =>
            _reviewSuggestions(item, suggestions),
      ),
    );
  }

  void _withCurrent(Future<void> Function(KnowledgeItem item) action) {
    final item = _current;
    if (item != null) unawaited(action(item));
  }
}

class _PendingItemCard extends ConsumerWidget {
  const _PendingItemCard({
    required this.item,
    required this.onDiscard,
    required this.onTriage,
    required this.onExtract,
    required this.onLink,
    required this.onReviewSuggestions,
    super.key,
  });

  final KnowledgeItem item;
  final VoidCallback onDiscard;
  final VoidCallback onTriage;
  final VoidCallback onExtract;
  final VoidCallback onLink;
  final ValueChanged<List<Suggestion>> onReviewSuggestions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rendition = extractableRendition(item);
    final excerpt = rendition == null
        ? null
        : rendition.content.length > 280
        ? '${rendition.content.substring(0, 280)}…'
        : rendition.content;
    // Un duplicado queda afuera del diálogo de revisión genérico (D4, F7):
    // fusionar borra un elemento, y eso pide su propia confirmación
    // explícita en la pantalla de "Posibles duplicados", no un casillero
    // más entre sugerencias reversibles con un toque. Una sugerencia de
    // referencia (F15) también: tiene su propia tarjeta, más abajo.
    final suggestions =
        (ref.watch(pendingSuggestionsProvider(item.id)).valueOrNull ?? const [])
            .where(
              (s) => s is! DuplicateSuggestionEntry && s is! MetadataSuggestion,
            )
            .toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SwipeCard(
            onSwipe: (direction) => switch (direction) {
              SwipeDirection.left => onDiscard(),
              SwipeDirection.right => onTriage(),
              SwipeDirection.up => onExtract(),
            },
            hints: {
              SwipeDirection.left: (
                label: l10n.inboxActionDiscard,
                color: scheme.error,
              ),
              SwipeDirection.right: (
                label: l10n.inboxActionTriage,
                color: scheme.tertiary,
              ),
              SwipeDirection.up: (
                label: l10n.inboxActionExtract,
                color: scheme.primary,
              ),
            },
            // Una fuente y una nota no se ven igual: acá siempre es una fuente.
            child: Card(
              margin: EdgeInsets.zero,
              color: item.source.kind.role.surface(scheme),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  item.source.kind.role.radius,
                ),
                side: BorderSide(color: item.source.kind.role.outline(scheme)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(item.source.kind.icon, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.source.kind.label(l10n),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
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
                          color: scheme.onSurfaceVariant,
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
                    SuggestedPropertyChips(itemId: item.id),
                    const Divider(height: 32),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: onDiscard,
                          icon: const Icon(Icons.archive_outlined),
                          label: Text(l10n.inboxActionDiscard),
                        ),
                        OutlinedButton.icon(
                          onPressed: onTriage,
                          icon: const Icon(Icons.check),
                          label: Text(l10n.inboxActionTriage),
                        ),
                        Tooltip(
                          message: rendition == null
                              ? l10n.inboxActionExtractDisabledTooltip
                              : '',
                          child: OutlinedButton.icon(
                            onPressed: rendition == null ? null : onExtract,
                            icon: const Icon(Icons.content_cut),
                            label: Text(l10n.inboxActionExtract),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: onLink,
                          icon: const Icon(Icons.link),
                          label: Text(l10n.inboxActionLink),
                        ),
                        if (suggestions.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () => onReviewSuggestions(suggestions),
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: Text(l10n.inboxActionReviewSuggestions),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.inboxShortcutsHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
