import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/features/explorer/presentation/providers/explorer_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_item_card.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_filter_section.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El Explorador: lo ya procesado, filtrable por tema, tipo, etiqueta y
/// propiedad tipada —sin carpetas.
///
/// Antes organizaba en carpetas jerárquicas que había que crear y mantener
/// a mano, con una capa automática que agrupaba por tipo de recurso encima.
/// Se reemplazó por completo: la organización real ya vive en lo que cada
/// elemento tiene puesto —sus etiquetas, sus propiedades—, así que filtrar
/// por eso hace el mismo trabajo que antes hacía mover un elemento a una
/// carpeta, sin el paso extra de crearla ni el riesgo de dejar algo "sin
/// archivar" en ningún lado. El tipo de recurso, que antes era la única
/// subdivisión automática, ahora es un filtro más entre otros.
class ExplorerScreen extends ConsumerWidget {
  const ExplorerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(explorerQueryNotifierProvider);
    final notifier = ref.read(explorerQueryNotifierProvider.notifier);
    final items = ref.watch(libraryItemsProvider(query)).valueOrNull;
    // El tema elegido, con su nombre; `null` también si su `id` todavía no
    // llegó con la lista. Mirarlo acá además mantiene viva la lista de temas
    // mientras el Explorador está abierto: el panel de filtros la encuentra
    // lista en vez de arrancar vacío.
    final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const <Space>[];
    final currentSpace = spaces
        .where((space) => space.id == query.spaceId)
        .firstOrNull;
    // Lo mismo que en la Biblioteca: el tema cuenta como un filtro más,
    // porque vive en el mismo panel y acota lo que se ve.
    final activeFilterCount =
        (query.spaceId == null ? 0 : 1) +
        query.sourceKinds.length +
        query.tagIds.length +
        query.propertyValueIds.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.explorerTitle),
        // El tema en el que se está parado, igual que debajo de la búsqueda
        // de la Biblioteca —ver `CurrentSpaceChip`—: es el único filtro que
        // recorta como una carpeta, y saber CUÁL es importa más que saber
        // cuántos filtros hay.
        bottom: currentSpace == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(CurrentSpaceChip.extent),
                child: CurrentSpaceChip(
                  space: currentSpace,
                  onPressed: () => _showFilters(context),
                  onLeave: () => notifier.selectSpace(null),
                ),
              ),
        actions: [
          Badge(
            label: Text('$activeFilterCount'),
            isLabelVisible: activeFilterCount > 0,
            child: IconButton(
              icon: const Icon(Icons.tune),
              tooltip: l10n.libraryFiltersTooltip,
              isSelected: activeFilterCount > 0,
              onPressed: () => _showFilters(context),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(context, items, notifier),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<KnowledgeItem>? items,
    ExplorerQueryNotifier notifier,
  ) {
    final l10n = AppLocalizations.of(context)!;

    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty) {
      final filtered = notifier.hasActiveFilters;
      return EmptyStateView(
        icon: filtered ? Icons.filter_alt_off_outlined : Icons.inbox_outlined,
        title: filtered
            ? l10n.explorerEmptyFilteredTitle
            : l10n.explorerEmptyTitle,
        message: filtered ? null : l10n.explorerEmptyMessage,
        actionLabel: filtered ? l10n.libraryClearFilters : null,
        onAction: filtered ? notifier.clearFilters : null,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return LibraryItemCard(
          item: item,
          onTap: () => context.push(RoutePaths.itemDetail(item.id)),
        );
      },
    );
  }

  Future<void> _showFilters(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Sin esto, el panel queda topeado a la mitad de la pantalla aunque
      // haya de sobra más abajo: con muchas categorías puestas, ese tope
      // fijo es lo que obligaría a desplazarse antes de lo necesario.
      isScrollControlled: true,
      builder: (context) => const _ExplorerFiltersSheet(),
    );
  }
}

