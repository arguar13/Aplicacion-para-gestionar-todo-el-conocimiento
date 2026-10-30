import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/topic_dimension_menu.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';
import 'package:sinapsis/features/atlas/presentation/providers/atlas_providers.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_catalog.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_scope_listing.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_source_chips.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
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

/// La hoja del selector (F43, M11): **arriba**, el buscador y las pestañas
/// —«Todo», «Documentos», «Cuadernos» y «Temas»—; **debajo, una sola lista**:
/// «Recientes» —como mucho tres— y «Todos», de la A a la Z, sin repetir los
/// recientes. En «Todo», la primera fila es «Todo lo procesado». Con texto en
/// el buscador, una sola lista de resultados.
///
/// Cada fila dice lo mismo en todos lados: el nombre y una línea de lo que
/// tiene, cada dato con su ícono y su color de tipo («12 tarjetas», «1
/// creación», «Resumen», «Síntesis»). Lo elegido lleva ✓ y va resaltado.
///
/// **Todo sale de Procesado** (decisión D): un documento es un procesado, un
/// cuaderno uno de los de F41 y un tema uno del Atlas, que F41 ya arma solo
/// con lo procesado —un tema sin nada procesado no aparece—. La Biblioteca no
/// aparece.
///
/// **Con miles de documentos sigue fluida**: las líneas llegan todas juntas,
/// en lote ([creationScopeCatalogProvider]) —nunca una consulta por fila—, la
/// lista se arma de a lo que se ve y el orden de la A a la Z se hace una vez
/// por catálogo, no al escribir.
class CreationScopePicker extends ConsumerStatefulWidget {
  const CreationScopePicker({required this.current, super.key});

  final CreationScope current;

  @override
  ConsumerState<CreationScopePicker> createState() =>
      _CreationScopePickerState();
}

