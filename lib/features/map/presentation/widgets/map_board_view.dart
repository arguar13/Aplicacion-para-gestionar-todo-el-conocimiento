import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/board_stats.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El tablero del mapa (F14): los números que resumen la bóveda vista por
/// temas —dónde hay más material, qué está más conectado, qué quedó solo— y
/// lo que el grafo no dice: las contradicciones abiertas, cuánto creció la
/// bóveda y qué tan trabajadas están las notas.
///
/// [dashboard] llega aparte del mapa y puede tardar un poco más: mientras es
/// `null`, las tarjetas que lo necesitan no se muestran.
class MapBoardView extends StatefulWidget {
  const MapBoardView({
    required this.snapshot,
    required this.dashboard,
    required this.onOpenTopic,
    required this.onOpenItem,
    required this.onOpenTension,
    super.key,
  });

  final KnowledgeMapSnapshot snapshot;
  final MapDashboard? dashboard;
  final void Function(String valueId) onOpenTopic;
  final void Function(String itemId) onOpenItem;
  final VoidCallback onOpenTension;

  @override
  State<MapBoardView> createState() => _MapBoardViewState();
}

class _MapBoardViewState extends State<MapBoardView> {
  late BoardStats _stats = _statsOf(widget.snapshot);

  static BoardStats _statsOf(KnowledgeMapSnapshot snapshot) =>
      boardStatsOf(snapshot.graph, snapshot.detection);

  @override
  void didUpdateWidget(MapBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Las estadísticas dependen solo del mapa: no se rehacen si lo único que
    // cambió es el tablero.
    if (oldWidget.snapshot != widget.snapshot) {
      _stats = _statsOf(widget.snapshot);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dashboard = widget.dashboard;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(label: Text(l10n.mapTopicCount(_stats.topicCount))),
                    Chip(
                      label: Text(
                        l10n.mapCommunityCount(_stats.communityCount),
                      ),
                    ),
                    if (dashboard != null)
                      Chip(label: Text(l10n.mapItemCount(dashboard.itemCount))),
                  ],
                ),
                const SizedBox(height: 12),
                _DensestCard(
                  topics: _stats.densest,
                  onOpenTopic: widget.onOpenTopic,
                ),
                _ConnectedCard(
                  pairs: _stats.connected,
                  onOpenTopic: widget.onOpenTopic,
                ),
                _IsolatedCard(
                  topics: _stats.isolated,
                  total: _stats.isolatedCount,
                  onOpenTopic: widget.onOpenTopic,
                ),
                if (dashboard != null) ...[
                  _ContradictionsCard(
                    dashboard: dashboard,
                    onOpenItem: widget.onOpenItem,
                    onOpenTension: widget.onOpenTension,
                  ),
                  _GrowthCard(points: dashboard.growth),
                  _MaturityCard(dashboard: dashboard),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Una tarjeta del tablero: título y contenido.
class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.cardKey, required this.title, this.child});

  final String cardKey;
  final String title;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('map-board-$cardKey'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
            if (child != null) ...[const SizedBox(height: 8), child!],
          ],
        ),
      ),
    );
  }
}

