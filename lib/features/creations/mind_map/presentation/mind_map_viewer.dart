import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_json.dart';
import 'package:sinapsis/features/creations/mind_map/presentation/mind_map_canvas.dart';
import 'package:sinapsis/features/creations/mind_map/presentation/mind_map_node_sheet.dart';
import 'package:sinapsis/features/creations/mind_map/presentation/mind_map_scene.dart';
import 'package:sinapsis/features/creations/presentation/creation_actions.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El visor de un mapa mental (F43, punto 5 del plan), como el de NotebookLM:
///
/// - **un árbol horizontal** con la idea central a la izquierda y sus ramas
///   hacia la derecha, en nodos redondeados que se abren y se cierran con
///   «›» —al abrirse, el «›» apunta hacia atrás—. Arranca con las ramas
///   principales a la vista;
/// - **pellizco para acercar y alejar, y arrastre**, con los botones de
///   abajo para lo mismo, «Ampliar todo», «Contraer todo» y «Ajustar a la
///   pantalla»;
/// - abrir o cerrar una rama deja quieta la idea que se tocó: lo demás se
///   acomoda alrededor, sin que el mapa salte;
/// - **tocar una idea** abre su hoja, con «Preguntarle al chat sobre esto» y
///   «Ver en el documento».
///
/// Nada se anima: el mapa cambia de una vez, con «sin animaciones» o sin.
class MindMapViewer extends ConsumerStatefulWidget {
  const MindMapViewer({required this.creation, super.key});

  final StudyCreation creation;

  /// Lo más que se aleja y se acerca.
  static const double minScale = 0.15;
  static const double maxScale = 3;

  @override
  ConsumerState<MindMapViewer> createState() => _MindMapViewerState();
}

class _MindMapViewerState extends ConsumerState<MindMapViewer> {
  late MindMap _map = MindMapJson.decode(widget.creation.decodedContent);

  /// Las ideas con las ramas abiertas: de entrada, solo la central.
  late Set<String> _expanded = {_map.root.id};

  final _transform = TransformationController();
  MindMapMetrics? _metrics;
  MindMapScene? _scene;
  var _viewport = Size.zero;

  /// Si falta encuadrar el mapa: al abrirlo, o si cambió su contenido.
  var _fitPending = true;

  /// Si el visor ya se armó una vez: desde ahí escucha al controlador, y
  /// encuadrar mientras se acomoda la pantalla se deja para después.
  var _shown = false;

