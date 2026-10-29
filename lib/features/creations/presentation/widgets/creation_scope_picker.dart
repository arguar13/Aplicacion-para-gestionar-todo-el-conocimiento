import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/topic_dimension_menu.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/features/atlas/presentation/providers/atlas_providers.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_source_chips.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «N documentos · M tarjetas · K creaciones» de un recorte.
String creationScopeDetail(
  AppLocalizations l10n,
  CreationScopeSummary summary,
) => [
  l10n.f43StudioDocuments(summary.documents),
  l10n.f43StudioCards(summary.cards),
  if (summary.creations > 0) l10n.f43StudioCreations(summary.creations),
].join(' · ');

/// La píldora de arriba de Repasar (F43, punto 2 del plan; lo del óvalo
/// naranja): el ícono, el nombre de lo elegido y una línea de detalle. Tocarla
/// abre la hoja del selector ([showCreationScopePicker]).
class CreationScopePill extends ConsumerWidget {
  const CreationScopePill({
    required this.scope,
    required this.onTap,
    super.key,
  });

  final CreationScope scope;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = ref.watch(creationScopeSummaryProvider(scope));
    final value = summary.valueOrNull;
    final missing = value != null && !value.exists;
    final title = scope.isAll
        ? l10n.f43StudioScopeAll
        : missing
        ? l10n.f43StudioScopeMissing
        : (value?.name ?? '…');
    final detail = value == null
        ? null
        : missing
        ? l10n.f43StudioScopeMissingHint
        : creationScopeDetail(l10n, value);

