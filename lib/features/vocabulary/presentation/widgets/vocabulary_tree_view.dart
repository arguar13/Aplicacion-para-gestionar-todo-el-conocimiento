import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:sinapsis/features/vocabulary/presentation/widgets/vocabulary_feedback.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los valores de UNA categoría de texto como árbol de temas y subtemas (F13).
///
/// Se puede reordenar de tres maneras, para que ninguna sea la única: el menú
/// de cada fila («Mover bajo…», «Llevar al primer nivel»), arrastrar una fila
/// sobre la que va a ser su padre —o sobre la franja de arriba, para llevarla
/// al primer nivel— y, con el teclado, las flechas para plegar y desplegar
/// más el menú, que se alcanza con Tab.
///
/// Mover siempre pide confirmación y dice cuánto mueve, y el aviso trae
/// «Deshacer»: una rama entera cambia de lugar de una vez.
class VocabularyTreeView extends ConsumerStatefulWidget {
  const VocabularyTreeView({
    required this.values,
    required this.onOpen,
    super.key,
  });

  /// Los valores de la categoría, ya en el orden en que se muestran.
  final List<VocabularyValueStat> values;

  /// Se abre el valor con ese identificador.
  final void Function(String valueId) onOpen;

  @override
  ConsumerState<VocabularyTreeView> createState() => _VocabularyTreeViewState();
}

class _VocabularyTreeViewState extends ConsumerState<VocabularyTreeView> {
  final Set<String> _expanded = {};
  bool _dragging = false;

  VocabularyTree get _tree => VocabularyTree([
    for (final v in widget.values) (id: v.id, parentId: v.parentId),
  ]);

  Map<String, VocabularyValueStat> get _byId => {
    for (final v in widget.values) v.id: v,
  };

  /// Las filas que se ven: cada raíz, y bajo las desplegadas sus hijos.
  List<VocabularyValueStat> _visible(VocabularyTree tree) {
    final byId = _byId;
    final rows = <VocabularyValueStat>[];
    void add(String id) {
      final value = byId[id];
      if (value == null) return;
      rows.add(value);
      if (_expanded.contains(id)) tree.childrenOf(id).forEach(add);
    }

    tree.roots.forEach(add);
    return rows;
  }

