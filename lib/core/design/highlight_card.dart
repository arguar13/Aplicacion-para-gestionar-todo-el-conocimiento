import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sinapsis/core/design/highlight_toolbar.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La ficha chica de un resaltado ya hecho (F38): se abre al tocarlo, desde
/// abajo, y deja cambiarle el color, pasarlo de fondo a subrayado o al revés,
/// escribirle o editarle la nota, o quitarlo.
///
/// **API, para quien la abre desde cualquier documento**
///
/// No sabe dónde se guarda nada: recibe el [highlight] tal como está y avisa
/// lo que la persona decide.
///
///  * [onLook]: se cambió el color o el estilo. Se avisa en cuanto se toca,
///    sin cerrar la ficha: se ve el cambio en el documento mientras se
///    elige. El color es `null` si el resaltado es de los de antes, con el
///    de siempre, y solo se le cambió el estilo.
///  * [onNote]: se tocó «Guardar» en la nota, con el texto ya recortado
///    (`null` si quedó en blanco). Cierra la ficha.
///  * [onDelete]: se tocó «Quitar este resaltado». Cierra la ficha.
///
/// Devuelve cuando la ficha se cierra, por la razón que sea.
Future<void> showHighlightCard(
  BuildContext context, {
  required Highlight highlight,
  required FutureOr<void> Function(HighlightColor? color, HighlightStyle style)
  onLook,
  required FutureOr<void> Function(String? note) onNote,
  required FutureOr<void> Function() onDelete,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _HighlightCard(
    highlight: highlight,
    onLook: onLook,
    onNote: onNote,
    onDelete: onDelete,
  ),
);

class _HighlightCard extends StatefulWidget {
  const _HighlightCard({
    required this.highlight,
    required this.onLook,
    required this.onNote,
    required this.onDelete,
  });

  final Highlight highlight;
  final FutureOr<void> Function(HighlightColor? color, HighlightStyle style)
  onLook;
  final FutureOr<void> Function(String? note) onNote;
  final FutureOr<void> Function() onDelete;

  @override
  State<_HighlightCard> createState() => _HighlightCardState();
}

class _HighlightCardState extends State<_HighlightCard> {
  late var _color = widget.highlight.color;
  late var _style = widget.highlight.style;
  late final _note = TextEditingController(text: widget.highlight.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _chooseColor(HighlightColor color) {
    setState(() => _color = color);
    unawaited(Future.sync(() => widget.onLook(color, _style)));
  }

  void _chooseStyle(HighlightStyle style) {
    setState(() => _style = style);
    // Un resaltado de antes, sin color elegido, conserva el de siempre.
    unawaited(Future.sync(() => widget.onLook(_color, style)));
  }

  void _saveNote() {
    final note = _note.text.trim();
    unawaited(Future.sync(() => widget.onNote(note.isEmpty ? null : note)));
    Navigator.of(context).pop();
  }

  void _delete() {
    unawaited(Future.sync(widget.onDelete));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.highlightCardTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            widget.highlight.excerpt,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            container: true,
            label: l10n.highlightCardColor,
            // Nueve muestras de 48 no entran en una fila de un teléfono
            // angosto: pasan a la línea de abajo.
            child: Wrap(
              children: [
                for (final color in HighlightColor.values)
                  HighlightColorDot(
                    key: Key('card-color-${color.name}'),
                    color: color,
                    selected: color == _color,
                    tooltip: highlightColorName(l10n, color),
                    onPressed: () => _chooseColor(color),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<HighlightStyle>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: HighlightStyle.fill,
                icon: const Icon(Icons.format_color_fill),
                label: Text(l10n.highlightStyleFill),
              ),
              ButtonSegment(
                value: HighlightStyle.underline,
                icon: const Icon(Icons.format_underlined),
                label: Text(l10n.highlightStyleUnderline),
              ),
            ],
            selected: {_style},
            onSelectionChanged: (selection) => _chooseStyle(selection.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: l10n.highlightAddNote,
              hintText: l10n.detailHighlightNoteHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.detailRemoveHighlight),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
              const Spacer(),
              FilledButton(onPressed: _saveNote, child: Text(l10n.detailSave)),
            ],
          ),
        ],
      ),
    );
  }
}
