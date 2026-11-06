import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/services/index_match.dart';
import 'package:sinapsis/features/index/domain/services/index_outline.dart';
import 'package:sinapsis/features/index/presentation/index_opening.dart';
import 'package:sinapsis/features/index/presentation/providers/index_providers.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_rows.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que encuentra el buscador del Índice (F46), **con su jerarquía**: un
/// capítulo que coincide se ve con su documento arriba —fijo mientras se
/// recorren sus coincidencias, con sus temas— y los capítulos que lo
/// contienen, más tenues; lo buscado, resaltado.
///
/// Arriba, los documentos cuyo título coincide: la búsqueda de la base es de
/// capítulos e imágenes, y los títulos de los documentos se filtran sobre la
/// lista de todos.
///
/// Mientras se escribe se sigue viendo lo anterior hasta que llega lo nuevo:
/// cada letra no deja la pantalla en blanco.
class IndexSearchView extends ConsumerStatefulWidget {
  const IndexSearchView({required this.query, super.key});

  final String query;

  @override
  ConsumerState<IndexSearchView> createState() => _IndexSearchViewState();
}

class _IndexSearchViewState extends ConsumerState<IndexSearchView> {
  List<IndexSearchHit>? _lastHits;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = widget.query;
    final hits = ref.watch(indexSearchProvider(query));
    final documents = ref.watch(
      indexDocumentsProvider(IndexDocumentOrder.title),
    );
    if (hits.valueOrNull case final value?) _lastHits = value;
    final shown = _lastHits;
    final allDocuments = documents.valueOrNull;

    if (hits.hasError && !hits.hasValue) {
      return EmptyStateView(
        icon: Icons.error_outline,
        title: l10n.globalErrorUnexpected,
      );
    }
    if (shown == null || allDocuments == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final matchingDocuments = [
      for (final document in allDocuments)
        if (indexTitleMatches(document.title, query)) document,
    ];
    final groups = groupIndexSearch(shown);
    // Lo de la búsqueda anterior que todavía se ve no dice «no hay nada».
    final settled = hits.hasValue;
    if (settled && groups.isEmpty && matchingDocuments.isEmpty) {
      return EmptyStateView(
        key: const Key('index-search-empty'),
        icon: Icons.search_off,
        title: l10n.f46P3SearchEmpty(query),
        message: l10n.f46P3SearchEmptyMessage,
      );
    }

    return CustomScrollView(
      key: const PageStorageKey('index-search'),
      slivers: [
        if (matchingDocuments.isNotEmpty) ...[
          _SectionLabel(l10n.f46P3SearchDocuments),
          SliverList.builder(
            itemCount: matchingDocuments.length,
            itemBuilder: (context, index) {
              final document = matchingDocuments[index];
              return IndexDocumentRow(
                key: ValueKey('search-document-${document.id}'),
                document: document,
                place: const IndexDocumentPlace.listed(),
                query: query,
                onTap: () => openIndexEntry(
                  context,
                  ref,
                  IndexOpening(documentId: document.id),
                ),
              );
            },
          ),
        ],
        if (groups.isNotEmpty) ...[
          _SectionLabel(l10n.f46P3SearchChapters),
          for (final group in groups)
            _SearchGroup(
              key: ValueKey('search-group-${group.documentId}'),
              group: group,
              document: allDocuments
                  .where((d) => d.id == group.documentId)
                  .firstOrNull,
              query: query,
            ),
        ],
        if (shown.length >= kIndexSearchLimit)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                l10n.f46P3SearchCapped(kIndexSearchLimit),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Semantics(
        header: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Las coincidencias de un documento: el documento, fijo arriba mientras se
/// recorren, y cada coincidencia con los capítulos que la contienen.
class _SearchGroup extends ConsumerWidget {
  const _SearchGroup({
    required this.group,
    required this.document,
    required this.query,
    super.key,
  });

  final IndexSearchGroup group;

  /// Su fila de la lista de todos, con sus cuentas; `null` mientras esa
  /// lista no lo trae —uno que acaba de llegar—, y se arma con lo que dice
  /// la coincidencia.
  final IndexDocument? document;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = group.first;
    final shown =
        document ??
        IndexDocument(
          id: group.documentId,
          title: first.documentTitle,
          sourceKind: first.sourceKind,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          chapterCount: 0,
          imageCount: 0,
          hasText: true,
          indexed: true,
          spaceIds: first.spaceIds,
        );
    return SliverMainAxisGroup(
      slivers: [
        PinnedHeaderSliver(
          child: IndexDocumentRow(
            key: ValueKey('search-header-${group.documentId}'),
            document: shown,
            place: const IndexDocumentPlace.listed(),
            pinned: true,
            showsCount: document != null,
            onTap: () => openIndexEntry(
              context,
              ref,
              IndexOpening(documentId: group.documentId),
            ),
          ),
        ),
        SliverList.builder(
          itemCount: group.rows.length,
          itemBuilder: (context, index) {
            final row = group.rows[index];
            return IndexEntryRow(
              key: ValueKey('search-entry-${row.entry.key}'),
              row: IndexOutlineRow(
                entry: row.entry,
                hasChildren: false,
                unfolded: true,
              ),
              matched: row.matched,
              query: query,
              onOpen: () =>
                  openIndexEntry(context, ref, IndexOpening.of(row.entry)),
            );
          },
        ),
      ],
    );
  }
}