/// Una fila que se toca: un tema o un par.
class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.rowKey,
    required this.onTap,
    required this.child,
    this.semanticsLabel,
  });

  final Key rowKey;
  final VoidCallback onTap;
  final Widget child;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      excludeSemantics: semanticsLabel != null,
      child: InkWell(
        key: rowKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DensestCard extends StatelessWidget {
  const _DensestCard({required this.topics, required this.onOpenTopic});

  final List<TopicNode> topics;
  final void Function(String valueId) onOpenTopic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (topics.isEmpty) return const SizedBox.shrink();
    final most = topics.first.itemCount;
    final color = Theme.of(context).colorScheme.primary;

    return _BoardCard(
      cardKey: 'densest',
      title: l10n.mapBoardDensestTitle,
      child: Column(
        children: [
          for (final topic in topics)
            _TapRow(
              rowKey: ValueKey('map-densest-${topic.valueId}'),
              onTap: () => onOpenTopic(topic.valueId),
              semanticsLabel:
                  '${topic.label}: ${l10n.mapItemCount(topic.itemCount)}',
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(topic.label, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: _Bar(fraction: topic.itemCount / most, color: color),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${topic.itemCount}',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelLarge,
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
        backgroundColor: color.withValues(alpha: 0.12),
      ),
    );
  }
}

class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({required this.pairs, required this.onOpenTopic});

  final List<ConnectedPair> pairs;
  final void Function(String valueId) onOpenTopic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (pairs.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return _BoardCard(
      cardKey: 'connected',
      title: l10n.mapBoardConnectedTitle,
      child: Column(
        children: [
          for (final pair in pairs)
            _TapRow(
              rowKey: ValueKey(
                'map-pair-${pair.first.valueId}-${pair.second.valueId}',
              ),
              onTap: () => onOpenTopic(pair.first.valueId),
              semanticsLabel: l10n.mapBoardPairSemantics(
                pair.first.label,
                pair.second.label,
                pair.weight.toStringAsFixed(0),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${pair.first.label}  ↔  ${pair.second.label}',
                      overflow: TextOverflow.ellipsis,
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
                  SizedBox(
                    width: 44,
                    child: Text(
                      pair.weight.toStringAsFixed(0),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelLarge,
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

class _IsolatedCard extends StatelessWidget {
  const _IsolatedCard({
    required this.topics,
    required this.total,
    required this.onOpenTopic,
  });

  final List<TopicNode> topics;
  final int total;
  final void Function(String valueId) onOpenTopic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (total == 0) return const SizedBox.shrink();

    return _BoardCard(
      cardKey: 'isolated',
      title: '${l10n.mapBoardIsolatedTitle} ($total)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.mapBoardIsolatedHint,
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
                  onPressed: () => onOpenTopic(topic.valueId),
                ),
              if (total > topics.length)
                Text(l10n.mapBoardMore(total - topics.length)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContradictionsCard extends StatelessWidget {
  const _ContradictionsCard({
    required this.dashboard,
    required this.onOpenItem,
    required this.onOpenTension,
  });

  final MapDashboard dashboard;
  final void Function(String itemId) onOpenItem;
  final VoidCallback onOpenTension;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final open = dashboard.openContradictions;

    return _BoardCard(
      cardKey: 'contradictions',
      title: l10n.mapBoardContradictionsTitle,
      child: open.isEmpty
          ? Text(l10n.mapBoardContradictionsNone)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in open)
                  _TapRow(
                    rowKey: ValueKey('map-contradiction-${c.relationId}'),
                    onTap: () => onOpenItem(c.fromId),
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
                            overflow: TextOverflow.ellipsis,
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

class _GrowthCard extends StatelessWidget {
  const _GrowthCard({required this.points});

  final List<GrowthPoint> points;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (points.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final format = DateFormat.yMMM(locale);
    final first = points.first;
    final last = points.last;

    return _BoardCard(
      cardKey: 'growth',
      title: l10n.mapBoardGrowthTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            image: true,
            label: l10n.mapBoardGrowthSemantics(last.total, points.length),
            child: ExcludeSemantics(
              child: SizedBox(
                height: 72,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SparklinePainter(
                    totals: [for (final p in points) p.total],
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.mapBoardGrowthRange(
                  format.format(DateTime(first.year, first.month)),
                  format.format(DateTime(last.year, last.month)),
                ),
                style: theme.textTheme.bodySmall,
              ),
              Text(
                l10n.mapItemCount(last.total),
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// La línea del total de la bóveda mes a mes, con el área de abajo suavizada.
class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.totals, required this.color});

  final List<int> totals;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (totals.isEmpty) return;
    var low = totals.first;
    var high = totals.first;
    for (final total in totals) {
      if (total < low) low = total;
      if (total > high) high = total;
    }
    final span = (high - low).toDouble();
    const inset = 3.0;
    final height = size.height - 2 * inset;

    Offset at(int i) {
      final x = totals.length == 1
          ? size.width / 2
          : i / (totals.length - 1) * size.width;
      final y = span == 0
          ? size.height / 2
          : size.height - inset - (totals[i] - low) / span * height;
      return Offset(x, y);
    }

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < totals.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(at(totals.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();

    canvas
      ..drawPath(area, Paint()..color = color.withValues(alpha: 0.14))
      ..drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    if (totals.length == 1) {
      canvas.drawCircle(at(0), 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color || !_sameTotals(old.totals, totals);

  static bool _sameTotals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _MaturityCard extends StatelessWidget {
  const _MaturityCard({required this.dashboard});

  final MapDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final segments = [
      for (final level in NoteMaturity.values) (level, level.color(colors)),
    ];

    return _BoardCard(
      cardKey: 'maturity',
      title: l10n.mapBoardMaturityTitle,
      child: dashboard.noteCount == 0
          ? Text(l10n.mapBoardMaturityNone)
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
                            if ((dashboard.maturity[level] ?? 0) > 0)
                              Expanded(
                                flex: dashboard.maturity[level]!,
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
                          Text(
                            '${level.label(l10n)}: '
                            '${dashboard.maturity[level] ?? 0}',
                            key: ValueKey('map-maturity-${level.name}'),
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
