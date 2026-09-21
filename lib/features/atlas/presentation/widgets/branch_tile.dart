import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';
import 'package:sinapsis/features/atlas/presentation/widgets/coverage_meter.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántas notas mapa se muestran como marca en la fila; el resto, detrás de
/// «+N».
const _maxMapNoteChips = 2;

/// Una rama del Atlas: el tema con lo que hay debajo, cuánto está trabajado y
/// por dónde entrar.
///
/// Muestra los conteos en cascada —fuentes y notas, cada una con el color con
/// que la app distingue una de otra—, el estado de cobertura, el rango de
/// fechas que cubre y sus notas mapa como puntos de entrada. Tocar la fila
/// pliega o despliega (una rama sin subtemas abre su material); el menú y las
/// marcas llevan al material, a la línea de tiempo y a las notas mapa.
///
/// Con el teclado: la flecha derecha despliega, la izquierda pliega, y Enter
/// hace lo que el toque.
class BranchTile extends StatelessWidget {
  const BranchTile({
    required this.node,
    required this.expanded,
    required this.searching,
    required this.onToggle,
    required this.onOpenMaterial,
    required this.onOpenTimeline,
    required this.onOpenNote,
    super.key,
  });

  final AtlasNode node;
  final bool expanded;

  /// Con una búsqueda activa el árbol no se pliega: tocar abre el material.
  final bool searching;

  final VoidCallback onToggle;
  final VoidCallback onOpenMaterial;
  final VoidCallback onOpenTimeline;
  final void Function(String noteId) onOpenNote;

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || searching) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        node.hasChildren &&
        !expanded) {
      onToggle();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && expanded) {
      onToggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final axis = _axisText(l10n);
    final canToggle = node.hasChildren && !searching;

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) => _onKey(event),
      child: ListTile(
        key: ValueKey('atlas-node-${node.valueId}'),
        contentPadding: EdgeInsetsDirectional.only(
          start: 8.0 + 20.0 * node.depth,
          end: 4,
        ),
        leading: node.hasChildren && !searching
            ? IconButton(
                tooltip: expanded
                    ? l10n.vocabularyCollapseTooltip
                    : l10n.vocabularyExpandTooltip,
                icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
                onPressed: onToggle,
              )
            : const SizedBox(width: 40),
        title: Text(node.label, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Counts(node: node),
            if (axis != null || node.mapNotes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (axis != null)
                      ActionChip(
                        key: ValueKey('atlas-axis-${node.valueId}'),
                        avatar: const Icon(Icons.timeline, size: 16),
                        label: Text(axis),
                        tooltip: l10n.atlasOpenTimeline,
                        visualDensity: VisualDensity.compact,
                        onPressed: onOpenTimeline,
                      ),
                    ..._mapNoteChips(context, l10n, colors),
                  ],
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CoverageMeter(coverage: node.coverage),
            PopupMenuButton<String>(
              key: ValueKey('atlas-menu-${node.valueId}'),
              tooltip: l10n.vocabularyValueActionsTooltip,
              onSelected: (action) {
                if (action == _material) onOpenMaterial();
                if (action == _timeline) onOpenTimeline();
                if (action.startsWith(_notePrefix)) {
                  onOpenNote(action.substring(_notePrefix.length));
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _material,
                  child: Text(l10n.atlasOpenMaterial),
                ),
                if (axis != null)
                  PopupMenuItem(
                    value: _timeline,
                    child: Text(l10n.atlasOpenTimeline),
                  ),
                for (final note in node.mapNotes)
                  PopupMenuItem(
                    value: '$_notePrefix${note.id}',
                    child: Row(
                      children: [
                        Icon(
                          SourceKind.manualNote.icon,
                          size: 18,
                          color: EntityRole.note.accent(colors),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            note.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        onTap: canToggle ? onToggle : onOpenMaterial,
      ),
    );
  }

  /// Las marcas de las notas mapa: las primeras, y «+N» con el resto.
  List<Widget> _mapNoteChips(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colors,
  ) {
    final notes = node.mapNotes;
    final accent = EntityRole.note.accent(colors);
    return [
      for (final note in notes.take(_maxMapNoteChips))
        ActionChip(
          key: ValueKey('atlas-map-${node.valueId}-${note.id}'),
          avatar: Icon(Icons.map_outlined, size: 16, color: accent),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(note.title, overflow: TextOverflow.ellipsis),
          ),
          tooltip: l10n.atlasMapNoteTooltip,
          side: BorderSide(color: EntityRole.note.outline(colors)),
          visualDensity: VisualDensity.compact,
          onPressed: () => onOpenNote(note.id),
        ),
      if (notes.length > _maxMapNoteChips)
        ActionChip(
          key: ValueKey('atlas-map-more-${node.valueId}'),
          label: Text('+${notes.length - _maxMapNoteChips}'),
          visualDensity: VisualDensity.compact,
          onPressed: () => _showAllMapNotes(context, l10n),
        ),
    ];
  }

  Future<void> _showAllMapNotes(BuildContext context, AppLocalizations l10n) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  l10n.atlasMapNotesTitle,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                subtitle: Text(node.label),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final note in node.mapNotes)
                      ListTile(
                        key: ValueKey('atlas-map-sheet-${note.id}'),
                        leading: const Icon(Icons.map_outlined),
                        title: Text(note.title),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onOpenNote(note.id);
                        },
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

  /// «44 a.C. – 476», o un solo año si la rama cubre uno; `null` si ningún
  /// elemento de la rama tiene fecha del hecho.
  String? _axisText(AppLocalizations l10n) {
    final first = node.firstYear;
    final last = node.lastYear;
    if (first == null) return null;
    final from = _yearText(l10n, first);
    if (last == null || last == first) return from;
    return '$from – ${_yearText(l10n, last)}';
  }

  /// El año astronómico como se lee: 0 es «1 a.C.», -43 es «44 a.C.». Igual
  /// que el eje de la línea de tiempo.
  static String _yearText(AppLocalizations l10n, int astronomicalYear) {
    return astronomicalYear <= 0
        ? l10n.timelineYearBce(1 - astronomicalYear)
        : '$astronomicalYear';
  }

  static const _material = 'material';
  static const _timeline = 'timeline';
  static const _notePrefix = 'note:';
}

/// Cuántas fuentes y cuántas notas hay en la rama, cada una con su color.
class _Counts extends StatelessWidget {
  const _Counts({required this.node});

  final AtlasNode node;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = theme.textTheme.bodySmall;

    Widget count(IconData icon, Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: style),
      ],
    );

    if (node.itemCount == 0) return Text(l10n.atlasCoverageEmpty, style: style);
    return Wrap(
      spacing: 12,
      children: [
        if (node.sourceCount > 0)
          count(
            Icons.article_outlined,
            EntityRole.source.accent(colors),
            l10n.atlasSourceCount(node.sourceCount),
          ),
        if (node.noteCount > 0)
          count(
            SourceKind.manualNote.icon,
            EntityRole.note.accent(colors),
            l10n.atlasNoteCount(node.noteCount),
          ),
      ],
    );
  }
}
