import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/design/widgets/topic_dimension_menu.dart';
import 'package:sinapsis/core/domain/entities/processed_depth.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/stats_charts.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/board_bridges.dart';
import 'package:sinapsis/features/map/domain/services/board_insights.dart';
import 'package:sinapsis/features/map/domain/services/board_stats.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_target.dart';
import 'package:sinapsis/features/organize/presentation/processed_depth_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El Resumen del Mapa (F14, rehecho en F44 paso 3): las cifras grandes de lo
/// procesado y nueve tarjetas —lo nuevo, para estudiar, dónde hay más
/// material, los puentes, lo más unido, lo suelto, las contradicciones, cómo
/// creció y cuánto se trabajó—, con el mismo diseño de las estadísticas de
/// Repasar (M17) para que la app hable un solo idioma visual.
///
/// Cada cosa lleva al Mapa (decisión D): tocar una cifra lo abre a su altura, y
/// tocar una fila, con ese tema o ese documento en foco ([onShowInMap]). El
/// Explorador queda para «Abrir», en la ficha del nodo.
///
/// [dashboard] e [insights] llegan aparte del mapa y pueden tardar un poco
/// más: mientras son `null`, lo que los necesita no se muestra.
class MapBoardView extends StatefulWidget {
  const MapBoardView({
    required this.snapshot,
    required this.dimension,
    required this.dashboard,
    required this.insights,
    required this.onShowInMap,
    required this.onOpenItem,
    required this.onOpenTension,
    required this.onStudyTopic,
    required this.onSuggestLinks,
    required this.onOrganize,
    super.key,
  });

  final KnowledgeMapSnapshot snapshot;

  /// Qué se mira: los textos dicen «temas», «etiquetas» o «valores» (F28).
  final TopicDimension dimension;
  final MapDashboard? dashboard;
  final BoardInsights? insights;

  /// Lleva al Mapa: a una altura, o con un tema o un documento en foco.
  final void Function(MapBoardTarget target) onShowInMap;

  /// Abre un documento: lo que se toca en los sueltos, que no tienen ningún
  /// vínculo que mostrar en el Mapa y sí, en su página, con qué vincularlos.
  final void Function(String itemId) onOpenItem;
  final VoidCallback onOpenTension;

  /// Abre Repasar con ese tema en el selector.
  final void Function(String valueId) onStudyTopic;

  /// «Sugerir vínculos» entre esos documentos, con la IA.
  final void Function(List<String> itemIds) onSuggestLinks;

  /// «Organizar con IA» esos documentos.
  final void Function(List<String> itemIds) onOrganize;

  @override
  State<MapBoardView> createState() => _MapBoardViewState();
}

class _MapBoardViewState extends State<MapBoardView> {
  late BoardStats _stats;
  late List<BoardBridge> _bridges;

  @override
  void initState() {
    super.initState();
    _derive();
  }

  void _derive() {
    final snapshot = widget.snapshot;
    _stats = boardStatsOf(snapshot.graph, snapshot.detection);
    _bridges = bridgesOf(snapshot.graph, snapshot.detection);
  }

