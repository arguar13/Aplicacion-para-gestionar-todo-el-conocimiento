import 'package:flutter/material.dart';
import 'package:sinapsis/features/map/domain/entities/map_search.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «⚲ Buscar en el mapa» (F44, paso 5): escribís y aparecen los temas y los
/// documentos que coinciden, cada uno con dónde está; tocar uno lo devuelve, y
/// la pantalla deja el pedido para que el lienzo vuele hasta él
/// (`MapShowTopic`, `MapShowDocument`).
///
/// Busca en el índice que arma el motor con cada mapa (`insights.search`), en
/// memoria: escribir no cuesta una consulta por letra. Sin acentos ni
/// mayúsculas, lo que mejor coincide primero.
class MapSearchDelegate extends SearchDelegate<MapSearchEntry?> {
  MapSearchDelegate({
    required this.index,
    required this.topicKind,
    required this.communityName,
    required String hint,
  }) : super(searchFieldLabel: hint);

  final MapSearchIndex index;

  /// Qué es un tema acá: ver `topicSelectKind`.
  final String topicKind;

  /// Cómo se llama una comunidad —sus dos temas principales—, o `null` si el
  /// motor no la nombró.
  final String? Function(int communityId) communityName;

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        key: const ValueKey('map-search-clear'),
        tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
        icon: const Icon(Icons.close),
        onPressed: () {
          query = '';
          showSuggestions(context);
        },
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) =>
      BackButton(onPressed: () => close(context, null));

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  @override
  Widget buildResults(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (query.trim().isEmpty) {
      return _Message(text: l10n.f44S5SearchEmpty);
    }
    final hits = index.search(query);
    if (hits.isEmpty) {
      return _Message(
        key: const ValueKey('map-search-none'),
        text: l10n.f44S5SearchNone(query.trim()),
      );
    }
    return ListView.builder(
      key: const ValueKey('map-search-results'),
      itemCount: hits.length + 1,
      itemBuilder: (context, i) {
        // Arriba, cuántos hay: el lector de pantalla lo oye al cambiar.
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.f44S5SearchResults(hits.length),
                style: theme.textTheme.labelLarge,
              ),
            ),
          );
        }
        final hit = hits[i - 1];
        return ListTile(
          key: ValueKey('map-search-hit-${hit.kind.name}-${hit.id}'),
          leading: Icon(_iconOf(hit)),
          title: Text(hit.label, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(_placeOf(l10n, hit)),
          onTap: () => close(context, hit),
        );
      },
    );
  }

  static IconData _iconOf(MapSearchEntry hit) => switch (hit.kind) {
    MapSearchKind.topic => Icons.label_outline,
    MapSearchKind.document =>
      hit.isNote ? Icons.sticky_note_2_outlined : Icons.article_outlined,
  };

  /// Qué es y dónde está: un tema, en qué comunidad; un documento, en qué
  /// tema, o en la burbuja «Sin tema».
  String _placeOf(AppLocalizations l10n, MapSearchEntry hit) {
    switch (hit.kind) {
      case MapSearchKind.topic:
        final community = hit.communityId == null
            ? null
            : communityName(hit.communityId!);
        return community == null
            ? l10n.f44S5SearchTopic(topicKind)
            : l10n.f44S5SearchTopicIn(topicKind, community);
      case MapSearchKind.document:
        final role = hit.isNote ? 'note' : 'source';
        final topic = hit.topicValueId;
        return topic == null
            ? l10n.f44S5SearchDocumentUnthemed(
                role,
                l10n.f44S5LayerUnthemed(topicKind),
              )
            : l10n.f44S5SearchDocumentIn(
                role,
                index.topic(topic)?.label ?? topic,
              );
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
