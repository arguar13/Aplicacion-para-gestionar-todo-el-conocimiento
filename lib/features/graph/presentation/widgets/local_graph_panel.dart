import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/features/graph/domain/services/graph_scope.dart';
import 'package:sinapsis/features/graph/domain/services/preview_graph_layout.dart';
import 'package:sinapsis/features/graph/presentation/widgets/compact_graph_node.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Vista previa del mapa de CUALQUIER elemento —fuente o nota— dentro de su
/// propio detalle: el elemento en el medio y sus vecinos directos alrededor,
/// sin selector ni pan/zoom —eso vive en `LocalGraphScreen`, adonde llevan
/// tanto tocar la vista como su botón de ampliar—. Es el requisito explícito
/// del punto 1 del encargo de F6 (ver `docs/arquitectura.md`).
///
/// Es una vista PREVIA, no el mapa en chiquito: dibuja hasta
/// [kLocalGraphPreviewMaxNeighbors] vecinos —los más atados al elemento— en
/// una disposición cerrada, sin encimados, que usa todo el ancho de la
/// tarjeta (ver [layoutLocalPreview]), y resume el resto en un «+N» que
/// invita a ampliar. Sin etiquetas de vínculo ni vínculos entre vecinos: con
/// muchos, eso era lo que la hacía ilegible. Se calcula en el build, sin
/// simulación física.
///
/// **El grafo local lee solo lo procesado** (F41, paso 6), como el Mapa: los
/// vínculos entre documentos procesados. Es el Mapa de un documento procesado
/// (paso 8). De cualquier otro elemento no se dibuja: una fuente es de
/// consulta y se estudia en su procesado (decisión K), y una nota de la
/// persona no está en el Mapa. Sus vínculos siguen a la vista en su detalle,
/// en «Vínculos».
class LocalGraphPanel extends ConsumerWidget {
  const LocalGraphPanel({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final own = ref.watch(processedDocumentProvider(item.id));
    if (own.valueOrNull == null) return const SizedBox.shrink();
    return _ProcessedGraphPanel(item: item);
  }
}

/// La vista previa del grafo de un documento procesado: lo que
/// [LocalGraphPanel] dibuja una vez que sabe de cuál.
class _ProcessedGraphPanel extends ConsumerWidget {
  const _ProcessedGraphPanel({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Solo lo que rodea al elemento, no la bóveda entera: pedir todos los
    // elementos y todos los vínculos para quedarse con unos pocos tardaba
    // un minuto con diez mil elementos, en CADA detalle que se abría.
    final hood = ref
        .watch(
          neighborhoodProvider((
            itemId: item.id,
            degree: 1,
            maxNodes: kLocalGraphPanelMaxNodes,
          )),
        )
        .valueOrNull;
    if (hood == null) return const SizedBox.shrink();

    final items = hood.nodeIds.isEmpty
        ? const <KnowledgeItem>[]
        : ref
              .watch(
                libraryItemsProvider(
                  LibraryQuery(
                    ids: hood.nodeIds,
                    scope: LibraryScope.processed,
                  ),
                ),
              )
              .valueOrNull;
    if (items == null) return const SizedBox.shrink();

    return _LocalGraphPanelBody(
      item: item,
      items: items,
      // `nodeIds` viene con el elemento primero y después los vecinos del más
      // al menos reciente: es el orden de desempate de la elección.
      nodeIds: hood.nodeIds.toList(),
      edges: hood.edges,
      omitted: hood.omitted,
    );
  }
}

class _LocalGraphPanelBody extends StatelessWidget {
  const _LocalGraphPanelBody({
    required this.item,
    required this.items,
    required this.nodeIds,
    required this.edges,
    required this.omitted,
  });

  final KnowledgeItem item;
  final List<KnowledgeItem> items;
  final List<String> nodeIds;
  final List<RelationEdge> edges;

  /// Cuántos vecinos no entraron en el vecindario por el tope de nodos.
  final int omitted;

  void _openFull(BuildContext context) =>
      context.push(RoutePaths.graphLocal(item.id));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final itemsById = {for (final i in items) i.id: i};

    // Los vecinos directos que existen: `nodeIds` ya son los de un salto, pero
    // un vínculo puede apuntar a un elemento que ya no está entre [items].
    final neighborIds = [
      for (final id in nodeIds)
        if (id != item.id && itemsById.containsKey(id)) id,
    ];