  @override
  void didUpdateWidget(MapBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Las estadísticas y los puentes dependen solo del mapa: no se rehacen si
    // lo único que cambió es el tablero o lo que se cuenta aparte.
    if (oldWidget.snapshot != widget.snapshot) _derive();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.dashboard;
    final insights = widget.insights;
    final kind = topicSelectKind(widget.dimension);
    final graph = widget.snapshot.graph;
    final documents = insights?.figures.documents ?? dashboard?.itemCount;
    const gap = SizedBox(height: 16);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Figures(
                  kind: kind,
                  stats: _stats,
                  documents: documents,
                  figures: insights?.figures,
                  onShowInMap: widget.onShowInMap,
                ),
                if (insights != null) ...[
                  gap,
                  _NewCard(insights: insights, onShowInMap: widget.onShowInMap),
                  gap,
                  _StudyCard(
                    kind: kind,
                    insights: insights,
                    onShowInMap: widget.onShowInMap,
                    onStudyTopic: widget.onStudyTopic,
                  ),
                ],
                gap,
                _DensestCard(
                  kind: kind,
                  topics: _stats.densest,
                  total: documents,
                  onShowInMap: widget.onShowInMap,
                ),
                gap,
                _BridgesCard(
                  bridges: _bridges,
                  graph: graph,
                  onShowInMap: widget.onShowInMap,
                ),
                gap,
                _ConnectedCard(
                  pairs: _stats.connected,
                  onShowInMap: widget.onShowInMap,
                ),
                // Sin los documentos todavía, «nada suelto» podría no ser
                // cierto: se espera, salvo que ya haya temas aislados.
                if (insights != null || _stats.isolatedCount > 0) ...[
                  gap,
                  _LooseCard(
                    kind: kind,
                    stats: _stats,
                    insights: insights,
                    unassigned: widget.snapshot.unassignedItemIds,
                    onShowInMap: widget.onShowInMap,
                    onOpenItem: widget.onOpenItem,
                    onSuggestLinks: widget.onSuggestLinks,
                    onOrganize: widget.onOrganize,
                  ),
                ],
                if (dashboard != null) ...[
                  gap,
                  _ContradictionsCard(
                    dashboard: dashboard,
                    onShowInMap: widget.onShowInMap,
                    onOpenTension: widget.onOpenTension,
                  ),
                  if (dashboard.growth.isNotEmpty) ...[
                    gap,
                    _GrowthCard(points: dashboard.growth),
                  ],
                  gap,
                  _DepthCard(dashboard: dashboard),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Piezas comunes ──────────────────────────────────────────────────────

/// Una línea tenue: lo que dice una tarjeta vacía.
class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// El encabezado de un grupo dentro de una tarjeta: «Con tarjetas para hoy».
class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.text, {this.top = 0});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 4),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Una fila que se toca: un tema, un par o un documento, con su línea de
/// abajo si la tiene.
///
/// Para el lector de pantalla es un solo botón con [semanticsLabel] y la
/// acción de tocar: el `Semantics` lleva su propio `onTap`, porque excluir lo
/// de adentro excluye también la acción del `InkWell`.
class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.rowKey,
    required this.onTap,
    required this.semanticsLabel,
    required this.child,
  });

  final Key rowKey;
  final VoidCallback onTap;
  final String semanticsLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      label: semanticsLabel,
      hint: l10n.f44S3OpenMapHint,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: rowKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          // El mínimo de un blanco táctil.
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Un título con su línea de abajo, para una fila.
class _TitleCaption extends StatelessWidget {
  const _TitleCaption({required this.title, this.caption});

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
        ),
        if (caption != null)
          Text(
            caption!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// «y 4 más», debajo de una lista cortada.
class _More extends StatelessWidget {
  const _More(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2),
      child: _Muted(l10n.mapBoardMore(count)),
    );
  }
}

/// La fecha corta de algo de «Lo nuevo»: «28 oct».
String _shortDate(BuildContext context, DateTime at) =>
    DateFormat.MMMd(Localizations.localeOf(context).toString()).format(at);

// ── Las cifras grandes ──────────────────────────────────────────────────

class _Figures extends StatelessWidget {
  const _Figures({
    required this.kind,
    required this.stats,
    required this.documents,
    required this.figures,
    required this.onShowInMap,
  });

  final String kind;
  final BoardStats stats;

  /// `null` hasta que se sepa.
  final int? documents;