    return Semantics(
      button: true,
      hint: l10n.f43StudioScopeChange,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('repasar-scope'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (missing ? scheme.error : scheme.primary).withValues(
                      alpha: 0.12,
                    ),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    missing ? Icons.link_off : creationScopeIcon(scope),
                    size: 22,
                    color: missing ? scheme.error : scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        key: const Key('repasar-scope-name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          key: const Key('repasar-scope-detail'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: missing
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.expand_more, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Abre la hoja del selector y devuelve lo elegido, o `null` si se cierra
/// sin elegir.
Future<CreationScope?> showCreationScopePicker(
  BuildContext context, {
  required CreationScope current,
}) => showModalBottomSheet<CreationScope>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (context) => CreationScopePicker(current: current),
);

/// Las cuatro pestañas de la hoja.
enum CreationScopeTab { all, document, notebook, topic }

/// La hoja del selector (punto 2 del plan): un buscador, **los recientes**
/// —los últimos cuatro que se eligieron— y cuatro pestañas: **Todo lo
/// procesado**, **Documento**, **Cuaderno** y **Tema**. Cada fila dice cuánto
/// tiene —documentos, tarjetas, creaciones y si ya tiene resumen—.
///
/// **Todo sale de Procesado** (decisión D): un documento es un procesado, un
/// cuaderno uno de los de F41 y un tema uno del Atlas, que F41 ya arma solo
/// con lo procesado —un tema sin nada procesado no aparece—. La Biblioteca no
/// aparece.
class CreationScopePicker extends ConsumerStatefulWidget {
  const CreationScopePicker({required this.current, super.key});

  final CreationScope current;

  @override
  ConsumerState<CreationScopePicker> createState() =>
      _CreationScopePickerState();
}

class _CreationScopePickerState extends ConsumerState<CreationScopePicker> {
  late var _tab = switch (widget.current) {
    AllProcessed() => CreationScopeTab.all,
    ProcessedDocumentScope() => CreationScopeTab.document,
    NotebookScope() => CreationScopeTab.notebook,
    TopicScope() || SpaceScope() => CreationScopeTab.topic,
  };
  var _search = '';
  String? _dimensionId;

  void _choose(CreationScope scope) => Navigator.of(context).pop(scope);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final recents = ref.watch(recentCreationScopesProvider);
    final searching = _search.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: Column(
          key: const Key('creation-scope-picker'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.f43StudioPickerTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  CreationCloseButton(tooltip: l10n.f43StudioClose),
                ],
              ),
            ),
            Flexible(
              child: CustomScrollView(
                shrinkWrap: true,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: TextField(
                        key: const Key('creation-scope-search'),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: l10n.f43StudioPickerSearch,
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                        ),
                        onChanged: (text) => setState(() {
                          _search = text.trim();
                          // Buscar es buscar algo: en «Todo» no hay qué, así
                          // que se pasa a los documentos.
                          if (_search.isNotEmpty &&
                              _tab == CreationScopeTab.all) {
                            _tab = CreationScopeTab.document;
                          }
                        }),
                      ),
                    ),
                  ),
                  if (!searching && recents.isNotEmpty) ...[
                    _label(context, l10n.f43StudioPickerRecent),
                    SliverList.list(
                      children: [
                        for (final scope in recents)
                          _RecentRow(
                            scope: scope,
                            selected: scope == widget.current,
                            onTap: () => _choose(scope),
                          ),
                      ],
                    ),
                  ],
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tab in CreationScopeTab.values)
                            ChoiceChip(
                              key: Key('creation-scope-tab-${tab.name}'),
                              label: Text(_tabLabel(l10n, tab)),
                              avatar: Icon(_tabIcon(tab), size: 18),
                              showCheckmark: false,
                              shape: const StadiumBorder(),
                              selected: _tab == tab,
                              onSelected: (_) => setState(() => _tab = tab),
                            ),
                        ],
                      ),
                    ),
                  ),
                  ..._tabContent(context),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
    sliver: SliverToBoxAdapter(child: CreationSectionLabel(text)),
  );

  static String _tabLabel(AppLocalizations l10n, CreationScopeTab tab) =>
      switch (tab) {
        CreationScopeTab.all => l10n.f43StudioPickerTabAll,
        CreationScopeTab.document => l10n.f43StudioPickerTabDocument,
        CreationScopeTab.notebook => l10n.f43StudioPickerTabNotebook,
        CreationScopeTab.topic => l10n.f43StudioPickerTabTopic,
      };

  static IconData _tabIcon(CreationScopeTab tab) => switch (tab) {
    CreationScopeTab.all => Icons.summarize_outlined,
    CreationScopeTab.document => Icons.description_outlined,
    CreationScopeTab.notebook => Icons.menu_book_outlined,
    CreationScopeTab.topic => Icons.label_outline,
  };

  List<Widget> _tabContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (_tab) {
      case CreationScopeTab.all:
        return [
          SliverToBoxAdapter(
            child: _SummaryRow(
              scope: const CreationScope.allProcessed(),
              title: l10n.f43StudioScopeAll,
              hint: l10n.f43StudioPickerAllHint,
              selected: widget.current.isAll,
              onTap: () => _choose(const CreationScope.allProcessed()),
            ),
          ),
        ];
      case CreationScopeTab.document:
        final documents = ref.watch(
          processedDocumentsProvider(
            ProcessedQuery(
              searchText: _search.isEmpty ? null : _search,
              limit: 200,
            ),
          ),
        );
        return _rows(
          context,
          documents.whenData(
            (all) => [
              for (final d in all)
                (scope: CreationScope.document(d.id), title: d.title),
            ],
          ),
          (entry) => entry.title,
          (entry) => _DocumentRow(
            documentId: entry.scope.id!,
            title: entry.title,
            selected: entry.scope == widget.current,
            onTap: () => _choose(entry.scope),
          ),
          filtered: false,
        );
      case CreationScopeTab.notebook:
        return _rows(
          context,
          ref
              .watch(notebooksProvider)
              .whenData(
                (all) => [
                  for (final n in all)
                    (scope: CreationScope.notebook(n.id), title: n.name),
                ],
              ),
          (entry) => entry.title,
          (entry) => _SummaryRow(
            scope: entry.scope,
            title: entry.title,
            selected: entry.scope == widget.current,
            onTap: () => _choose(entry.scope),
          ),
        );
      case CreationScopeTab.topic:
        return _topics(context);
    }
  }

  /// Los temas del Atlas por la dimensión elegida —los temas, las etiquetas o
  /// una categoría—, con su árbol, solo los que tienen algo procesado.
  List<Widget> _topics(BuildContext context) {
    final definitions = ref.watch(allPropertyDefinitionsProvider).valueOrNull;
    final spaces = ref.watch(allSpacesProvider).valueOrNull;
    if (definitions == null || spaces == null) return const [];
    final (:options, :selected) = topicDimensionsOf(
      definitions,
      hasSpaces: spaces.isNotEmpty,
      chosenId: _dimensionId ?? _currentDimension(),
    );
    final atlas = ref.watch(atlasProvider(selected.id));
    final rows = _rows(
      context,
      atlas.whenData(
        (snapshot) => [
          for (final node in snapshot.nodes)
            if (node.itemCount > 0)
              (
                scope: selected.isSpaces
                    ? CreationScope.space(node.valueId)
                    : CreationScope.topic(node.valueId),
                title: node.label,
                node: node,
              ),
        ],
      ),
      (entry) => entry.title,
      (entry) => _SummaryRow(
        scope: entry.scope,
        title: entry.title,
        // El árbol, sangrado; buscando, plano.
        depth: _search.isEmpty ? entry.node.depth : 0,
        selected: entry.scope == widget.current,
        onTap: () => _choose(entry.scope),
      ),
    );
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        sliver: SliverToBoxAdapter(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TopicDimensionMenu(
              key: const Key('creation-scope-dimension'),
              options: options,
              selected: selected,
              onSelected: (dimension) =>
                  setState(() => _dimensionId = dimension.id),
            ),
          ),
        ),
      ),
      ...rows,
    ];
  }

  /// La dimensión del tema elegido ahora, para abrir ahí: un espacio está en
  /// los temas; un valor, en su categoría (que no se sabe sin leerlo: la de
  /// por defecto).
  String? _currentDimension() =>
      widget.current is SpaceScope ? kSpacesDimensionId : null;

  /// Las filas de [entries], filtradas por la búsqueda si [filtered], con el
  /// vacío que corresponde.
  List<Widget> _rows<T>(
    BuildContext context,
    AsyncValue<List<T>> entries,
    String Function(T entry) titleOf,
    Widget Function(T entry) row, {
    bool filtered = true,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final list = entries.valueOrNull;
    if (list == null) return const [];
    final needle = _search.toLowerCase();
    final shown = filtered && needle.isNotEmpty
        ? [
            for (final e in list)
              if (titleOf(e).toLowerCase().contains(needle)) e,
          ]
        : list;
    if (shown.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          sliver: SliverToBoxAdapter(
            child: Text(
              _search.isEmpty
                  ? l10n.f43StudioPickerNothing
                  : l10n.f43StudioPickerNoMatch(_search),
              key: const Key('creation-scope-nothing'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ];
    }
    return [
      SliverList.builder(
        itemCount: shown.length,
        itemBuilder: (context, index) => row(shown[index]),
      ),
    ];
  }
}

/// Una fila de la hoja: el ícono, el nombre, el detalle y el ✓ si es la
/// elegida.
class _Row extends StatelessWidget {
  const _Row({
    required this.scope,
    required this.title,
    required this.selected,
    required this.onTap,
    this.detail,
    this.depth = 0,
  });

  final CreationScope scope;
  final String title;
  final String? detail;
  final bool selected;
  final int depth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      child: ListTile(
        key: ValueKey('creation-scope-option-${scope.storageKey}'),
        contentPadding: EdgeInsetsDirectional.only(
          start: 20 + 16.0 * depth.clamp(0, 4),
          end: 16,
        ),
        leading: Icon(
          creationScopeIcon(scope),
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: selected
              ? theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                )
              : null,
        ),
        subtitle: detail == null ? null : Text(detail!),
        trailing: selected
            ? Icon(
                Icons.check,
                color: scheme.primary,
                semanticLabel: l10n.f43StudioPickerChosen,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

/// Una fila con las cifras de su recorte, al día.
class _SummaryRow extends ConsumerWidget {
  const _SummaryRow({
    required this.scope,
    required this.title,
    required this.selected,
    required this.onTap,
    this.hint,
    this.depth = 0,
  });

  final CreationScope scope;
  final String title;
  final String? hint;
  final bool selected;
  final int depth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final summary = ref.watch(creationScopeSummaryProvider(scope)).valueOrNull;
    final counts = summary == null ? null : creationScopeDetail(l10n, summary);
    final lines = [?hint, ?counts];
    return _Row(
      scope: scope,
      title: title,
      depth: depth,
      detail: lines.isEmpty ? null : lines.join('\n'),
      selected: selected,
      onTap: onTap,
    );
  }
}

/// Un documento: sus tarjetas, sus creaciones y si ya tiene resumen o
/// síntesis.
class _DocumentRow extends ConsumerWidget {
  const _DocumentRow({
    required this.documentId,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String documentId;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final source = ref
        .watch(creationSourcesProvider(CreationSourceIds([documentId])))
        .valueOrNull
        ?.firstOrNull;
    final detail = source == null
        ? null
        : [
            l10n.f43StudioCards(source.cards),
            if (source.creations > 0) l10n.f43StudioCreations(source.creations),
            if (source.hasSummary) l10n.f43StudioHasSummary,
            if (source.hasSynthesis) l10n.f43StudioHasSynthesis,
          ].join(' · ');
    return _Row(
      scope: CreationScope.document(documentId),
      title: title,
      detail: detail,
      selected: selected,
      onTap: onTap,
    );
  }
}

/// Uno de los recientes: con su nombre y sus cifras. Uno que ya no existe se
/// olvida solo.
class _RecentRow extends ConsumerWidget {
  const _RecentRow({
    required this.scope,
    required this.selected,
    required this.onTap,
  });

  final CreationScope scope;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final summary = ref.watch(creationScopeSummaryProvider(scope)).valueOrNull;
    if (summary == null) return const SizedBox.shrink();
    if (!summary.exists) {
      // Lo que apuntaba se borró: se olvida, después de este cuadro.
      final recents = ref.read(recentCreationScopesProvider.notifier);
      unawaited(Future.microtask(() => recents.forget(scope)));
      return const SizedBox.shrink();
    }
    return KeyedSubtree(
      key: ValueKey('creation-scope-recent-${scope.storageKey}'),
      child: _Row(
        scope: scope,
        title: summary.name ?? l10n.f43StudioScopeAll,
        detail: creationScopeDetail(l10n, summary),
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}
