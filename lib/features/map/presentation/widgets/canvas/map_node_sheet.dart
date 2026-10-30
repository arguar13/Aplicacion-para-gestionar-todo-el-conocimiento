import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/entities/map_node_facts.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_network.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una acción de la ficha: su clave —para las pruebas y para que la persona
/// la encuentre siempre en el mismo lugar—, su ícono, su nombre y qué hace.
typedef MapNodeAction = ({
  String id,
  IconData icon,
  String label,
  VoidCallback onPressed,
});

/// Lo que hace cada acción de la ficha, en el lienzo: a un tema le llega su
/// valor; a un documento, su identificador.
typedef MapNodeHandlers = ({
  ValueChanged<MapNodeRef> enter,
  ValueChanged<MapNodeRef> center,
  VoidCallback exitFocus,
  ValueChanged<String> openTopic,
  ValueChanged<String> openItem,
  ValueChanged<String> ask,
  ValueChanged<CreationScope> study,
  ValueChanged<String> link,
  ValueChanged<String> seeLinks,
});

/// Lo que se puede hacer con el nodo de [facts] —llamado [title]—, lo
/// principal primero: en lo que junta temas, «Entrar»; en un documento,
/// «Abrir».
///
/// - **Entrar**, en una comunidad, un grupo o un tema.
/// - **Centrar aquí**, o **Salir del foco** si ya está en el centro
///   ([centered]); un grupo no se centra.
/// - **Abrir**: un tema en el Explorador, un documento en Procesado.
/// - **Preguntar al chat**, con [mapNodeQuestion], salvo en un grupo.
/// - **Estudiar**: un tema —un espacio de F37 si [spaces]— o un documento.
/// - En un documento, **Vincular** y **Ver sus vínculos**, si no se están
///   viendo ya con él en foco ([showingItsLinks]).
List<MapNodeAction> mapNodeActions(
  AppLocalizations l10n,
  MapNodeFacts facts, {
  required String title,
  required bool centered,
  required bool showingItsLinks,
  required bool spaces,
  required MapNodeHandlers on,
}) {
  final node = facts.ref;
  final question = mapNodeQuestion(l10n, facts, title);
  final study = switch (node) {
    MapCommunityRef() => null,
    MapTopicRef(:final valueId) =>
      spaces ? CreationScope.space(valueId) : CreationScope.topic(valueId),
    MapDocumentRef(:final itemId) => CreationScope.document(itemId),
  };
  final open = switch (node) {
    MapCommunityRef() => null,
    MapTopicRef(:final valueId) => (
      id: 'open',
      icon: Icons.folder_open_outlined,
      label: l10n.f44S4Open,
      onPressed: () => on.openTopic(valueId),
    ),
    MapDocumentRef(:final itemId) => (
      id: 'open',
      icon: Icons.open_in_new,
      label: l10n.f44S4Open,
      onPressed: () => on.openItem(itemId),
    ),
  };
  final group = facts.kind == MapNodeKind.group;
  return [
    if (facts.canEnter)
      (
        id: 'enter',
        icon: Icons.zoom_in,
        label: l10n.f44S4Enter,
        onPressed: () => on.enter(node),
      )
    else
      ?open,
    if (!group && centered)
      (
        id: 'exit-focus',
        icon: Icons.center_focus_weak,
        label: l10n.f44S4ExitFocus,
        onPressed: on.exitFocus,
      )
    else if (!group)
      (
        id: 'center',
        icon: Icons.center_focus_strong,
        label: l10n.f44S4Center,
        onPressed: () => on.center(node),
      ),
    if (facts.canEnter) ?open,
    if (question != null)
      (
        id: 'ask',
        icon: Icons.auto_awesome,
        label: l10n.f44S4Ask,
        onPressed: () => on.ask(question),
      ),
    if (study != null)
      (
        id: 'study',
        icon: Icons.school_outlined,
        label: l10n.f44S4Study,
        onPressed: () => on.study(study),
      ),
    if (node case MapDocumentRef(:final itemId)) ...[
      (
        id: 'link',
        icon: Icons.add_link,
        label: l10n.f44S4Link,
        onPressed: () => on.link(itemId),
      ),
      if (!showingItsLinks)
        (
          id: 'see-links',
          icon: Icons.link,
          label: l10n.f44S4SeeLinks,
          onPressed: () => on.seeLinks(itemId),
        ),
    ],
  ];
}

