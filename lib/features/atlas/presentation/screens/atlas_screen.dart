import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_view.dart';
import 'package:sinapsis/features/atlas/presentation/providers/atlas_providers.dart';
import 'package:sinapsis/features/atlas/presentation/widgets/branch_tile.dart';
import 'package:sinapsis/features/atlas/presentation/widgets/coverage_meter.dart';
import 'package:sinapsis/features/atlas/presentation/widgets/gaps_card.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El Atlas (F13): el mapa de lo que sabés y de lo que te falta, generado solo
/// desde las propiedades y las notas.
///
/// Muestra UNA categoría a la vez —«Tema» por defecto—: su árbol de temas y
/// subtemas con cuántas fuentes y notas hay debajo de cada rama, cuánto está
/// trabajada, qué años cubre y qué notas mapa la abren; y arriba, los vacíos.
/// Se actualiza solo: asignar una propiedad se refleja sin recargar.
class AtlasScreen extends ConsumerStatefulWidget {
  const AtlasScreen({super.key});

  @override
  ConsumerState<AtlasScreen> createState() => _AtlasScreenState();
}

class _AtlasScreenState extends ConsumerState<AtlasScreen> {
  final _searchController = TextEditingController();

  /// La categoría elegida; `null` hasta que se elige una: se muestra «Tema».
  String? _definitionId;

  final Set<String> _expanded = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(String valueId) {
    setState(() {
      if (!_expanded.remove(valueId)) _expanded.add(valueId);
    });
  }

  void _openMaterial(String valueId) =>
      context.go(RoutePaths.explorerFor(valueId));

  void _openTimeline(AtlasNode node) => context.push(
    RoutePaths.timelineFor(valueId: node.valueId, label: node.label),
  );

  void _openNote(String noteId) => context.push(RoutePaths.itemDetail(noteId));

  /// Las categorías donde el Atlas tiene sentido —las de texto: la jerarquía
  /// solo vive ahí— y la que se muestra: la elegida, o «Tema», o la primera.
  (List<PropertyDefinition>, PropertyDefinition?) _categories(
    List<PropertyDefinition> definitions,
  ) {
    final text = [
      for (final d in definitions)
        if (d.type == PropertyValueType.text) d,
    ];
    PropertyDefinition? selected;
    for (final d in text) {
      if (d.id == _definitionId) selected = d;
    }
    for (final d in text) {
      if (selected == null && d.isTema) selected = d;
    }
    return (text, selected ?? (text.isEmpty ? null : text.first));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final definitions =
        ref.watch(allPropertyDefinitionsProvider).valueOrNull ?? const [];
    final (categories, selected) = _categories(definitions);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.atlasTitle),
        actions: [
          if (categories.length > 1)
            PopupMenuButton<String>(
              key: const ValueKey('atlas-category'),
              tooltip: l10n.atlasCategoryTooltip,
              icon: const Icon(Icons.category_outlined),
              initialValue: selected?.id,
              onSelected: (id) => setState(() {
                _definitionId = id;
                _expanded.clear();
              }),
              itemBuilder: (context) => [
                for (final d in categories)
                  PopupMenuItem(value: d.id, child: Text(d.name)),
              ],
            ),
        ],
      ),
      body: selected == null
          ? _Empty(l10n: l10n)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    key: const ValueKey('atlas-search'),
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l10n.atlasSearchHint,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(_searchController.clear),
                            ),
                      isDense: true,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(28)),
                      ),
                    ),
                  ),
                ),
                Expanded(child: _atlas(selected.id, l10n)),
              ],
            ),
    );
  }

  Widget _atlas(String definitionId, AppLocalizations l10n) {
    final atlas = ref.watch(atlasProvider(definitionId));

    return atlas.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.atlasLoadError),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(atlasProvider(definitionId)),
              child: Text(l10n.atlasRetry),
            ),
          ],
        ),
      ),
      data: (snapshot) {
        if (snapshot.nodes.isEmpty) return _Empty(l10n: l10n);
        return _AtlasList(
          snapshot: snapshot,
          expanded: _expanded,
          query: _searchController.text,
          now: ref.read(clockProvider)(),
          onToggle: _toggle,
          onOpenMaterial: _openMaterial,
          onOpenTimeline: _openTimeline,
          onOpenNote: _openNote,
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.account_tree_outlined,
      title: l10n.atlasEmptyTitle,
      message: l10n.atlasEmptyMessage,
    );
  }
}

/// La leyenda, los vacíos y el árbol, en una sola lista que se construye a
/// medida que se muestra: con miles de temas solo importan las filas a la
/// vista.
class _AtlasList extends StatelessWidget {
  const _AtlasList({
    required this.snapshot,
    required this.expanded,
    required this.query,
    required this.now,
    required this.onToggle,
    required this.onOpenMaterial,
    required this.onOpenTimeline,
    required this.onOpenNote,
  });

  final AtlasSnapshot snapshot;
  final Set<String> expanded;
  final String query;
  final DateTime now;
  final void Function(String valueId) onToggle;
  final void Function(String valueId) onOpenMaterial;
  final void Function(AtlasNode node) onOpenTimeline;
  final void Function(String noteId) onOpenNote;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final searching = query.trim().isNotEmpty;
    final rows = visibleAtlasNodes(snapshot, expanded: expanded, query: query);
    // Buscando, solo la búsqueda: los vacíos y la leyenda son del árbol entero.
    final showGaps = !searching && snapshot.gaps.isNotEmpty;
    final headers = searching ? 0 : (showGaps ? 2 : 1);

    if (searching && rows.isEmpty) {
      return Center(child: Text(l10n.atlasNoResults));
    }

    return ListView.builder(
      itemCount: headers + rows.length,
      itemBuilder: (context, index) {
        if (index < headers) {
          return index == 0
              ? const CoverageLegend()
              : GapsCard(snapshot: snapshot, now: now, onOpen: onOpenMaterial);
        }
        final node = rows[index - headers];
        return BranchTile(
          node: node,
          expanded: expanded.contains(node.valueId),
          searching: searching,
          onToggle: () => onToggle(node.valueId),
          onOpenMaterial: () => onOpenMaterial(node.valueId),
          onOpenTimeline: () => onOpenTimeline(node),
          onOpenNote: onOpenNote,
        );
      },
    );
  }
}