  @override
  void didUpdateWidget(MindMapViewer old) {
    super.didUpdateWidget(old);
    if (old.creation.content != widget.creation.content) {
      _map = MindMapJson.decode(widget.creation.decodedContent);
      _expanded = {
        _map.root.id,
        for (final id in _expanded)
          if (_map.find(id) != null) id,
      };
      _scene = null;
      _fitPending = true;
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  MindMapScene _build() => MindMapScene.build(_map, _expanded, _metrics!);

  /// Abre o cierra [node], con la idea quieta en la pantalla.
  void _toggle(MindMapNode node) {
    final before = _scene?.layout.rectOf(node.id);
    setState(() {
      final next = {..._expanded};
      if (!next.remove(node.id)) next.add(node.id);
      _expanded = next;
      _scene = _build();
    });
    final after = _scene!.layout.rectOf(node.id);
    if (before != null && after != null) {
      _transform.value = _transform.value.clone()
        ..translateByDouble(
          before.left - after.left,
          before.top - after.top,
          0,
          1,
        );
    }
  }

  void _expandAll() {
    setState(() {
      _expanded = {_map.root.id, ...mindMapBranchIds(_map)};
      _scene = _build();
    });
    _fit();
  }

  void _collapseAll() {
    setState(() {
      _expanded = {_map.root.id};
      _scene = _build();
    });
    _fit();
  }

  /// El mapa entero a la vista. Un mapa chico no se agranda de más.
  void _fit() {
    final scene = _scene;
    if (scene == null || _viewport.isEmpty) return;
    _transform.value = mindMapFitTransform(
      scene.size,
      _viewport,
      maxScale: 1.25,
      minScale: MindMapViewer.minScale,
    );
  }

  void _zoom(double factor) {
    if (_viewport.isEmpty) return;
    _transform.value = mindMapZoomTransform(
      _transform.value,
      factor,
      _viewport.center(Offset.zero),
      minScale: MindMapViewer.minScale,
      maxScale: MindMapViewer.maxScale,
    );
  }

  void _openNode(MindMapNode node, Color accent) => unawaited(
    showMindMapNodeSheet(
      context,
      ref,
      creation: widget.creation,
      map: _map,
      node: node,
      accent: accent,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = mindMapAccent.of(context);
    final palette = MindMapPalette.of(theme, accent);
    final metrics = MindMapMetrics.of(context);
    if (metrics != _metrics || _scene == null) {
      _metrics = metrics;
      _scene = _build();
    }
    final scene = _scene!;

    if (_map.root.label.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.f43MindEmpty,
            key: const Key('mind-map-empty'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
      );
    }

    final labels = MindMapCanvasLabels(
      node: (node, depth, {required open}) {
        final head = l10n.f43MindNodeLabel(node.label, depth + 1);
        if (!node.hasChildren) return head;
        final count = node.children.length;
        final branches = open
            ? l10n.f43MindNodeBranchesOpen(count)
            : l10n.f43MindNodeBranchesClosed(count);
        return '$head. $branches';
      },
      open: l10n.f43MindOpenBranch,
      close: l10n.f43MindCloseBranch,
      hint: l10n.f43MindNodeHint,
    );

    return ColoredBox(
      color: palette.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = constraints.biggest;
          if (_fitPending) {
            _fitPending = false;
            if (_shown) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _fit();
              });
            } else {
              // La primera vez el visor todavía no escucha al controlador:
              // se encuadra acá mismo, y el mapa aparece ya en su lugar.
              _transform.value = mindMapFitTransform(
                scene.size,
                _viewport,
                minScale: MindMapViewer.minScale,
              );
            }
          }
          _shown = true;
          return Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  label: l10n.f43MindCanvas(_map.title, _map.size),
                  explicitChildNodes: true,
                  child: InteractiveViewer(
                    key: const Key('mind-map-viewport'),
                    transformationController: _transform,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: MindMapViewer.minScale,
                    maxScale: MindMapViewer.maxScale,
                    child: MindMapCanvas(
                      scene: scene,
                      palette: palette,
                      metrics: metrics,
                      expanded: _expanded,
                      labels: labels,
                      onToggle: _toggle,
                      onTapNode: (node) => _openNode(node, accent),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                end: 12,
                bottom: 12 + MediaQuery.paddingOf(context).bottom,
                child: _Toolbar(
                  onZoomOut: () => _zoom(1 / 1.25),
                  onZoomIn: () => _zoom(1.25),
                  onFit: _fit,
                  onExpandAll: _expandAll,
                  onCollapseAll: _collapseAll,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Los botones de abajo, en una píldora: alejar, acercar, encuadrar, y abrir
/// o cerrar todas las ramas.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
    required this.onExpandAll,
    required this.onCollapseAll,
  });

  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    Widget button(String key, IconData icon, String tooltip, VoidCallback on) =>
        IconButton(
          key: Key('mind-map-$key'),
          icon: Icon(icon),
          tooltip: tooltip,
          onPressed: on,
        );
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 2,
      shadowColor: scheme.shadow.withValues(alpha: 0.3),
      shape: StadiumBorder(
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button('zoom-out', Icons.remove, l10n.f43MindZoomOut, onZoomOut),
            button('zoom-in', Icons.add, l10n.f43MindZoomIn, onZoomIn),
            button('fit', Icons.fit_screen_outlined, l10n.f43MindFit, onFit),
            button(
              'expand-all',
              Icons.unfold_more,
              l10n.f43MindExpandAll,
              onExpandAll,
            ),
            button(
              'collapse-all',
              Icons.unfold_less,
              l10n.f43MindCollapseAll,
              onCollapseAll,
            ),
          ],
        ),
      ),
    );
  }
}

/// El color del mapa: el de su tipo, el rosa de su ícono.
CreationAccent get mindMapAccent =>
    defaultCreationKindSpec(StudyCreationKind.mindMap).accent;

/// Los botones del mapa en la barra del visor: guardarlo como imagen.
List<Widget> mindMapViewerActions(
  BuildContext context,
  StudyCreation creation,
) => [
  Consumer(
    builder: (context, ref, _) => IconButton(
      key: const Key('mind-map-save-image'),
      icon: const Icon(Icons.image_outlined),
      tooltip: AppLocalizations.of(context)!.f43MindSaveImage,
      onPressed: () => unawaited(
        runCreationAction(context, ref, creation, CreationAction.download),
      ),
    ),
  ),
];
