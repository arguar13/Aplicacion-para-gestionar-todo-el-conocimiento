import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/services/canvas_tree_builder.dart';
import 'package:sinapsis/features/map/domain/services/schema_layout.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_tree.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_canvas_layers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántas filas tiene la lista, como mucho: más que el dibujo, porque una
/// lista se recorre de a una y no tiene que caber en una pantalla.
const kMaxCanvasListNodes = 500;

/// «Ver como lista» (F44, paso 2): lo mismo que el lienzo, como una lista que
/// se despliega —comunidades › temas › documentos, con sus vínculos—. Es como
/// se recorre el Mapa con el lector de pantalla, y con la letra grande.
///
/// Usa el mismo árbol que Radial y Árbol, con lo mismo desplegado: pasar del
/// dibujo a la lista, o al revés, no pierde nada.
class MapCanvasList extends StatelessWidget {
  const MapCanvasList({
    required this.tree,
    required this.topicKind,
    required this.onToggle,
    required this.sheetOf,
    super.key,
  });

  final CanvasTree tree;

  /// Qué es un tema acá: ver `topicSelectKind`.
  final String topicKind;
  final ValueChanged<CanvasTreeEntry> onToggle;

  /// Cómo se abre la ficha de una fila (F44, paso 4), con las mismas acciones
  /// que en el dibujo; `null` si no tiene.
  final CanvasTreeSheet? Function(CanvasTreeEntry entry) sheetOf;

  @override
  Widget build(BuildContext context) {
    final rows = <CanvasTreeEntry>[];
    void visit(SchemaNode node) {
      final entry = tree.entries[node.id];
      if (entry == null) return;
      rows.add(entry);
      node.children.forEach(visit);
    }

    visit(tree.root);

    return ListView.builder(
      key: const ValueKey('map-list'),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length,
      itemBuilder: (context, index) => _Row(
        entry: rows[index],
        parentTitle: tree.entries[rows[index].parentKey]?.title,
        topicKind: topicKind,
        onToggle: () => onToggle(rows[index]),
        sheet: sheetOf(rows[index]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.parentTitle,
    required this.topicKind,
    required this.onToggle,
    required this.sheet,
  });

  final CanvasTreeEntry entry;
  final String? parentTitle;
  final String topicKind;
  final VoidCallback onToggle;
  final CanvasTreeSheet? sheet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = treeAccentOf(entry, theme.colorScheme, theme.brightness);
    final indent = 8.0 + 20.0 * (entry.depth > 5 ? 5 : entry.depth);

    return ListTile(
      key: ValueKey('map-list-row-${entry.key}'),
      contentPadding: EdgeInsetsDirectional.only(start: indent, end: 4),
      leading: Icon(treeIconOf(entry), color: accent),
      title: Text(entry.title),
      subtitle: Text(_subtitle(l10n)),
      onTap: entry.canExpand ? onToggle : sheet?.onOpen,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sheet case final sheet?)
            IconButton(
              key: ValueKey('map-list-sheet-${entry.key}'),
              tooltip: sheet.tooltip,
              icon: const Icon(Icons.info_outline),
              onPressed: sheet.onOpen,
            ),
          // Un solo nodo para el lector: el botón, con su nombre y si la fila
          // está desplegada.
          if (entry.canExpand)
            MergeSemantics(
              child: Semantics(
                expanded: entry.expanded,
                child: IconButton(
                  key: ValueKey('map-list-toggle-${entry.key}'),
                  tooltip: entry.expanded
                      ? l10n.mapSchemaCollapse(entry.title)
                      : l10n.mapSchemaExpand(entry.title),
                  icon: Icon(
                    entry.expanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onPressed: onToggle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Qué es la fila y cómo se une con la de arriba: un vínculo se lee desde
  /// el documento de la fila («Citado por Livio»), como en su detalle.
  String _subtitle(AppLocalizations l10n) {
    final relation = entry.relation;
    final parent = parentTitle;
    if (relation != null && parent != null) {
      return relation.describe(
        l10n,
        // El vínculo sale del padre hacia esta fila: desde acá, llega.
        direction: entry.outgoing
            ? RelationDirection.incoming
            : RelationDirection.outgoing,
        otherItemTitle: parent,
      );
    }
    return switch (entry.ref.kind) {
      CanvasTreeKind.community => l10n.mapTopicCount(topicKind, entry.count),
      CanvasTreeKind.topic => l10n.mapSchemaNodeTopic(topicKind),
      CanvasTreeKind.item =>
        entry.edge == CanvasTreeEdge.mapNote
            ? l10n.mapSchemaNodeMapNote
            : entry.isNote
            ? l10n.mapSchemaNodeNote
            : l10n.mapSchemaNodeSource,
      CanvasTreeKind.all || CanvasTreeKind.links => l10n.f44S2ListRoot,
    };
  }
}