    if (neighborIds.isEmpty) {
      // En un renglón si entra; con la letra grande en un teléfono, el botón
      // baja al siguiente en vez de desbordar.
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.graphEmpty, style: Theme.of(context).textTheme.bodyMedium),
          TextButton(
            onPressed: () => _openFull(context),
            child: Text(l10n.localGraphPanelOpenFull),
          ),
        ],
      );
    }

    final picked = pickPreviewNeighbors(
      seedId: item.id,
      neighborIds: neighborIds,
      edges: [for (final e in edges) (e.fromItemId, e.toItemId)],
      omitted: omitted,
    );
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _openFull(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 4),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.localGraphPreviewTitle,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (picked.hidden > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Chip(
                          key: const ValueKey('local-graph-preview-more'),
                          label: Text(
                            l10n.localGraphPreviewMore(picked.hidden),
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          side: BorderSide.none,
                          backgroundColor: colors.secondaryContainer,
                          labelStyle: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.open_in_full),
                      iconSize: 20,
                      tooltip: l10n.localGraphPanelOpenFull,
                      onPressed: () => _openFull(context),
                    ),
                  ],
                ),
              ),
            ),
            // El texto de los nodos no crece con la letra grande del sistema
            // más de lo que el nodo aguanta: la vista previa es de tamaño fijo.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: _PreviewCanvas(
                item: item,
                neighbors: [for (final id in picked.shown) itemsById[id]!],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El lienzo de la vista previa: se adapta al ancho que le toca y pide el alto
/// que su disposición necesita.
class _PreviewCanvas extends StatelessWidget {
  const _PreviewCanvas({required this.item, required this.neighbors});

  final KnowledgeItem item;
  final List<KnowledgeItem> neighbors;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final sizes = previewNodeSizes(width);
        final layout = layoutLocalPreview(
          count: neighbors.length,
          width: width,
          nodeSize: sizes.node,
          centerSize: sizes.center,
        );
        return SizedBox(
          width: width,
          height: layout.size.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: PreviewLinksPainter(
                    from: layout.center.center,
                    to: [for (final r in layout.neighbors) r.center],
                    color: colors.outline.withValues(alpha: 0.5),
                  ),
                ),
              ),
              for (var i = 0; i < neighbors.length; i++)
                Positioned.fromRect(
                  rect: layout.neighbors[i],
                  child: LocalGraphPreviewNode(
                    item: neighbors[i],
                    isSeed: false,
                  ),
                ),
              Positioned.fromRect(
                rect: layout.center,
                child: LocalGraphPreviewNode(item: item, isSeed: true),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Los vínculos de la vista previa: una línea fina y suave del elemento a cada
/// vecino. Va por DEBAJO de los nodos, que son opacos y la tapan donde se
/// cruzan, así que solo se ve el tramo entre uno y otro.
class PreviewLinksPainter extends CustomPainter {
  const PreviewLinksPainter({
    required this.from,
    required this.to,
    required this.color,
  });

  final Offset from;
  final List<Offset> to;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final target in to) {
      canvas.drawLine(from, target, paint);
    }
  }

  @override
  bool shouldRepaint(PreviewLinksPainter old) =>
      old.from != from || old.color != color || !_sameOffsets(old.to, to);

  static bool _sameOffsets(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Un nodo de la vista previa: una píldora con el título en hasta dos líneas,
/// sin ícono ni pie. El color y la forma distinguen una fuente de una nota
/// (ver `EntityRole`) y una nota mapa lleva su color propio, igual que en el
/// mapa completo (D4). El elemento del medio ([isSeed]) lleva el borde de
/// foco y no es tocable por sí mismo: tocarlo abre el mapa completo, como el
/// resto de la vista.
class LocalGraphPreviewNode extends ConsumerWidget {
  const LocalGraphPreviewNode({
    required this.item,
    required this.isSeed,
    super.key,
  });

  final KnowledgeItem item;
  final bool isSeed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final kind = ref.watch(noteKindProvider(item.id)).valueOrNull;
    final isMapNote = kind == NoteKind.map;
    final role = item.source.kind.role;
    final radius = BorderRadius.circular(isSeed ? 14 : 12);

    final background = isSeed
        ? colors.surfaceContainerHigh
        : isMapNote
        ? colors.tertiaryContainer
        : role.surface(colors);
    final borderColor = isSeed
        ? colors.primary
        : isMapNote
        ? colors.tertiary
        : role.outline(colors);

    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: Border.all(
          color: borderColor,
          width: isSeed || isMapNote ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Center(
          child: Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              fontSize: isSeed ? 12.5 : 11.5,
              height: 1.15,
              fontWeight: isSeed ? FontWeight.w600 : null,
            ),
          ),
        ),
      ),
    );

    if (isSeed) return pill;

    return InkWell(
      borderRadius: radius,
      onTap: () => openLocalGraphNode(context, nodeId: item.id, kind: kind),
      child: pill,
    );
  }
}
