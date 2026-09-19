import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los pares de elementos que se contradicen entre sí, en toda la bóveda.
///
/// Una lente sobre `RelationKind.contradicts` —no un octavo destino de
/// navegación, ni un `RelationKind` más tratado igual que el resto (ver la
/// decisión sobre F5, D12)—: filtra `allRelationEdgesProvider` client-side,
/// sin distinguir si el vínculo se creó a mano, por el diálogo manual del
/// grafo, o por el motor automático — `Relations` no tiene columna de
/// procedencia.
///
/// Cada contradicción se puede marcar como revisada (F9): lo que queda sin
/// marcar es lo que falta mirar, y es lo que cuenta el panel de salud. La
/// lista arranca con lo pendiente; las revisadas se incluyen con un filtro.
class TensionScreen extends ConsumerStatefulWidget {
  const TensionScreen({super.key});

  @override
  ConsumerState<TensionScreen> createState() => _TensionScreenState();
}

class _TensionScreenState extends ConsumerState<TensionScreen> {
  var _showReviewed = false;

  Future<void> _setReviewed(RelationEdge edge, {required bool reviewed}) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // Se toma antes de esperar: si la pantalla se cierra, el "Deshacer" del
    // aviso —que la sobrevive— no puede leer de un `ref` ya descartado.
    final repository = ref.read(organizeRepositoryProvider);

    final result = await repository.setRelationReviewed(
      relationId: edge.id,
      reviewed: reviewed,
    );

    messenger.hideCurrentSnackBar();
    final failure = result.getLeft().toNullable();
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(failure.localizedMessage(l10n))),
      );
      return;
    }
    if (!reviewed) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.tensionMarkedReviewed),
        action: SnackBarAction(
          label: l10n.tensionUndoAction,
          onPressed: () => unawaited(
            repository.setRelationReviewed(
              relationId: edge.id,
              reviewed: false,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = ref.watch(libraryItemsProvider(const LibraryQuery()));
    final edges = ref.watch(allRelationEdgesProvider);

    return switch ((items, edges)) {
      (AsyncData(value: final items), AsyncData(value: final edges)) =>
        _TensionBody(
          items: items,
          edges: edges,
          showReviewed: _showReviewed,
          onToggleShowReviewed: () =>
              setState(() => _showReviewed = !_showReviewed),
          onSetReviewed: _setReviewed,
        ),
      (AsyncError(:final error), _) ||
      (_, AsyncError(:final error)) => Scaffold(
        appBar: AppBar(title: Text(l10n.tensionTitle)),
        body: Center(child: Text('$error')),
      ),
      _ => Scaffold(
        appBar: AppBar(title: Text(l10n.tensionTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

/// Una contradicción con los dos elementos ya resueltos.
typedef _Contradiction = (RelationEdge, KnowledgeItem, KnowledgeItem);

class _TensionBody extends StatelessWidget {
  const _TensionBody({
    required this.items,
    required this.edges,
    required this.showReviewed,
    required this.onToggleShowReviewed,
    required this.onSetReviewed,
  });

  final List<KnowledgeItem> items;
  final List<RelationEdge> edges;
  final bool showReviewed;
  final VoidCallback onToggleShowReviewed;
  final Future<void> Function(RelationEdge edge, {required bool reviewed})
  onSetReviewed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final itemsById = {for (final item in items) item.id: item};

    final pairs = <_Contradiction>[
      for (final edge in edges)
        if (edge.kind == RelationKind.contradicts)
          if (itemsById[edge.fromItemId] case final from?)
            if (itemsById[edge.toItemId] case final to?) (edge, from, to),
    ];
    final pending = [
      for (final pair in pairs)
        if (pair.$1.reviewedAt == null) pair,
    ];
    final reviewed = [
      for (final pair in pairs)
        if (pair.$1.reviewedAt != null) pair,
    ];
    // Lo pendiente primero: es lo que hay que mirar.
    final shown = showReviewed ? [...pending, ...reviewed] : pending;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tensionTitle)),
      body: pairs.isEmpty
          ? _CenteredMessage(l10n.tensionEmpty)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.tensionPendingCount(pending.length),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (reviewed.isNotEmpty)
                        FilterChip(
                          label: Text(
                            l10n.tensionShowReviewed(reviewed.length),
                          ),
                          selected: showReviewed,
                          onSelected: (_) => onToggleShowReviewed(),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? _CenteredMessage(l10n.tensionAllReviewed)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: shown.length,
                          itemBuilder: (context, index) {
                            final (edge, from, to) = shown[index];
                            final isReviewed = edge.reviewedAt != null;
                            return _ContradictionCard(
                              key: ValueKey(edge.id),
                              from: from,
                              to: to,
                              reviewed: isReviewed,
                              onToggleReviewed: () =>
                                  onSetReviewed(edge, reviewed: !isReviewed),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

/// Un par que se contradice, con los dos títulos tocables por separado —
/// cada uno navega a su propio detalle, en vez de que la fila entera apunte
/// a uno solo de los dos y deje al otro sin forma de llegar desde acá.
class _ContradictionCard extends StatelessWidget {
  const _ContradictionCard({
    required this.from,
    required this.to,
    required this.reviewed,
    required this.onToggleReviewed,
    super.key,
  });

  final KnowledgeItem from;
  final KnowledgeItem to;
  final bool reviewed;
  final VoidCallback onToggleReviewed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: reviewed ? theme.colorScheme.surfaceContainerLow : null,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _ItemLink(item: from)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    RelationKind.contradicts.icon,
                    color: RelationKind.contradicts.color(theme.colorScheme),
                  ),
                ),
                Expanded(child: _ItemLink(item: to)),
                IconButton(
                  icon: Icon(
                    reviewed ? Icons.check_circle : Icons.check_circle_outline,
                    color: reviewed ? theme.colorScheme.primary : null,
                  ),
                  tooltip: reviewed
                      ? l10n.tensionMarkUnreviewed
                      : l10n.tensionMarkReviewed,
                  onPressed: onToggleReviewed,
                ),
              ],
            ),
            if (reviewed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l10n.tensionReviewedBadge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemLink extends StatelessWidget {
  const _ItemLink({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push(RoutePaths.itemDetail(item.id)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          item.title,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
