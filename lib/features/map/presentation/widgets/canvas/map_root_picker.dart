import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/canvas_tree_builder.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que se eligió como punto de partida de Radial y Árbol: un tema o una
/// nota mapa.
typedef MapRootChoice = ({CanvasTreeRef ref, String title});

/// Abre el selector del punto de partida (lo que era el del Esquema, F14, D6):
/// una lista con búsqueda de las notas mapa, que ya traen ordenada una parte
/// del conocimiento, y de los temas —los de más elementos primero—.
Future<MapRootChoice?> showMapRootPicker(
  BuildContext context, {
  required TopicGraph graph,
  required Future<List<SchemaLink>> notes,
  required String topicKind,
}) => showModalBottomSheet<MapRootChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) =>
      _RootPicker(graph: graph, notes: notes, topicKind: topicKind),
);

class _RootPicker extends StatefulWidget {
  const _RootPicker({
    required this.graph,
    required this.notes,
    required this.topicKind,
  });

  final TopicGraph graph;
  final Future<List<SchemaLink>> notes;

  /// Qué son los temas acá: ver `topicSelectKind`.
  final String topicKind;

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
                key: const ValueKey('map-root-search'),
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: l10n.atlasSearchHint(widget.topicKind),
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
                            key: ValueKey('map-root-note-${note.target.id}'),
                            dense: true,
                            leading: const Icon(
                              Icons.account_tree_outlined,
                              size: 20,
                            ),
                            title: Text(note.title),
                            onTap: () => Navigator.of(context).pop((
                              ref: CanvasTreeRef.of(note.target),
                              title: note.title,
                            )),
                          ),
                      ],
                      if (shownTopics.isNotEmpty) ...[
                        _PickerHeading(
                          l10n.mapSchemaPickerTopics(widget.topicKind),
                        ),
                        for (final node in shownTopics)
                          ListTile(
                            key: ValueKey('map-root-topic-${node.valueId}'),
                            dense: true,
                            title: Text(node.label),
                            trailing: Text('${node.itemCount}'),
                            onTap: () => Navigator.of(context).pop((
                              ref: CanvasTreeRef.topic(node.valueId),
                              title: node.label,
                            )),
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
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