/// El panel de filtros: tema, tipo, categorías con sus valores, y etiquetas.
///
/// `ConsumerWidget` observando `explorerQueryNotifierProvider` directamente
/// —igual que `_FiltersSheet` en `library_screen.dart`— para que marcar un
/// chip acá se refleje al instante en la lista de atrás, aunque el panel
/// siga abierto: el estado vive en el provider, no en este widget.
class _ExplorerFiltersSheet extends ConsumerWidget {
  const _ExplorerFiltersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final query = ref.watch(explorerQueryNotifierProvider);
    final notifier = ref.read(explorerQueryNotifierProvider.notifier);
    // Tema no va en las categorías: sus valores YA se muestran como
    // etiquetas, más abajo. Sin esto, cada etiqueta aparecería dos
    // veces —las dos secciones filtran por el mismo valor—.
    final definitions = [
      for (final definition
          in ref.watch(allPropertyDefinitionsProvider).valueOrNull ??
              const <PropertyDefinition>[])
        if (!definition.isTema) definition,
    ];
    final tags = ref.watch(allTagsProvider).valueOrNull ?? const <Tag>[];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.libraryFiltersTooltip,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (notifier.hasActiveFilters)
                  TextButton(
                    onPressed: notifier.clearFilters,
                    child: Text(l10n.libraryClearFilters),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Arriba de todo, como en la Biblioteca: la misma sección, para
            // que filtrar por tema se vea y se use igual en las dos.
            _FilterSectionLabel(l10n.libraryFilterSpaceLabel),
            const SizedBox(height: 8),
            SpaceFilterSection(
              selectedSpaceId: query.spaceId,
              onChanged: notifier.selectSpace,
            ),
            const SizedBox(height: 20),
            _FilterSectionLabel(l10n.libraryFilterTypeLabel),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in SourceKind.values)
                  FilterChip(
                    avatar: Icon(kind.icon, size: 18),
                    label: Text(kind.label(l10n)),
                    selected: query.sourceKinds.contains(kind),
                    onSelected: (_) => notifier.toggleSourceKind(kind),
                  ),
              ],
            ),
            // Sin ninguna categoría creada todavía, esta sección no tiene
            // qué mostrar: ver la nota análoga sobre etiquetas más abajo.
            if (definitions.isNotEmpty) ...[
              const SizedBox(height: 20),
              _FilterSectionLabel(l10n.explorerFilterPropertiesLabel),
              const SizedBox(height: 8),
              for (final definition in definitions)
                _PropertyDefinitionFilter(
                  definition: definition,
                  selectedValueIds: query.propertyValueIds,
                  onToggle: notifier.togglePropertyValueId,
                ),
            ],
            // Sin nada en el vocabulario todavía, esta sección no tiene qué
            // mostrar: ocuparía lugar para decir "no hay etiquetas por las
            // que filtrar", que no es información que alguien necesite ver
            // siempre.
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 20),
              _FilterSectionLabel(l10n.libraryFilterTagsLabel),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    FilterChip(
                      avatar: const Icon(Icons.label_outline, size: 18),
                      label: Text(tag.name),
                      selected: query.tagIds.contains(tag.id),
                      onSelected: (_) => notifier.toggleTagId(tag.id),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Una categoría dentro del panel de filtros, con sus valores como chips.
///
/// Observa sus propios valores —`propertyValuesProvider(definitionId)`— en
/// vez de que el panel los traiga todos de antemano: cada categoría solo
/// necesita los suyos, y así una bóveda con muchas categorías no dispara
/// una consulta por cada una hasta que esta sección efectivamente se
/// construye.
class _PropertyDefinitionFilter extends ConsumerWidget {
  const _PropertyDefinitionFilter({
    required this.definition,
    required this.selectedValueIds,
    required this.onToggle,
  });

  final PropertyDefinition definition;
  final Set<String> selectedValueIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final values =
        ref.watch(propertyValuesProvider(definition.id)).valueOrNull ??
        const <PropertyValue>[];
    if (values.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            definition.name,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in values)
                FilterChip(
                  label: Text(value.value),
                  selected: selectedValueIds.contains(value.id),
                  onSelected: (_) => onToggle(value.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterSectionLabel extends StatelessWidget {
  const _FilterSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}
