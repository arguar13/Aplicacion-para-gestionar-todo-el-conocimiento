import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
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
class TensionScreen extends ConsumerWidget {
  const TensionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final items = ref.watch(libraryItemsProvider(const LibraryQuery()));
    final edges = ref.watch(allRelationEdgesProvider);

    return switch ((items, edges)) {
      (AsyncData(value: final items), AsyncData(value: final edges)) =>
        _TensionBody(items: items, edges: edges),
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

class _TensionBody extends StatelessWidget {
  const _TensionBody({required this.items, required this.edges});

  final List<KnowledgeItem> items;
  final List<RelationEdge> edges;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final itemsById = {for (final item in items) item.id: item};

    final pairs = <(KnowledgeItem, KnowledgeItem)>[
      for (final edge in edges)
        if (edge.kind == RelationKind.contradicts)
          if (itemsById[edge.fromItemId] case final from?)
            if (itemsById[edge.toItemId] case final to?) (from, to),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tensionTitle)),
      body: pairs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.tensionEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: pairs.length,
              itemBuilder: (context, index) {
                final (from, to) = pairs[index];
                return _ContradictionCard(from: from, to: to);
              },
            ),
    );
  }
}

/// Un par que se contradice, con los dos títulos tocables por separado —
/// cada uno navega a su propio detalle, en vez de que la fila entera apunte
/// a uno solo de los dos y deje al otro sin forma de llegar desde acá.
class _ContradictionCard extends StatelessWidget {
  const _ContradictionCard({required this.from, required this.to});

  final KnowledgeItem from;
  final KnowledgeItem to;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
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