class _CreationScopePickerState extends ConsumerState<CreationScopePicker>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: CreationScopeTab.values.length,
    initialIndex: CreationScopeTab.of(widget.current).index,
    vsync: this,
  )..addListener(_onTab);

  /// La lista de debajo: cambiar de pestaña o de búsqueda la vuelve arriba,
  /// donde empieza lo nuevo.
  final _list = ScrollController();
  var _search = '';
  String? _dimensionId;

  /// El último catálogo que llegó: cambiar de categoría en «Temas» no deja la
  /// hoja en blanco mientras llega el nuevo.
  CreationScopeCatalog? _lastCatalog;

  /// Lo armado una vez, mientras no cambie de dónde sale.
  AtlasSnapshot? _topicsAtlas;
  List<({CreationScope scope, String name})> _topics = const [];
  CreationScopeListing? _listing;
  (CreationScopeCatalog, List<({CreationScope scope, String name})>)?
  _listingFrom;

  CreationScopeTab get _tab => CreationScopeTab.values[_tabs.index];

  void _onTab() {
    setState(() {});
    _toTop();
  }

  void _toTop() {
    if (_list.hasClients) _list.jumpTo(0);
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTab)
      ..dispose();
    _list.dispose();
    super.dispose();
  }

  void _choose(CreationScope scope) => Navigator.of(context).pop(scope);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

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
                  CreationCloseButton(
                    key: const Key('creation-scope-close'),
                    tooltip: l10n.f43StudioClose,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: TextField(
                key: const Key('creation-scope-search'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.f43S18Search,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
                onChanged: (text) {
                  setState(() => _search = text.trim());
                  _toTop();
                },
              ),
            ),
            TabBar(
              key: const Key('creation-scope-tabs'),
              controller: _tabs,
              // Las cuatro entran en 360 dp con la letra normal; con la letra
              // grande, se desplazan en vez de cortarse.
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              tabs: [
                for (final tab in CreationScopeTab.values)
                  Tab(
                    key: Key('creation-scope-tab-${tab.name}'),
                    text: _tabLabel(l10n, tab),
                  ),
              ],
            ),
            Flexible(
              child: CustomScrollView(
                key: const Key('creation-scope-list'),
                controller: _list,
                slivers: [
                  ..._listSlivers(context),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _tabLabel(AppLocalizations l10n, CreationScopeTab tab) =>
      switch (tab) {
        CreationScopeTab.all => l10n.f43S18TabAll,
        CreationScopeTab.document => l10n.f43S18TabDocuments,
        CreationScopeTab.notebook => l10n.f43S18TabNotebooks,
        CreationScopeTab.topic => l10n.f43S18TabTopics,
      };

  /// La lista de debajo de las pestañas: lo de la pestaña elegida, o los
  /// resultados de la búsqueda.
  List<Widget> _listSlivers(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final recents = ref.watch(recentCreationScopesProvider);
    final definitions = ref.watch(allPropertyDefinitionsProvider).valueOrNull;
    final spaces = ref.watch(allSpacesProvider).valueOrNull;
    if (definitions == null || spaces == null) return const [];
    final (:options, :selected) = topicDimensionsOf(
      definitions,
      hasSpaces: spaces.isNotEmpty,
      chosenId: _dimensionId ?? _currentDimension(),
    );
    final atlas = ref.watch(atlasProvider(selected.id)).valueOrNull;
    if (atlas == null && _lastCatalog == null) return const [];
    final topics = atlas == null ? _topics : _topicsOf(atlas, selected);

    // Las líneas de todo, en lote: los documentos y los cuadernos siempre, y
    // de los temas, los de esta categoría y los recientes.
    final keys = CreationScopeKeys({
      for (final topic in topics) topic.scope,
      for (final scope in recents)
        if (CreationScopeTab.topic.includes(scope)) scope,
    });
    final fresh = ref.watch(creationScopeCatalogProvider(keys)).valueOrNull;
    final catalog = fresh ?? _lastCatalog;
    if (catalog == null) return const [];
    _lastCatalog = catalog;
    final listing = _listingOf(catalog, topics);
    if (fresh != null) _forgetMissing(listing.missing(recents));

    final kinds = ref.watch(creationKindRegistryProvider);
    Widget row(CreationScopeEntry entry, {bool recent = false}) => _ScopeRow(
      key: recent
          ? ValueKey('creation-scope-recent-${entry.scope.storageKey}')
          : null,
      entry: entry,
      kinds: kinds,
      selected: entry.scope == widget.current,
      onTap: () => _choose(entry.scope),
    );

    if (_search.isNotEmpty) {
      // Lo que lo tiene en el texto, una lectura por búsqueda: solo donde hay
      // documentos.
      final inText =
          _tab == CreationScopeTab.all || _tab == CreationScopeTab.document
          ? ref.watch(creationScopeTextSearchProvider(_search)).valueOrNull
          : null;
      final results = listing.search(_tab, _search, inText: inText ?? const {});
      if (results.isEmpty) {
        return [_message(context, l10n.f43StudioPickerNoMatch(_search))];
      }
      return [
        _label(l10n.f43S18Results(results.length)),
        SliverList.builder(
          itemCount: results.length,
          itemBuilder: (context, index) => row(results[index]),
        ),
      ];
    }

    final (:recent, :rest) = listing.sections(_tab, recents);
    return [
      if (_tab == CreationScopeTab.topic)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
      if (_tab == CreationScopeTab.all)
        SliverPadding(
          padding: const EdgeInsets.only(top: 8),
          sliver: SliverToBoxAdapter(
            child: row((
              scope: catalog.all.scope,
              name: l10n.f43StudioScopeAll,
              line: catalog.all,
            )),
          ),
        ),
      if (recent.isNotEmpty) ...[
        _label(l10n.f43StudioPickerRecent),
        SliverList.list(
          children: [for (final entry in recent) row(entry, recent: true)],
        ),
      ],
      if (rest.isNotEmpty) ...[
        _label(l10n.f43S18Everything),
        SliverList.builder(
          itemCount: rest.length,
          itemBuilder: (context, index) => row(rest[index]),
        ),
      ],
      if (recent.isEmpty && rest.isEmpty)
        _message(context, l10n.f43StudioPickerNothing),
    ];
  }

  /// Lo de [catalog] y [topics] de la A a la Z, armado una sola vez: escribir
  /// en el buscador o cambiar de pestaña no lo vuelve a ordenar.
  CreationScopeListing _listingOf(
    CreationScopeCatalog catalog,
    List<({CreationScope scope, String name})> topics,
  ) {
    final from = _listingFrom;
    if (_listing case final listing?
        when from != null &&
            identical(from.$1, catalog) &&
            identical(from.$2, topics)) {
      return listing;
    }
    _listingFrom = (catalog, topics);
    return _listing = CreationScopeListing(catalog: catalog, topics: topics);
  }

  /// Los temas de [atlas] que tienen algo procesado, cada uno con su rama
  /// —«Roma › Imperio»—: así, de la A a la Z, quedan juntos los de una rama y
  /// se sabe de cuál es cada uno.
  List<({CreationScope scope, String name})> _topicsOf(
    AtlasSnapshot atlas,
    TopicDimension dimension,
  ) {
    if (identical(atlas, _topicsAtlas)) return _topics;
    final byId = {for (final node in atlas.nodes) node.valueId: node};
    String pathOf(AtlasNode node) {
      final labels = <String>[];
      AtlasNode? at = node;
      // Un árbol mal armado no cuelga la hoja: un tope de escalones.
      while (at != null && labels.length < 16) {
        labels.insert(0, at.label);
        at = at.parentId == null ? null : byId[at.parentId];
      }
      return labels.join(' › ');
    }

    _topicsAtlas = atlas;
    return _topics = [
      for (final node in atlas.nodes)
        if (node.itemCount > 0)
          (
            scope: dimension.isSpaces
                ? CreationScope.space(node.valueId)
                : CreationScope.topic(node.valueId),
            name: pathOf(node),
          ),
    ];
  }

  /// Olvida los recientes que ya no existen, después de este cuadro.
  void _forgetMissing(List<CreationScope> missing) {
    if (missing.isEmpty) return;
    final recents = ref.read(recentCreationScopesProvider.notifier);
    unawaited(
      Future.microtask(() {
        for (final scope in missing) {
          recents.forget(scope);
        }
      }),
    );
  }

  /// La dimensión del tema elegido ahora, para abrir ahí: un espacio está en
  /// los temas; un valor, en su categoría (que no se sabe sin leerlo: la de
  /// por defecto).
  String? _currentDimension() =>
      widget.current is SpaceScope ? kSpacesDimensionId : null;

  Widget _label(String text) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverToBoxAdapter(
      child: Semantics(header: true, child: CreationSectionLabel(text)),
    ),
  );

  Widget _message(BuildContext context, String text) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    sliver: SliverToBoxAdapter(
      child: Text(
        text,
        key: const Key('creation-scope-nothing'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

/// El color de «N creaciones» en la línea: el de lo creado, que no es de
/// ningún tipo.
const _creationsAccent = CreationAccent(
  light: Color(0xFF3949AB),
  dark: Color(0xFFA8B4F0),
);

/// Un dato de la línea de una fila: su ícono, su color y su texto.
typedef _Datum = ({IconData icon, CreationAccent? accent, String text});

/// Lo que dice la línea de [line], en orden: los documentos —salvo en un
/// documento—, las tarjetas, las creaciones si hay, y el resumen y la síntesis
/// si los tiene. Cada dato con el ícono y el color de su tipo.
List<_Datum> _dataOf(
  AppLocalizations l10n,
  CreationScopeLine line,
  CreationKindRegistry kinds,
) {
  final cards = kinds.of(StudyCreationKind.flashcards);
  final summary = kinds.of(StudyCreationKind.summary);
  final synthesis = kinds.of(StudyCreationKind.synthesis);
  return [
    if (line.scope is! ProcessedDocumentScope)
      (
        icon: Icons.description_outlined,
        accent: null,
        text: l10n.f43StudioDocuments(line.documents),
      ),
    (
      icon: cards.iconData,
      accent: cards.accent,
      text: l10n.f43StudioCards(line.cards),
    ),
    if (line.creations > 0)
      (
        icon: Icons.auto_awesome_outlined,
        accent: _creationsAccent,
        text: l10n.f43StudioCreations(line.creations),
      ),
    if (line.hasSummary)
      (
        icon: summary.iconData,
        accent: summary.accent,
        text: l10n.f43S18Summary,
      ),
    if (line.hasSynthesis)
      (
        icon: synthesis.iconData,
        accent: synthesis.accent,
        text: l10n.f43S18Synthesis,
      ),
  ];
}

/// Una fila del selector, igual en «Recientes», en «Todos» y en los
/// resultados: el ícono de su clase, el nombre, la línea de lo que tiene y el
/// ✓ si es lo elegido, que además va resaltado.
///
/// El lector de pantalla la lee entera, de una vez: el nombre, qué es, lo que
/// tiene y si es lo elegido.
class _ScopeRow extends StatelessWidget {
  const _ScopeRow({
    required this.entry,
    required this.kinds,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final CreationScopeEntry entry;
  final CreationKindRegistry kinds;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scope = entry.scope;
    final data = _dataOf(l10n, entry.line, kinds);
    final background = selected
        ? scheme.secondaryContainer
        : scheme.surfaceContainerLow;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final kind = switch (scope) {
      AllProcessed() => null,
      ProcessedDocumentScope() => l10n.f43StudioPickerTabDocument,
      NotebookScope() => l10n.f43StudioPickerTabNotebook,
      TopicScope() || SpaceScope() => l10n.f43StudioPickerTabTopic,
    };
    final label = [
      [entry.name, ?kind].join(', '),
      [for (final datum in data) datum.text].join(', '),
      if (selected) l10n.f43StudioPickerChosen,
    ].join('. ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Semantics(
        key: ValueKey('creation-scope-option-${scope.storageKey}'),
        container: true,
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (selected ? scheme.primary : scheme.onSurface)
                          .withValues(alpha: selected ? 0.16 : 0.06),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      creationScopeIcon(scope),
                      size: 22,
                      color: selected ? scheme.primary : foreground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? scheme.onSecondaryContainer
                                : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          runSpacing: 2,
                          children: [
                            for (final datum in data)
                              _DatumView(
                                datum: datum,
                                background: background,
                                foreground: foreground,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_circle, color: scheme.primary),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un dato de la línea: su ícono en el color de su tipo —llevado a 3:1 sobre
/// el fondo de la fila— y el texto en el color de la línea, que se lee en
/// cualquier tema.
class _DatumView extends StatelessWidget {
  const _DatumView({
    required this.datum,
    required this.background,
    required this.foreground,
  });

  final _Datum datum;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor =
        datum.accent?.resolve(theme.brightness, background) ?? foreground;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(datum.icon, size: 16, color: iconColor),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            datum.text,
            style: theme.textTheme.bodySmall?.copyWith(color: foreground),
          ),
        ),
      ],
    );
  }
}