/// La ficha de un nodo del lienzo del Mapa (F44, paso 4): abajo, corta y sin
/// tapar el dibujo —el lienzo se achica para dejarle lugar—.
///
/// Dice qué es y cuánto tiene ([mapNodeFactsLine]), con qué se une más —cada
/// vecino se toca para ir a él—, lo más reciente de una comunidad, el tema de
/// un documento y, debajo, lo que se puede hacer con él ([actions], la primera
/// como la principal).
///
/// Con el lector de pantalla es un contenedor con su nombre («Ficha de
/// Cristianismo»), el título se anuncia al abrirse y cada vecino y cada acción
/// es un botón con lo que hace.
class MapNodeSheet extends StatelessWidget {
  const MapNodeSheet({
    required this.facts,
    required this.title,
    required this.topicKind,
    required this.actions,
    required this.onGoTo,
    required this.onClose,
    super.key,
  });

  final MapNodeFacts facts;

  /// El nombre, ya rotulado: el de un grupo lo pone el lienzo.
  final String title;

  /// Qué es un tema acá: ver `topicSelectKind`.
  final String topicKind;
  final List<MapNodeAction> actions;

  /// Ir a un vecino, a lo más reciente o al tema de un documento.
  final ValueChanged<MapNodeRef> onGoTo;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = _accentOf(facts, colors, theme.brightness);
    final topics = facts.topicNames;
    final hiddenTopics = facts.topicCount - topics.length;
    final topicsLine = [
      '${l10n.f44S4Topics(topicKind)}: ${topics.join(', ')}',
      if (hiddenTopics > 0) l10n.mapBoardMore(hiddenTopics),
    ].join(' ');

