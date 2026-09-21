import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/graph/domain/services/graph_view_fit.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/schema_layout.dart';
import 'package:sinapsis/features/map/domain/services/schema_tree_builder.dart';
import 'package:sinapsis/features/map/domain/services/svg_writer.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/map/presentation/widgets/arrow_head.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_export_handle.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El tamaño de la tarjeta de cada nodo del esquema.
const _kNodeWidth = 176.0;
const _kNodeHeight = 44.0;

/// El aire alrededor del esquema dentro del lienzo.
const _kCanvasMargin = 80.0;

/// El esquema del mapa (F14, D6): un árbol que parte de un tema y se despliega
/// al tocarlo, en modo radial o de árbol.
///
/// Los subtemas salen de la jerarquía del mapa; las notas mapa de cada tema y
/// los vínculos de cada nota, de la base, cuando se despliega el nodo. Cada
/// vínculo se dibuja con su tipo. Tocar un nodo con hijos lo despliega o lo
/// pliega; el botón de su borde abre el tema o el elemento.
class MapSchemaView extends ConsumerStatefulWidget {
  const MapSchemaView({
    required this.snapshot,
    required this.onOpenTopic,
    required this.onOpenItem,
    this.exportHandle,
    super.key,
  });

  final KnowledgeMapSnapshot snapshot;
  final void Function(String valueId) onOpenTopic;
  final void Function(String itemId) onOpenItem;

  /// Donde la vista ofrece su dibujo para exportarlo, si alguien lo quiere.
  final MapExportHandle? exportHandle;

  @override
  ConsumerState<MapSchemaView> createState() => _MapSchemaViewState();
}

class _MapSchemaViewState extends ConsumerState<MapSchemaView> {
  late SchemaRef _root;

  /// El nombre de la raíz cuando es un elemento: una nota mapa. Un tema se
  /// llama como en el grafo.
  String? _rootTitle;
  bool _radial = true;

  /// Los nodos desplegados, por clave.
  final Map<String, SchemaRef> _expanded = {};

  /// Lo que la base trajo de cada nodo desplegado, por clave.
  final Map<String, List<SchemaLink>> _links = {};

  final _controller = TransformationController();
  final _boundaryKey = GlobalKey();
  Size _viewport = Size.zero;
  bool _needsFit = true;

  late SchemaTree _tree;
  late Map<String, Offset> _positions;
  late Size _canvas;

  TopicGraph get _graph => widget.snapshot.graph;

  @override
  void initState() {
    super.initState();
    _root = _defaultRoot(_graph);
    _open(_root);
    _offerExport(widget.exportHandle);
  }

  void _offerExport(MapExportHandle? handle) {
    handle
      ?..png = (() => capturePng(_boundaryKey))
      ..svg = _exportSvg;
  }

  void _withdrawExport(MapExportHandle? handle) {
    handle
      ?..png = null
      ..svg = null;
  }