  /// Con lo que sumó cada cifra; `null` hasta que llegue.
  final BoardFigures? figures;
  final void Function(MapBoardTarget target) onShowInMap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final f = figures;
    final links = f?.links;
    final tiles = [
      (
        MapBoardFigure.documents,
        documents,
        l10n.f44S3FigureDocuments(documents ?? 0),
        f?.documentsAdded,
      ),
      (
        MapBoardFigure.topics,
        stats.topicCount,
        l10n.f44S3FigureTopics(kind, stats.topicCount),
        f?.topicsAdded,
      ),
      (
        MapBoardFigure.communities,
        stats.communityCount,
        l10n.f44S3FigureCommunities(stats.communityCount),
        f?.communitiesAdded,
      ),
      (
        MapBoardFigure.links,
        links,
        l10n.f44S3FigureLinks(links ?? 0),
        f?.linksAdded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        const spacing = 12.0;
        // Por filas, y cada fila con el alto de su cifra más alta: las cuatro
        // quedan parejas aunque una diga más que otra.
        return Column(
          children: [
            for (var start = 0; start < tiles.length; start += columns) ...[
              if (start > 0) const SizedBox(height: spacing),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = start; i < start + columns; i++) ...[
                      if (i > start) const SizedBox(width: spacing),
                      Expanded(
                        child: _FigureTile(
                          figure: tiles[i].$1,
                          value: tiles[i].$2,
                          label: tiles[i].$3,
                          added: tiles[i].$4,
                          onTap: () => onShowInMap(MapBoardLevel(tiles[i].$1)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Una cifra grande que se toca: el número, qué cuenta y lo que sumó en 30
/// días.
class _FigureTile extends StatelessWidget {
  const _FigureTile({
    required this.figure,
    required this.value,
    required this.label,
    required this.added,
    required this.onTap,
  });

  final MapBoardFigure figure;
  final int? value;
  final String label;

  /// `null` mientras no se sabe: no se dice nada.
  final int? added;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final number = value == null ? '—' : '$value';
    final change = switch (added) {
      null => null,
      0 => l10n.f44S3FigureSteady,
      final n => l10n.f44S3FigureAdded(n),
    };

    return Semantics(
      label: [number, label, ?change].join(', '),
      hint: l10n.f44S3OpenMapHint,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('map-board-figure-${figure.name}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  number,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(label, style: theme.textTheme.labelLarge),
                if (change != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    change,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: (added ?? 0) > 0
                          ? colors.tertiary
                          : colors.onSurfaceVariant,
                      fontWeight: (added ?? 0) > 0 ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Lo nuevo ────────────────────────────────────────────────────────────

class _NewCard extends StatelessWidget {
  const _NewCard({required this.insights, required this.onShowInMap});

  final BoardInsights insights;
  final void Function(MapBoardTarget target) onShowInMap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = insights.newItems;
    final links = insights.newLinks;

    return StatsSection(
      key: const ValueKey('map-board-new'),
      title: l10n.f44S3NewTitle,
      subtitle: l10n.f44S3NewSubtitle,
      child: items.isEmpty && links.isEmpty
          ? _Muted(l10n.f44S3NewNone)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (items.isNotEmpty) ...[
                  _GroupHeading(l10n.f44S3NewDocuments(insights.newItemCount)),
                  for (final item in items)
                    _TapRow(
                      rowKey: ValueKey('map-new-item-${item.id}'),
                      onTap: () => onShowInMap(MapBoardItem(item.id)),
                      semanticsLabel: [
                        item.title,
                        _shortDate(context, item.createdAt),
                        ?item.topic?.label,
                      ].join(', '),
                      child: _TitleCaption(
                        title: item.title,
                        caption: [
                          _shortDate(context, item.createdAt),
                          ?item.topic?.label,
                        ].join(' · '),
                      ),
                    ),
                  _More(insights.newItemCount - items.length),
                ],
                if (links.isNotEmpty) ...[
                  _GroupHeading(
                    l10n.f44S3NewLinks(insights.newLinkCount),
                    top: items.isEmpty ? 0 : 12,
                  ),
                  for (final link in links)
                    _TapRow(
                      rowKey: ValueKey(
                        'map-new-link-${link.fromId}-${link.toId}',
                      ),
                      onTap: () => onShowInMap(MapBoardItem(link.fromId)),
                      semanticsLabel:
                          '${link.fromTitle}, ${link.toTitle}, '
                          '${_shortDate(context, link.createdAt)}',
                      child: _TitleCaption(
                        title: '${link.fromTitle}  ↔  ${link.toTitle}',
                        caption: _shortDate(context, link.createdAt),
                      ),
                    ),
                  _More(insights.newLinkCount - links.length),
                ],
              ],
            ),
    );
  }
}

// ── Para estudiar ───────────────────────────────────────────────────────

class _StudyCard extends StatelessWidget {
  const _StudyCard({
    required this.kind,
    required this.insights,
    required this.onShowInMap,
    required this.onStudyTopic,
  });

  final String kind;
  final BoardInsights insights;
  final void Function(MapBoardTarget target) onShowInMap;
  final void Function(String valueId) onStudyTopic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final due = insights.dueTopics;
    final uncarded = insights.uncardedTopics;

    return StatsSection(
      key: const ValueKey('map-board-study'),
      title: l10n.f44S3StudyTitle,
      subtitle: l10n.f44S3StudySubtitle(kind),
      child: due.isEmpty && uncarded.isEmpty
          ? _Muted(l10n.f44S3StudyNone)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (due.isNotEmpty) ...[
                  _GroupHeading(l10n.f44S3StudyDueHeading),
                  for (final topic in due)
                    _StudyRow(
                      group: 'due',
                      topic: topic,
                      caption: l10n.f44S3StudyDue(topic.dueToday),
                      onShowInMap: onShowInMap,
                      onStudyTopic: onStudyTopic,
                    ),
                ],
                if (uncarded.isNotEmpty) ...[
                  _GroupHeading(
                    l10n.f44S3StudyUncardedHeading,
                    top: due.isEmpty ? 0 : 12,
                  ),
                  for (final topic in uncarded)
                    _StudyRow(
                      group: 'uncarded',
                      topic: topic,
                      caption: l10n.f44S3StudyUncarded(topic.documents),
                      onShowInMap: onShowInMap,
                      onStudyTopic: onStudyTopic,
                    ),
                ],
              ],
            ),
    );
  }
}

/// Un tema de «Para estudiar»: tocarlo lo lleva al Mapa, y «Estudiar» abre
/// Repasar con él.
///
/// Con la letra grande en un teléfono el botón no entra al lado del nombre
/// sin aplastarlo: baja debajo, alineado al final.
class _StudyRow extends StatelessWidget {
  const _StudyRow({
    required this.group,
    required this.topic,
    required this.caption,
    required this.onShowInMap,
    required this.onStudyTopic,
  });

  final String group;
  final BoardStudyTopic topic;
  final String caption;
  final void Function(MapBoardTarget target) onShowInMap;
  final void Function(String valueId) onStudyTopic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final node = topic.topic;
    final info = _TapRow(
      rowKey: ValueKey('map-study-$group-${node.valueId}'),
      onTap: () => onShowInMap(MapBoardTopic(node.valueId)),
      semanticsLabel: '${node.label}, $caption',
      child: _TitleCaption(title: node.label, caption: caption),
    );
    final button = Semantics(
      label: l10n.f44S3StudySemantics(node.label),
      button: true,
      onTap: () => onStudyTopic(node.valueId),
      excludeSemantics: true,
      child: FilledButton.tonalIcon(
        key: ValueKey('map-study-$group-action-${node.valueId}'),
        onPressed: () => onStudyTopic(node.valueId),
        icon: const Icon(Icons.school_outlined, size: 18),
        label: Text(l10n.f44S3StudyAction),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final large = MediaQuery.textScalerOf(context).scale(10) > 13;
        if (large && constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              info,
              Align(alignment: AlignmentDirectional.centerEnd, child: button),
              const SizedBox(height: 4),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: info),
            const SizedBox(width: 8),
            button,
          ],
        );
      },
    );
  }
}

// ── Temas con más material ──────────────────────────────────────────────

class _DensestCard extends StatelessWidget {
  const _DensestCard({
    required this.kind,
    required this.topics,
    required this.total,
    required this.onShowInMap,
  });

  /// Qué se agrupa: ver `topicSelectKind`.
  final String kind;
  final List<TopicNode> topics;

  /// Cuántos documentos hay en total, para el porcentaje; `null` hasta que se
  /// sepa.
  final int? total;
  final void Function(MapBoardTarget target) onShowInMap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = statsMarkColor(
      theme.colorScheme.primary,
      theme.colorScheme.surfaceContainerLow,
    );
    final most = topics.isEmpty ? 1 : topics.first.itemCount;
    int percentOf(int count) {
      final all = total;
      if (all == null || all == 0) return 0;
      return (count * 100 / all).round();
    }

    return StatsSection(
      key: const ValueKey('map-board-densest'),
      title: l10n.mapBoardDensestTitle(kind),
      subtitle: l10n.f44S3DensestSubtitle,
      child: topics.isEmpty
          ? _Muted(l10n.f44S3DensestNone)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final topic in topics)
                  _TapRow(
                    rowKey: ValueKey('map-densest-${topic.valueId}'),
                    onTap: () => onShowInMap(MapBoardTopic(topic.valueId)),
                    semanticsLabel: l10n.f44S3DensestSemantics(
                      topic.label,
                      topic.itemCount,
                      percentOf(topic.itemCount),
                    ),
                    // El nombre y la cifra arriba, la barra abajo a todo lo
                    // ancho: con la letra al doble nada se aplasta.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                topic.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              total == null
                                  ? '${topic.itemCount}'
                                  : l10n.f44S3DensestShare(
                                      topic.itemCount,
                                      percentOf(topic.itemCount),
                                    ),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _Bar(fraction: topic.itemCount / most, color: color),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Una barra horizontal proporcional.
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: fraction.clamp(0.0, 1.0),
        minHeight: 8,
        color: color,
        backgroundColor: color.withValues(alpha: 0.14),
      ),
    );
  }
}

// ── Puentes ─────────────────────────────────────────────────────────────

class _BridgesCard extends StatelessWidget {
  const _BridgesCard({
    required this.bridges,
    required this.graph,
    required this.onShowInMap,
  });

  final List<BoardBridge> bridges;
  final TopicGraph graph;
  final void Function(MapBoardTarget target) onShowInMap;

  /// Lo que dice debajo de un puente: con qué comunidades se une —por el
  /// nombre de su tema principal, las tres más unidas y cuántas más—, o en
  /// cuántas partes quedaría lo de alrededor sin él.
  String _caption(AppLocalizations l10n, BoardBridge bridge) {
    if (bridge.joins.isEmpty) return l10n.f44S3BridgeParts(bridge.parts);
    const shown = 3;
    final names = [
      for (final community in bridge.joins.take(shown))
        graph.nodes[community.anchor].label,
    ].join(', ');
    final rest = bridge.joins.length - shown;
    return l10n.f44S3BridgeJoins(
      rest > 0 ? '$names ${l10n.mapBoardMore(rest)}' : names,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return StatsSection(
      key: const ValueKey('map-board-bridges'),
      title: l10n.f44S3BridgesTitle,
      subtitle: l10n.f44S3BridgesSubtitle,
      child: bridges.isEmpty
          ? _Muted(l10n.f44S3BridgesNone)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final bridge in bridges)
                  _TapRow(
                    rowKey: ValueKey('map-bridge-${bridge.topic.valueId}'),
                    onTap: () =>
                        onShowInMap(MapBoardTopic(bridge.topic.valueId)),
                    semanticsLabel:
                        '${bridge.topic.label}, ${_caption(l10n, bridge)}',
                    child: Row(
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.hub_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TitleCaption(
                            title: bridge.topic.label,
                            caption: _caption(l10n, bridge),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── Los más conectados ──────────────────────────────────────────────────

class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({required this.pairs, required this.onShowInMap});

  final List<ConnectedPair> pairs;
  final void Function(MapBoardTarget target) onShowInMap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return StatsSection(
      key: const ValueKey('map-board-connected'),
      title: l10n.mapBoardConnectedTitle,
      subtitle: l10n.f44S3ConnectedSubtitle,
      child: pairs.isEmpty
          ? _Muted(l10n.f44S3ConnectedNone)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final pair in pairs)
                  _TapRow(
                    rowKey: ValueKey(
                      'map-pair-${pair.first.valueId}-${pair.second.valueId}',
                    ),
                    onTap: () => onShowInMap(MapBoardTopic(pair.first.valueId)),
                    semanticsLabel: [
                      l10n.mapBoardPairSemantics(
                        pair.first.label,
                        pair.second.label,
                        pair.weight.toStringAsFixed(0),
                      ),
                      if (pair.edge.isTension) l10n.graphTensionTooltip,
                    ].join(', '),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${pair.first.label}  ↔  ${pair.second.label}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        if (pair.edge.isTension)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Tooltip(
                              message: l10n.graphTensionTooltip,
                              child: Icon(
                                Icons.bolt,
                                size: 18,
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          pair.weight.toStringAsFixed(0),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── Sueltos y aislados ──────────────────────────────────────────────────

class _LooseCard extends StatelessWidget {
  const _LooseCard({
    required this.kind,
    required this.stats,
    required this.insights,
    required this.unassigned,
    required this.onShowInMap,
    required this.onOpenItem,
    required this.onSuggestLinks,
    required this.onOrganize,
  });

  final String kind;
  final BoardStats stats;
  final BoardInsights? insights;

  /// Los documentos sin ningún valor de lo que se mira.
  final List<String> unassigned;
  final void Function(MapBoardTarget target) onShowInMap;
  final void Function(String itemId) onOpenItem;
  final void Function(List<String> itemIds) onSuggestLinks;
  final void Function(List<String> itemIds) onOrganize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final topics = stats.isolated;
    final looseIds = insights?.looseItemIds ?? const <String>[];
    final looseItems = insights?.looseItems ?? const <BoardLooseItem>[];
    // Lo que se le pide a la IA que ordene: lo suelto y lo que no tiene tema,
    // sin repetir.
    final toOrganize = {...looseIds, ...unassigned}.toList();

    return StatsSection(
      key: const ValueKey('map-board-loose'),
      title: l10n.f44S3LooseTitle,
      subtitle: l10n.f44S3LooseSubtitle,
      child: stats.isolatedCount == 0 && looseIds.isEmpty
          ? _Muted(l10n.f44S3LooseNone)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stats.isolatedCount > 0) ...[
                  _GroupHeading(
                    '${l10n.mapBoardIsolatedTitle(kind)} '
                    '(${stats.isolatedCount})',
                  ),
                  Text(
                    l10n.mapBoardIsolatedHint(kind),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final topic in topics)
                        ActionChip(
                          key: ValueKey('map-isolated-${topic.valueId}'),
                          label: Text(topic.label),
                          onPressed: () =>
                              onShowInMap(MapBoardTopic(topic.valueId)),
                        ),
                      _More(stats.isolatedCount - topics.length),
                    ],
                  ),
                ],
                if (looseIds.isNotEmpty) ...[
                  _GroupHeading(
                    l10n.f44S3LooseDocuments(looseIds.length),
                    top: stats.isolatedCount > 0 ? 12 : 0,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final item in looseItems)
                        ActionChip(
                          key: ValueKey('map-loose-${item.id}'),
                          avatar: const Icon(Icons.link_off, size: 18),
                          label: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () => onOpenItem(item.id),
                        ),
                      _More(looseIds.length - looseItems.length),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Hacen falta dos: uno de partida y otro con qué unirlo.
                    if (looseIds.length >= 2)
                      FilledButton.tonalIcon(
                        key: const ValueKey('map-loose-suggest'),
                        onPressed: () => onSuggestLinks(looseIds),
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(l10n.f44S3SuggestLinks),
                      ),
                    if (toOrganize.isNotEmpty)
                      OutlinedButton.icon(
                        key: const ValueKey('map-loose-organize'),
                        onPressed: () => onOrganize(toOrganize),
                        icon: const Icon(Icons.auto_fix_high, size: 18),
                        label: Text(l10n.mapOrganizeWithAi),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

// ── Contradicciones abiertas ────────────────────────────────────────────

class _ContradictionsCard extends StatelessWidget {
  const _ContradictionsCard({
    required this.dashboard,
    required this.onShowInMap,
    required this.onOpenTension,
  });

  final MapDashboard dashboard;
  final void Function(MapBoardTarget target) onShowInMap;
  final VoidCallback onOpenTension;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final open = dashboard.openContradictions;

    return StatsSection(
      key: const ValueKey('map-board-contradictions'),
      title: l10n.mapBoardContradictionsTitle,
      subtitle: l10n.f44S3ContradictionsSubtitle,
      child: open.isEmpty
          ? _Muted(l10n.mapBoardContradictionsNone)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in open)
                  _TapRow(
                    rowKey: ValueKey('map-contradiction-${c.relationId}'),
                    onTap: () => onShowInMap(MapBoardItem(c.fromId)),
                    semanticsLabel:
                        '${l10n.graphTensionTooltip}: '
                        '${c.fromTitle}, ${c.toTitle}',
                    child: Row(
                      children: [
                        Icon(
                          Icons.bolt,
                          size: 18,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${c.fromTitle}  ↔  ${c.toTitle}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    key: const ValueKey('map-contradictions-all'),
                    onPressed: onOpenTension,
                    child: Text(
                      l10n.mapBoardContradictionsAll(
                        dashboard.openContradictionCount,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Cómo creció ─────────────────────────────────────────────────────────

/// Lo procesado mes a mes, en columnas con su eje y sus meses: las piezas de
/// las estadísticas de Repasar (M17).
class _GrowthCard extends StatelessWidget {
  const _GrowthCard({required this.points});

  /// Un punto por mes, sin saltear ninguno: no está vacía.
  final List<GrowthPoint> points;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final month = DateFormat.yMMM(locale);
    final short = DateFormat.MMM(locale);
    String monthOf(GrowthPoint p) => month.format(DateTime(p.year, p.month));
    final last = points.length - 1;
    // Las puntas con el año —dicen de dónde a dónde va— y el medio, solo el
    // mes.
    final labels = <int, String>{
      0: monthOf(points.first),
      if (last >= 2)
        last ~/ 2: short.format(
          DateTime(points[last ~/ 2].year, points[last ~/ 2].month),
        ),
      last: monthOf(points.last),
    };

    return StatsSection(
      key: const ValueKey('map-board-growth'),
      title: l10n.f44S3GrowthTitle,
      subtitle: l10n.f44S3GrowthSubtitle,
      table: [
        for (final p in points.reversed)
          (monthOf(p), l10n.f44S3GrowthRow(p.added, p.total)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatsBarChart(
            key: const ValueKey('map-board-growth-chart'),
            bars: [
              for (final p in points)
                StatsBar(
                  values: [p.added.toDouble()],
                  description: l10n.f44S3GrowthBar(
                    monthOf(p),
                    p.added,
                    p.total,
                  ),
                ),
            ],
            colors: [
              statsMarkColor(
                theme.colorScheme.primary,
                theme.colorScheme.surfaceContainerLow,
              ),
            ],
            valueText: (bar) => '${bar.total.round()}',
            semanticsLabel: l10n.f44S3GrowthChartLabel(points.length),
            xLabels: labels,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.f44S3GrowthTotal(points.last.total),
            key: const ValueKey('map-board-growth-total'),
            style: theme.textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}

// ── Cuánto lo trabajaste ────────────────────────────────────────────────

/// Cuánto se trabajó lo procesado (F41, paso 6): cuántos documentos hay en
/// cada escalón, del texto copiado tal cual a las notas propias. Ocupa el
/// lugar de la madurez de las notas, que ya no están en el Mapa.
class _DepthCard extends StatelessWidget {
  const _DepthCard({required this.dashboard});

  final MapDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final segments = [
      for (final level in ProcessedDepth.values) (level, level.color(colors)),
    ];

    return StatsSection(
      key: const ValueKey('map-board-depth'),
      title: l10n.mapBoardDepthTitle,
      subtitle: l10n.f44S3DepthSubtitle,
      child: dashboard.itemCount == 0
          ? _Muted(l10n.mapBoardDepthNone)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 14,
                      child: Row(
                        children: [
                          for (final (level, color) in segments)
                            if ((dashboard.depth[level] ?? 0) > 0)
                              Expanded(
                                flex: dashboard.depth[level]!,
                                child: ColoredBox(color: color),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    for (final (level, color) in segments)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${level.label(l10n)}: '
                              '${dashboard.depth[level] ?? 0}',
                              key: ValueKey('map-depth-${level.name}'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}