    return Material(
      key: const ValueKey('map-sheet'),
      color: colors.surfaceContainerLow,
      elevation: 3,
      shadowColor: colors.shadow.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outlineVariant),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: l10n.f44S4SheetLabel(title),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(_iconOf(facts.kind), color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // Se anuncia al abrirse: quien usa el lector sabe de qué
                    // es la ficha sin ir a buscarla.
                    child: Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(
                        title,
                        key: const ValueKey('map-sheet-title'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('map-sheet-close'),
                    tooltip: l10n.f44S4SheetClose,
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      mapNodeFactsLine(l10n, facts, topicKind),
                      key: const ValueKey('map-sheet-facts'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (facts.within case final within?)
                      Text(
                        l10n.f44S4Within(within),
                        style: theme.textTheme.bodySmall,
                      ),
                    if (topics.isNotEmpty &&
                        facts.kind == MapNodeKind.community)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          topicsLine,
                          key: const ValueKey('map-sheet-topics'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (facts.neighbors.isNotEmpty)
                      _Places(
                        label: l10n.f44S4JoinsWith,
                        places: [
                          for (final neighbor in facts.neighbors)
                            (
                              key:
                                  'map-sheet-neighbor-${neighbor.ref.sceneKey}',
                              place: neighbor,
                            ),
                        ],
                        onGoTo: onGoTo,
                      ),
                    if (facts.latest case final latest?)
                      _Places(
                        label: l10n.f44S4Latest,
                        places: [(key: 'map-sheet-latest', place: latest)],
                        onGoTo: onGoTo,
                      ),
                    if (facts.place case final place?)
                      _Places(
                        label: l10n.mapSchemaNodeTopic(topicKind),
                        places: [(key: 'map-sheet-place', place: place)],
                        onGoTo: onGoTo,
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < actions.length; i++)
                          _ActionButton(action: actions[i], primary: i == 0),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconOf(MapNodeKind kind) => switch (kind) {
    MapNodeKind.community => Icons.bubble_chart_outlined,
    MapNodeKind.group => Icons.workspaces_outline,
    MapNodeKind.topic => Icons.label_outline,
    MapNodeKind.source => Icons.article_outlined,
    MapNodeKind.note => Icons.sticky_note_2_outlined,
  };

  static Color _accentOf(
    MapNodeFacts facts,
    ColorScheme colors,
    Brightness brightness,
  ) => switch (facts.kind) {
    MapNodeKind.source => EntityRole.source.accent(colors),
    MapNodeKind.note => EntityRole.note.accent(colors),
    MapNodeKind.group => colors.outline,
    MapNodeKind.community ||
    MapNodeKind.topic => mapCommunityColor(facts.group, colors, brightness),
  };
}

/// Una línea de la ficha con lo que se toca para ir ahí: «Une con: Imperio
/// romano, Literatura».
class _Places extends StatelessWidget {
  const _Places({
    required this.label,
    required this.places,
    required this.onGoTo,
  });

  final String label;
  final List<({String key, MapNodeNeighbor place})> places;
  final ValueChanged<MapNodeRef> onGoTo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$label:', style: theme.textTheme.labelLarge),
          for (final (:key, :place) in places)
            ActionChip(
              key: ValueKey(key),
              label: Text(
                place.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              tooltip: l10n.f44S4ShowInMap(place.label),
              visualDensity: VisualDensity.compact,
              onPressed: () => onGoTo(place.ref),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, required this.primary});

  final MapNodeAction action;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final key = ValueKey('map-sheet-${action.id}');
    final icon = Icon(action.icon, size: 18);
    final label = Text(action.label);
    return primary
        ? FilledButton.tonalIcon(
            key: key,
            onPressed: action.onPressed,
            icon: icon,
            label: label,
          )
        : OutlinedButton.icon(
            key: key,
            onPressed: action.onPressed,
            icon: icon,
            label: label,
          );
  }
}

/// Lo que tiene un nodo, en una línea: «7 documentos · 3 temas · 2 vínculos»
/// en una comunidad, «5 documentos · unido a 4 temas» en un tema y «Fuente · 2
/// vínculos a la vista» en un documento.
String mapNodeFactsLine(
  AppLocalizations l10n,
  MapNodeFacts facts,
  String topicKind,
) {
  final parts = switch (facts.kind) {
    MapNodeKind.community => [
      if (facts.documentCount case final documents?)
        l10n.f44S4Documents(documents),
      l10n.mapTopicCount(topicKind, facts.topicCount),
      if (facts.linkCount case final links?) l10n.f44S4Links(links),
    ],
    MapNodeKind.group => [l10n.mapTopicCount(topicKind, facts.topicCount)],
    MapNodeKind.topic => [
      if (facts.documentCount case final documents?)
        l10n.f44S4Documents(documents),
      l10n.f44S4JoinedTopics(topicKind, facts.topicCount),
    ],
    MapNodeKind.source || MapNodeKind.note => [
      if (facts.kind == MapNodeKind.note)
        l10n.mapSchemaNodeNote
      else
        l10n.mapSchemaNodeSource,
      if (facts.linkCount case final links?) l10n.f44S4LinksShown(links),
    ],
  };
  return parts.join(' · ');
}

/// [names] en una frase: «Roma», «Roma y Grecia», «Roma, Grecia y Egipto».
String mapListAnd(AppLocalizations l10n, List<String> names) {
  if (names.length <= 1) return names.join();
  return l10n.f44S4ListAnd(
    names.sublist(0, names.length - 1).join(', '),
    names.last,
  );
}

/// La pregunta de «✨ Preguntar al chat» sobre el nodo de [facts], llamado
/// [title]: qué dicen los documentos sobre él y, si tiene vecinos, cómo se
/// relaciona con ellos —«¿Qué dicen mis documentos sobre Cristianismo y cómo
/// se relaciona con Imperio romano y Literatura?»—. Una comunidad se nombra por
/// sus temas principales («Cristianismo y Tomás de Aquino»), y cada vecina, por
/// el suyo. `null` en un grupo, que no es un tema del que preguntar.
String? mapNodeQuestion(
  AppLocalizations l10n,
  MapNodeFacts facts,
  String title,
) {
  final others = mapListAnd(l10n, [
    for (final neighbor in facts.neighbors) neighbor.shortLabel,
  ]);
  switch (facts.kind) {
    case MapNodeKind.group:
      return null;
    case MapNodeKind.community || MapNodeKind.topic:
      final names = facts.kind == MapNodeKind.community
          ? (facts.nameLabels.isEmpty ? [title] : facts.nameLabels)
          : [title];
      final subject = mapListAnd(l10n, names);
      return facts.neighbors.isEmpty
          ? l10n.f44S4AskAbout(subject)
          : l10n.f44S4AskAboutWith(names.length, subject, others);
    case MapNodeKind.source || MapNodeKind.note:
      return facts.neighbors.isEmpty
          ? l10n.f44S4AskDocument(title)
          : l10n.f44S4AskDocumentWith(title, others);
  }
}