  @override
  void didUpdateWidget(MapSchemaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exportHandle != widget.exportHandle) {
      _withdrawExport(oldWidget.exportHandle);
      _offerExport(widget.exportHandle);
    }
    if (oldWidget.snapshot.sequence == widget.snapshot.sequence) return;
    // El mapa se recalculó: lo que la base trajo puede haber cambiado, y el
    // tema de partida puede haber dejado de existir.
    _links.clear();
    if (_root.kind == SchemaNodeKind.topic &&
        _graph.indexOf(_root.id) == null) {
      _open(_defaultRoot(_graph));
      return;
    }
    for (final node in _expanded.values) {
      unawaited(_fetch(node));
    }
    _rebuild();
  }

  @override
  void dispose() {
    _withdrawExport(widget.exportHandle);
    _controller.dispose();
    super.dispose();
  }

  /// El esquema como un documento SVG: las mismas uniones, con su tipo y su
  /// punta, y las mismas tarjetas que en pantalla.
  String _exportSvg() {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final svg = SvgWriter(
      width: _canvas.width,
      height: _canvas.height,
      background: scheme.surface,
    );

    for (final entry in _tree.entries.values) {
      final parent = entry.parentKey == null
          ? null
          : _positions[entry.parentKey];
      final child = _positions[entry.key];
      if (parent == null || child == null) continue;
      final relation = entry.relation;
      final color = relation == null
          ? scheme.outline.withValues(alpha: 0.6)
          : relation.color(scheme);
      svg.line(
        parent,
        child,
        color: color,
        strokeWidth: relation == RelationKind.contradicts ? 2.5 : 1.5,
      );
      if (relation != null) {
        final from = entry.outgoing ? parent : child;
        final to = entry.outgoing ? child : parent;
        final head = arrowHead(
          from,
          to,
          back: math.min((to - from).distance * 0.3, 40),
          length: 9,
          half: 5,
        );
        if (head != null) {
          svg.triangle(head.tip, head.left, head.right, fill: color);
        }
      }
      final label = switch (entry.edge) {
        SchemaEdgeKind.relation => relation?.shortLabel(l10n),
        SchemaEdgeKind.mapNote => l10n.mapSchemaEdgeMapNote,
        _ => null,
      };
      if (label != null) {
        final middle = (parent + child) / 2;
        svg.text(
          label,
          middle + const Offset(0, 4),
          color: scheme.onSurfaceVariant,
          size: 11,
        );
      }
    }

    for (final entry in _tree.entries.values) {
      final at = _positions[entry.key]!;
      final isTopic = entry.ref.kind == SchemaNodeKind.topic;
      final role = entry.isNote ? EntityRole.note : EntityRole.source;
      final accent = isTopic ? scheme.primary : role.accent(scheme);
      svg
        ..rect(
          Rect.fromCenter(center: at, width: _kNodeWidth, height: _kNodeHeight),
          fill: isTopic ? scheme.surfaceContainerHigh : role.surface(scheme),
          stroke: entry.expanded ? accent : accent.withValues(alpha: 0.5),
          strokeWidth: entry.expanded ? 2 : 1,
          radius: entry.isNote ? 22 : 8,
        )
        ..text(
          SvgWriter.ellipsize(entry.title, 22),
          Offset(at.dx - _kNodeWidth / 2 + 12, at.dy + 4),
          color: scheme.onSurface,
          anchor: 'start',
        );
    }
    return svg.build();
  }

  /// El tema de partida por defecto: el de primer nivel con más elementos.
  static SchemaRef _defaultRoot(TopicGraph graph) {
    TopicNode? best;
    for (final node in graph.nodes) {
      if (node.parentId != null) continue;
      if (best == null || node.itemCount > best.itemCount) best = node;
    }
    return SchemaRef.topic((best ?? graph.nodes.first).valueId);
  }

  /// Parte de [ref]: lo despliega y pide lo que le cuelga.
  void _open(SchemaRef node, {String? title}) {
    _root = node;
    _rootTitle = title;
    _expanded
      ..clear()
      ..[node.key] = node;
    _links.clear();
    _needsFit = true;
    unawaited(_fetch(node));
    _rebuild();
  }

  /// Pide a la base lo que cuelga de [node], y lo suma al esquema si sigue
  /// desplegado cuando llega.
  Future<void> _fetch(SchemaRef node) async {
    final links = await ref
        .read(knowledgeMapRepositoryProvider)
        .schemaLinks(node);
    if (!mounted || !_expanded.containsKey(node.key)) return;
    setState(() {
      _links[node.key] = links;
      _needsFit = true;
      _rebuild();
    });
  }

  void _toggle(SchemaEntry entry) {
    final expanding = !_expanded.containsKey(entry.key);
    setState(() {
      if (expanding) {
        _expanded[entry.key] = entry.ref;
      } else {
        _expanded.remove(entry.key);
      }
      _needsFit = true;
      _rebuild();
    });
    if (expanding && !_links.containsKey(entry.key)) {
      unawaited(_fetch(entry.ref));
    }
  }

  /// Arma el árbol y su layout con lo que hay ahora.
  void _rebuild() {
    _tree = buildSchemaTree(
      root: _root,
      rootTitle: _rootTitle,
      graph: _graph,
      expanded: _expanded.keys.toSet(),
      links: _links,
    );
    final layout = _radial ? layoutRadial(_tree.root) : layoutTree(_tree.root);
    final bounds = layout.bounds;
    final shift = Offset(
      _kCanvasMargin + _kNodeWidth / 2 - bounds.left,
      _kCanvasMargin + _kNodeHeight / 2 - bounds.top,
    );
    _positions = {
      for (final entry in layout.positions.entries)
        entry.key: entry.value + shift,
    };
    _canvas = Size(
      bounds.width + 2 * _kCanvasMargin + _kNodeWidth,
      bounds.height + 2 * _kCanvasMargin + _kNodeHeight,
    );
  }

  void _fitIfNeeded() {
    if (!_needsFit || _viewport.isEmpty) return;
    _needsFit = false;
    _controller.value = computeFitTransform(
      positions: _positions,
      viewportSize: _viewport,
      contentMargin: _kNodeWidth,
      maxScale: 1.2,
    );
  }

  Future<void> _pickRoot() async {
    final notes = ref.read(knowledgeMapRepositoryProvider).readMapNotes();
    final chosen = await showModalBottomSheet<_RootChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RootPicker(graph: _graph, notes: notes),
    );
    if (chosen == null || !mounted) return;
    setState(() => _open(chosen.ref, title: chosen.title));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rootEntry = _tree.entries[_tree.root.id];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('map-schema-root'),
                  onPressed: _pickRoot,
                  icon: Icon(
                    _root.kind == SchemaNodeKind.topic
                        ? Icons.label_outline
                        : Icons.account_tree_outlined,
                  ),
                  label: Text(
                    rootEntry?.title ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                key: const ValueKey('map-schema-mode'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.radar),
                    tooltip: l10n.mapSchemaRadial,
                  ),
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.account_tree_outlined),
                    tooltip: l10n.mapSchemaTree,
                  ),
                ],
                selected: {_radial},
                onSelectionChanged: (modes) => setState(() {
                  _radial = modes.single;
                  _needsFit = true;
                  _rebuild();
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewport = constraints.biggest;
              // Encuadrar después del cuadro: el `InteractiveViewer` ya existe.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _fitIfNeeded();
              });
              return ClipRect(
                child: InteractiveViewer(
                  key: const ValueKey('map-schema-canvas'),
                  transformationController: _controller,
                  constrained: false,
                  minScale: 0.2,
                  boundaryMargin: const EdgeInsets.all(600),
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    // Con fondo propio: el PNG sale opaco, del color de la
                    // pantalla.
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: SizedBox(
                        width: _canvas.width,
                        height: _canvas.height,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _EdgesPainter(
                                  entries: _tree.entries.values.toList(),
                                  positions: _positions,
                                  colors: Theme.of(context).colorScheme,
                                  mapNoteLabel: l10n.mapSchemaEdgeMapNote,
                                  relationLabel: (kind) =>
                                      kind.shortLabel(l10n),
                                  textColor: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            for (final entry in _tree.entries.values)
                              Positioned(
                                left:
                                    _positions[entry.key]!.dx - _kNodeWidth / 2,
                                top:
                                    _positions[entry.key]!.dy -
                                    _kNodeHeight / 2,
                                width: _kNodeWidth,
                                height: _kNodeHeight,
                                child: _NodeCard(
                                  entry: entry,
                                  onToggle: () => _toggle(entry),
                                  onOpen: () =>
                                      entry.ref.kind == SchemaNodeKind.topic
                                      ? widget.onOpenTopic(entry.ref.id)
                                      : widget.onOpenItem(entry.ref.id),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_tree.truncated)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              l10n.mapSchemaTruncated(_tree.entries.length),
              key: const ValueKey('map-schema-truncated'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// La tarjeta de un nodo: su ícono, su título y, si tiene hijos, cómo
/// desplegarlo.
class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.entry,
    required this.onToggle,
    required this.onOpen,
  });

  final SchemaEntry entry;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final isTopic = entry.ref.kind == SchemaNodeKind.topic;
    final role = entry.isNote ? EntityRole.note : EntityRole.source;
    final accent = isTopic ? colors.primary : role.accent(colors);
    final kind = isTopic
        ? l10n.mapSchemaNodeTopic
        : entry.edge == SchemaEdgeKind.mapNote
        ? l10n.mapSchemaNodeMapNote
        : entry.isNote
        ? l10n.mapSchemaNodeNote
        : l10n.mapSchemaNodeSource;
    final icon = isTopic
        ? Icons.label_outline
        : entry.edge == SchemaEdgeKind.mapNote
        ? Icons.account_tree_outlined
        : entry.isNote
        ? Icons.sticky_note_2_outlined
        : Icons.article_outlined;
    final hint = !entry.canExpand
        ? null
        : entry.expanded
        ? l10n.mapSchemaCollapse(entry.title)
        : l10n.mapSchemaExpand(entry.title);

    return Semantics(
      label: '$kind: ${entry.title}',
      hint: hint,
      button: true,
      expanded: entry.canExpand ? entry.expanded : null,
      excludeSemantics: true,
      onTap: entry.canExpand ? onToggle : onOpen,
      child: Material(
        key: ValueKey('map-schema-node-${entry.key}'),
        color: isTopic ? colors.surfaceContainerHigh : role.surface(colors),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: entry.expanded ? accent : accent.withValues(alpha: 0.5),
            width: entry.expanded ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(entry.isNote ? 22 : 8),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: entry.canExpand ? onToggle : onOpen,
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (entry.canExpand)
                  Icon(
                    entry.expanded ? Icons.remove : Icons.add,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                IconButton(
                  key: ValueKey('map-schema-open-${entry.key}'),
                  tooltip: l10n.mapSchemaOpen,
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Las líneas entre cada nodo y su padre. Las de un vínculo llevan el tipo, el
/// color de su tipo y una punta de flecha hacia donde apunta.
class _EdgesPainter extends CustomPainter {
  const _EdgesPainter({
    required this.entries,
    required this.positions,
    required this.colors,
    required this.mapNoteLabel,
    required this.relationLabel,
    required this.textColor,
  });

  final List<SchemaEntry> entries;
  final Map<String, Offset> positions;
  final ColorScheme colors;
  final String mapNoteLabel;
  final String Function(RelationKind kind) relationLabel;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in entries) {
      final parent = entry.parentKey == null
          ? null
          : positions[entry.parentKey];
      final child = positions[entry.key];
      if (parent == null || child == null) continue;

      final relation = entry.relation;
      final color = relation == null
          ? colors.outline.withValues(alpha: 0.6)
          : relation.color(colors);
      final line = Paint()
        ..color = color
        ..strokeWidth = relation == RelationKind.contradicts ? 2.5 : 1.5;
      canvas.drawLine(parent, child, line);

      // La punta, cerca del extremo al que apunta, fuera de la tarjeta.
      if (relation != null) {
        final from = entry.outgoing ? parent : child;
        final to = entry.outgoing ? child : parent;
        final head = arrowHead(
          from,
          to,
          back: math.min((to - from).distance * 0.3, 40),
          length: 9,
          half: 5,
        );
        if (head != null) {
          canvas.drawPath(arrowPath(head), Paint()..color = color);
        }
      }

      final label = switch (entry.edge) {
        SchemaEdgeKind.relation =>
          relation == null ? null : relationLabel(relation),
        SchemaEdgeKind.mapNote => mapNoteLabel,
        _ => null,
      };
      if (label != null) _paintLabel(canvas, label, (parent + child) / 2);
    }
  }

  void _paintLabel(Canvas canvas, String text, Offset at) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 11, color: textColor),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 110);
    final box = Rect.fromCenter(
      center: at,
      width: painter.width + 8,
      height: painter.height + 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()..color = colors.surface.withValues(alpha: 0.9),
    );
    painter.paint(canvas, box.topLeft + const Offset(4, 1));
  }

  @override
  bool shouldRepaint(_EdgesPainter old) =>
      old.entries != entries ||
      old.positions != positions ||
      old.colors != colors;
}

/// Lo que se eligió como punto de partida: un tema o una nota mapa.
class _RootChoice {
  const _RootChoice(this.ref, this.title);

  final SchemaRef ref;
  final String title;
}

/// El selector del punto de partida: una lista con búsqueda de las notas mapa,
/// que ya traen ordenada una parte del conocimiento, y de los temas —los de
/// más elementos primero—.
class _RootPicker extends StatefulWidget {
  const _RootPicker({required this.graph, required this.notes});

  final TopicGraph graph;
  final Future<List<SchemaLink>> notes;

  @override
  State<_RootPicker> createState() => _RootPickerState();
}

class _RootPickerState extends State<_RootPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = normalizeVocabularyLabel(_query.trim());
    bool matches(String text) =>
        query.isEmpty || normalizeVocabularyLabel(text).contains(query);
    final topics = [
      for (final node in widget.graph.nodes)
        if (matches(node.label)) node,
    ]..sort((a, b) => b.itemCount.compareTo(a.itemCount));

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const ValueKey('map-schema-search'),
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: l10n.atlasSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<SchemaLink>>(
                future: widget.notes,
                builder: (context, snapshot) {
                  final notes = [
                    for (final note in snapshot.data ?? const <SchemaLink>[])
                      if (matches(note.title)) note,
                  ];
                  final shownTopics = topics.take(100).toList();
                  return ListView(
                    children: [
                      if (notes.isNotEmpty) ...[
                        _PickerHeading(l10n.mapSchemaPickerMapNotes),
                        for (final note in notes)
                          ListTile(
                            key: ValueKey(
                              'map-schema-pick-note-${note.target.id}',
                            ),
                            dense: true,
                            leading: const Icon(
                              Icons.account_tree_outlined,
                              size: 20,
                            ),
                            title: Text(note.title),
                            onTap: () => Navigator.of(
                              context,
                            ).pop(_RootChoice(note.target, note.title)),
                          ),
                      ],
                      if (shownTopics.isNotEmpty) ...[
                        _PickerHeading(l10n.mapSchemaPickerTopics),
                        for (final node in shownTopics)
                          ListTile(
                            key: ValueKey('map-schema-pick-${node.valueId}'),
                            dense: true,
                            title: Text(node.label),
                            trailing: Text('${node.itemCount}'),
                            onTap: () => Navigator.of(context).pop(
                              _RootChoice(
                                SchemaRef.topic(node.valueId),
                                node.label,
                              ),
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerHeading extends StatelessWidget {
  const _PickerHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
