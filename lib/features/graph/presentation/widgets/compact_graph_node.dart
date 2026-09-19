import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';

/// El tamaño fijo de [CompactGraphNode]: bastante más chico que el nodo del
/// grafo completo (220×208) — acá no hay portada ni pie, solo ícono y
/// título, para que quepan varios a la vez en un panel embebido.
const compactGraphNodeSize = Size(148, 56);

/// Adónde navega tocar un nodo del grafo local: a su detalle, salvo que sea
/// una nota mapa, en cuyo caso entra al grafo local centrado en ella en vez
/// de a su detalle (decisión D4 de F6, ver `docs/arquitectura.md`) — lectura
/// literal del propio docstring de [NoteKind.map]: "da puntos de entrada al
/// grafo".
void openLocalGraphNode(
  BuildContext context, {
  required String nodeId,
  required NoteKind? kind,
}) {
  context.push(
    kind == NoteKind.map
        ? RoutePaths.graphLocal(nodeId)
        : RoutePaths.itemDetail(nodeId),
  );
}

/// Un nodo del grafo local: solo ícono y título, sin portada ni pie —
/// comparte esta forma chica entre el panel embebido (`LocalGraphPanel`) y
/// la pantalla completa (`LocalGraphScreen`).
///
/// Una nota mapa se distingue con su propio color e ícono (D4): es el
/// tratamiento visual que le da un lugar donde notarse a "dar puntos de
/// entrada al grafo". [isSeed] es el nodo desde el que se armó el grafo —no
/// es tocable, y su borde es siempre el de foco, sea o no nota mapa.
class CompactGraphNode extends ConsumerWidget {
  const CompactGraphNode({required this.item, required this.isSeed, super.key});

  final KnowledgeItem item;
  final bool isSeed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kind = ref.watch(noteKindProvider(item.id)).valueOrNull;
    final isMapNote = kind == NoteKind.map;
    // Una fuente y una nota no se ven igual: ver `EntityRole`.
    final role = item.source.kind.role;
    final radius = BorderRadius.circular(role.radius);

    final background = isSeed
        ? theme.colorScheme.surfaceContainerHigh
        : isMapNote
        ? theme.colorScheme.tertiaryContainer
        : role.surface(theme.colorScheme);
    final borderColor = isSeed
        ? theme.colorScheme.primary
        : isMapNote
        ? theme.colorScheme.tertiary
        : role.outline(theme.colorScheme);
    final icon = isMapNote ? NoteKind.map.icon : item.source.kind.icon;

    final card = Container(
      width: compactGraphNodeSize.width,
      height: compactGraphNodeSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: Border.all(
          color: borderColor,
          width: isSeed || isMapNote ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );

    if (isSeed) return card;

    return InkWell(
      borderRadius: radius,
      onTap: () => openLocalGraphNode(context, nodeId: item.id, kind: kind),
      child: card,
    );
  }
}