  Future<void> _requestMove(String valueId, String? parentId) async {
    // Antes de esperar nada: al terminar, esta pantalla puede haber cambiado.
    final feedback = VocabularyFeedback.of(context, ref);
    final controller = ref.read(vocabularyControllerProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final byId = _byId;
    final value = byId[valueId];
    if (value == null) return;

    final preview = await ref
        .read(vocabularyRepositoryProvider)
        .previewMove(valueId: valueId, parentId: parentId);
    if (!mounted) return;
    final plan = preview.fold((failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
      return null;
    }, (plan) => plan);
    if (plan == null) return;

    final parentLabel = parentId == null ? null : byId[parentId]?.label;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.vocabularyMoveConfirmTitle),
        content: Text(
          parentLabel == null
              ? l10n.vocabularyMoveToRootConfirmBody(
                  plan.valueCount,
                  value.label,
                )
              : l10n.vocabularyMoveConfirmBody(
                  plan.valueCount,
                  value.label,
                  parentLabel,
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.vocabularyMoveConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await controller.move(valueId: valueId, parentId: parentId);
    // Lo movido queda a la vista: se despliega el padre que lo recibió.
    if (mounted && parentId != null && result.isRight()) {
      setState(() => _expanded.add(parentId));
    }
    feedback.report(result);
  }

  Future<void> _chooseParent(VocabularyValueStat value) async {
    final tree = _tree;
    final candidates = [
      for (final v in widget.values)
        if (v.id != value.id &&
            v.id != value.parentId &&
            tree.problemMoving(value.id, v.id) == null)
          v,
    ];
    final parentId = await showDialog<String>(
      context: context,
      builder: (context) =>
          _ChooseParentDialog(value: value, candidates: candidates),
    );
    if (parentId == null || !mounted) return;
    await _requestMove(value.id, parentId);
  }

  KeyEventResult _onKey(VocabularyTree tree, String id, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final hasChildren = tree.childrenOf(id).isNotEmpty;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight && hasChildren) {
      setState(() => _expanded.add(id));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(() => _expanded.remove(id));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tree = _tree;
    final rows = _visible(tree);

    return Column(
      children: [
        // La franja del primer nivel solo aparece mientras se arrastra algo.
        if (_dragging)
          DragTarget<String>(
            onWillAcceptWithDetails: (details) =>
                _byId[details.data]?.parentId != null,
            onAcceptWithDetails: (details) => _requestMove(details.data, null),
            builder: (context, candidate, _) => Container(
              key: const ValueKey('vocabulary-drop-root'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: candidate.isEmpty
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Theme.of(context).colorScheme.primaryContainer,
              child: Center(child: Text(l10n.vocabularyDropToRoot)),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final value = rows[index];
              final children = tree.childrenOf(value.id);
              final expanded = _expanded.contains(value.id);
              return DragTarget<String>(
                onWillAcceptWithDetails: (details) =>
                    details.data != value.id &&
                    _byId[details.data]?.parentId != value.id &&
                    tree.problemMoving(details.data, value.id) == null,
                onAcceptWithDetails: (details) =>
                    _requestMove(details.data, value.id),
                builder: (context, candidate, _) => Focus(
                  onKeyEvent: (node, event) => _onKey(tree, value.id, event),
                  child: LongPressDraggable<String>(
                    data: value.id,
                    onDragStarted: () => setState(() => _dragging = true),
                    onDragEnd: (_) => setState(() => _dragging = false),
                    feedback: Material(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(value.label),
                      ),
                    ),
                    // `Material` y no `ColoredBox`: el ListTile pinta su fondo
                    // y sus salpicaduras sobre el `Material` más cercano.
                    child: Material(
                      color: candidate.isEmpty
                          ? Colors.transparent
                          : Theme.of(context).colorScheme.primaryContainer,
                      child: ListTile(
                        key: ValueKey('vocabulary-node-${value.id}'),
                        contentPadding: EdgeInsets.only(
                          left: 8.0 + 24.0 * value.depth,
                          right: 8,
                        ),
                        leading: children.isEmpty
                            ? const SizedBox(width: 40)
                            : IconButton(
                                tooltip: expanded
                                    ? l10n.vocabularyCollapseTooltip
                                    : l10n.vocabularyExpandTooltip,
                                icon: Icon(
                                  expanded
                                      ? Icons.expand_more
                                      : Icons.chevron_right,
                                ),
                                onPressed: () => setState(() {
                                  if (expanded) {
                                    _expanded.remove(value.id);
                                  } else {
                                    _expanded.add(value.id);
                                  }
                                }),
                              ),
                        title: Text(value.label),
                        subtitle: Text(
                          [
                            l10n.vocabularyUsage(value.usage),
                            if (children.isNotEmpty)
                              l10n.vocabularySubtopics(children.length),
                          ].join(' · '),
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: l10n.vocabularyValueActionsTooltip,
                          onSelected: (action) {
                            if (action == 'move') _chooseParent(value);
                            if (action == 'root') _requestMove(value.id, null);
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'move',
                              child: Text(l10n.vocabularyMoveUnder),
                            ),
                            if (value.parentId != null)
                              PopupMenuItem(
                                value: 'root',
                                child: Text(l10n.vocabularyMakeRoot),
                              ),
                          ],
                        ),
                        onTap: () => widget.onOpen(value.id),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Pide bajo qué valor va [value]: uno de [candidates], que ya son solo los que
/// se pueden —no él mismo, no un subtema suyo, y sin pasar de cinco niveles—.
class _ChooseParentDialog extends StatefulWidget {
  const _ChooseParentDialog({required this.value, required this.candidates});

  final VocabularyValueStat value;
  final List<VocabularyValueStat> candidates;

  @override
  State<_ChooseParentDialog> createState() => _ChooseParentDialogState();
}

class _ChooseParentDialogState extends State<_ChooseParentDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final shown = [
      for (final v in widget.candidates)
        if (_query.isEmpty ||
            normalizeVocabularyLabel(v.label).contains(_query))
          v,
    ];
    return AlertDialog(
      title: Text(l10n.vocabularyMoveChooseTitle(widget.value.label)),
      content: SizedBox(
        width: 400,
        height: 360,
        child: widget.candidates.isEmpty
            ? Center(child: Text(l10n.vocabularyMoveNoTargets))
            : Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l10n.vocabularySearchHint,
                      isDense: true,
                    ),
                    onChanged: (text) =>
                        setState(() => _query = normalizeVocabularyLabel(text)),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final v in shown)
                          ListTile(
                            key: ValueKey('vocabulary-target-${v.id}'),
                            title: Text(v.label),
                            contentPadding: EdgeInsets.only(
                              left: 8.0 + 16.0 * v.depth,
                            ),
                            onTap: () => Navigator.pop(context, v.id),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }
}
