import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El texto de una forma de contenido, subrayable.
///
/// Seleccionar una parte del texto agrega "Resaltar" al propio menú de
/// selección —junto a Copiar y Compartir—, en el lugar exacto donde ya
/// aparecen esas opciones. El resultado se ve incrustado en el propio texto
/// —con un fondo distinto— y además se lista abajo con su nota, para poder
/// repasar sin tener que encontrar cada fragmento en medio de un artículo
/// largo.
///
/// Antes había un botón aparte que aparecía debajo de todo el texto en vez
/// de junto a la selección: en cualquier forma de contenido más larga que
/// una pantalla —una transcripción, un artículo— quedaba a miles de
/// píxeles de donde el usuario estaba mirando, y en la práctica era
/// invisible. `contextMenuBuilder` lo resuelve sin volver al menú nativo
/// del sistema operativo que se había descartado antes: sigue siendo un
/// widget de Flutter, normal y corriente —se prueba con `tester.tap` como
/// cualquier otro—, solo que Flutter lo posiciona junto a la selección en
/// vez de en un lugar fijo.
class HighlightableText extends ConsumerStatefulWidget {
  const HighlightableText({
    required this.renditionId,
    required this.content,
    super.key,
  });

  final String renditionId;
  final String content;

  @override
  ConsumerState<HighlightableText> createState() => _HighlightableTextState();
}

class _HighlightableTextState extends ConsumerState<HighlightableText> {
  Future<void> _highlightSelection(TextSelection selection) async {
    final excerpt = selection.textInside(widget.content);

    // `null` es "se canceló". Una nota vacía sigue siendo una confirmación
    // válida —resaltar sin explicar por qué es perfectamente legítimo— y se
    // guarda como ausente, igual que hace el repositorio con cualquier nota
    // en blanco.
    final note = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(initialNote: null, excerpt: excerpt),
    );
    if (note == null || !mounted) return;

    await ref
        .read(organizeRepositoryProvider)
        .createHighlight(
          renditionId: widget.renditionId,
          startOffset: selection.start,
          endOffset: selection.end,
          excerpt: excerpt,
          note: note.isEmpty ? null : note,
        );
  }

  /// Agrega "Resaltar" al menú de selección que Flutter ya arma para
  /// Copiar/Compartir, en vez de dibujar uno propio: mismo look nativo del
  /// resto del menú, y Flutter lo posiciona solo junto a la selección
  /// activa, sea cual sea el punto de un texto largo donde el usuario esté
  /// parado.
  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final selection = editableTextState.textEditingValue.selection;

    final buttonItems = [
      if (!selection.isCollapsed)
        ContextMenuButtonItem(
          onPressed: () {
            ContextMenuController.removeAny();
            unawaited(_highlightSelection(selection));
          },
          label: l10n.detailHighlightSelection,
        ),
      ...editableTextState.contextMenuButtonItems,
    ];

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final highlights =
        ref
            .watch(renditionHighlightsProvider(widget.renditionId))
            .valueOrNull ??
        const <Highlight>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText.rich(
          _buildSpans(theme, highlights),
          contextMenuBuilder: _buildContextMenu,
        ),
        if (highlights.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            l10n.detailHighlightsTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final highlight in highlights)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.highlight),
              title: Text(
                highlight.excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: highlight.note == null ? null : Text(highlight.note!),
              onTap: () => _editNote(ref, highlight),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l10n.detailRemoveHighlight,
                onPressed: () => ref
                    .read(organizeRepositoryProvider)
                    .deleteHighlight(highlight.id),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _editNote(WidgetRef ref, Highlight highlight) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) =>
          _NoteDialog(initialNote: highlight.note, excerpt: highlight.excerpt),
    );
    if (result == null || !mounted) return;

    await ref
        .read(organizeRepositoryProvider)
        .updateHighlightNote(id: highlight.id, note: result);
  }

  /// Corta el contenido en tramos planos y resaltados, alternados.
  ///
  /// Se ignoran los resaltados cuyo rango ya no entra en el texto actual: si
  /// la rendition se regeneró —una transcripción rehecha con un modelo
  /// mejor— sus índices pueden apuntar más allá de donde ahora termina el
  /// texto, y usarlos tal cual rompería con un error de rango en vez de
  /// mostrar el texto igual, sin ese resaltado.
  TextSpan _buildSpans(ThemeData theme, List<Highlight> highlights) {
    final content = widget.content;
    final valid = highlights.where((h) => h.endOffset <= content.length);

    final spans = <TextSpan>[];
    var cursor = 0;

    for (final highlight in valid) {
      if (highlight.startOffset < cursor) continue; // se solapa con el anterior

      if (highlight.startOffset > cursor) {
        spans.add(
          TextSpan(text: content.substring(cursor, highlight.startOffset)),
        );
      }

      spans.add(
        TextSpan(
          text: content.substring(highlight.startOffset, highlight.endOffset),
          style: TextStyle(
            backgroundColor: theme.colorScheme.tertiaryContainer,
          ),
        ),
      );

      cursor = highlight.endOffset;
    }

    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor)));
    }

    return TextSpan(
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
      children: spans,
    );
  }
}

/// Ver o poner la nota de un resaltado: en blanco al crear uno, con lo que
/// ya tenía al editarlo.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initialNote, required this.excerpt});

  final String? initialNote;
  final String excerpt;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _controller = TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.detailHighlightNoteDialogTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.excerpt,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: l10n.detailHighlightNoteHint,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.detailSave),
        ),
      ],
    );
  }
}
