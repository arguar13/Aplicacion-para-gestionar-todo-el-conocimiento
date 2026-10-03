import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/design/widgets/topic_dimension_menu.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_view.dart';
import 'package:sinapsis/features/atlas/domain/usecases/export_atlas_usecase.dart';
import 'package:sinapsis/features/atlas/presentation/providers/atlas_providers.dart';
import 'package:sinapsis/features/atlas/presentation/services/atlas_markdown.dart';
import 'package:sinapsis/features/atlas/presentation/widgets/branch_tile.dart';
import 'package:sinapsis/features/atlas/presentation/widgets/coverage_meter.dart';
import 'package:sinapsis/features/atlas/presentation/widgets/gaps_card.dart';
import 'package:sinapsis/features/citations/presentation/export_bibliography_action.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El Atlas (F13): el mapa de lo que sabés y de lo que te falta, generado solo
/// desde lo que organizaste y las notas.
///
/// Muestra UNA dimensión a la vez (F28): los **temas** —lo que se elige al
/// guardar— si hay alguno, o el árbol de **etiquetas**, u otra categoría de
/// texto. Cada rama dice cuántas fuentes y notas hay debajo, cuánto está
/// trabajada, qué años cubre y qué notas mapa la abren; y arriba, los vacíos.
/// Los temas son planos —un elemento está en uno solo—, así que su Atlas es
/// una lista de ramas sin subtemas; la jerarquía vive en las etiquetas, y se
/// pasa de una a otra con el selector. Se actualiza solo: asignar algo se
/// refleja sin recargar.
class AtlasScreen extends ConsumerStatefulWidget {
  const AtlasScreen({super.key});

  @override
  ConsumerState<AtlasScreen> createState() => _AtlasScreenState();
}

class _AtlasScreenState extends ConsumerState<AtlasScreen> {
  final _searchController = TextEditingController();

  /// La dimensión que se mira. `null` hasta la primera vez que se sabe cuál
  /// toca por defecto; desde ahí queda fija hasta que se elija otra.
  String? _dimensionId;

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

  /// Si lo que se mira son los temas: una rama es un espacio y no un valor.
  bool get _spaces => _dimensionId != null && isSpacesDimension(_dimensionId!);

  void _openMaterial(String valueId) => context.go(
    _spaces
        ? RoutePaths.explorerForSpace(valueId)
        : RoutePaths.explorerFor(valueId),
  );

  void _openTimeline(AtlasNode node) => context.push(
    _spaces
        ? RoutePaths.timelineForSpace(spaceId: node.valueId, label: node.label)
        : RoutePaths.timelineFor(valueId: node.valueId, label: node.label),
  );

  void _openNote(String noteId) => context.push(RoutePaths.itemDetail(noteId));

  /// La bibliografía de la rama [node]: la propia rama y todo lo que cuelga
  /// de ella (F15, D13), o lo que está en el tema.
  Future<void> _exportBibliography(AtlasNode node) async {
    final bibliography = ref.read(bibliographyRepositoryProvider);
    final sources = _spaces
        ? await bibliography.sourcesOfSpace(node.valueId)
        : await bibliography.sourcesOfBranch(node.valueId);
    if (!mounted) return;
    await exportBibliography(
      context,
      ref,
      sources: sources,
      suggestedName: node.label,
    );
  }

  /// Guarda el Atlas de [dimension] como un documento Markdown: una foto de
  /// ahora, para tener el índice fuera de la app.
  Future<void> _export(TopicDimension dimension) async {
    // Antes de esperar nada: al terminar, esta pantalla puede haber cambiado.
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final export = ref.read(exportAtlasUseCaseProvider);
    final now = ref.read(clockProvider)();
    final label = topicDimensionLabel(l10n, dimension);

    final snapshot = await ref
        .read(atlasRepositoryProvider)
        .snapshot(dimension.id);
    final result = await export(
      ExportAtlasParams(
        fileName: 'atlas-${_fileSlug(label)}.md',
        markdown: atlasToMarkdown(snapshot, l10n, now: now, title: label),
      ),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.fold(
              (failure) => failure.localizedMessage(l10n),
              (_) => l10n.atlasExportSaved,
            ),
          ),
        ),
      );
  }

  /// El nombre de la categoría como parte de un nombre de archivo: en
  /// minúsculas, sin acentos y con guiones.
  static String _fileSlug(String name) {
    final dashed = normalizeVocabularyLabel(
      name,
    ).replaceAll(RegExp('[^a-z0-9]+'), '-');
    final slug = dashed.replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'atlas' : slug;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final definitions = ref.watch(allPropertyDefinitionsProvider).valueOrNull;
    final spaces = ref.watch(allSpacesProvider).valueOrNull;

    // Hasta saber si hay temas no se sabe qué mirar por defecto.
    if (definitions == null || spaces == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.atlasTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final (:options, :selected) = topicDimensionsOf(
      definitions,
      hasSpaces: spaces.isNotEmpty,
      chosenId: _dimensionId,
    );
    // La de por defecto queda fija desde ahora: ver [_dimensionId]. Es un
    // recuerdo, no algo que se dibuje, así que no hace falta `setState`.
    _dimensionId ??= selected.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.atlasTitle),
        actions: [
          IconButton(
            key: const ValueKey('atlas-export'),
            tooltip: l10n.atlasExportAction,
            icon: const Icon(Icons.ios_share),
            onPressed: () => _export(selected),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TopicDimensionMenu(
                key: const ValueKey('atlas-category'),
                options: options,
                selected: selected,
                onSelected: (dimension) => setState(() {
                  _dimensionId = dimension.id;
                  _expanded.clear();
                }),
              ),
            ),
          ),
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
                        onPressed: () => setState(_searchController.clear),
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
          onExportBibliography: _exportBibliography,
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
    required this.onExportBibliography,
  });

  final AtlasSnapshot snapshot;
  final Set<String> expanded;
  final String query;
  final DateTime now;
  final void Function(String valueId) onToggle;
  final void Function(String valueId) onOpenMaterial;
  final void Function(AtlasNode node) onOpenTimeline;
  final void Function(String noteId) onOpenNote;
  final void Function(AtlasNode node) onExportBibliography;

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
          onExportBibliography: () => onExportBibliography(node),
        );
      },
    );
  }
}
