import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/services/text_note_placement.dart';
import 'package:sinapsis/features/text_notes/presentation/text_note_actions.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

// Cómo se ven las notas en el texto (F45, paso 8b, mejora 19), en cualquier
// lector que pinta su texto: el pedazo con un subrayado fino punteado del
// color de la nota ([textNoteMarks], que pinta `RenderedMarkdown.buildSpans`)
// y, en el margen derecho a la altura de su renglón, **un globito**
// ([TextNoteMargin]), como el ícono de nota de Adobe o el comentario de Word:
// no tapa el texto ni le cambia el lugar a ninguna letra. Con varias notas en
// el mismo renglón, uno solo con el número.

/// Los subrayados punteados de las [notes] que tocan `[from, to)` del texto,
/// recortados a ese tramo y contados desde [from] —lo que cae en una página
/// o en un pedazo—. Las que no tienen lugar no se pintan.
List<NoteMark> textNoteMarks(
  BuildContext context,
  Iterable<PlacedTextNote> notes, {
  required int to,
  int from = 0,
}) => [
  for (final placed in notes)
    if (placed.placed && placed.end! > from && placed.start! < to)
      NoteMark(
        math.max(placed.start!, from) - from,
        math.min(placed.end!, to) - from,
        color: textNoteLine(context, placed.note.color),
      ),
];

/// Las notas cuyo pedazo toca la posición [offset] del texto —donde la
/// persona tocó—, en el orden del texto. Un toque en la mitad de la última
/// letra cae en su borde, como el de un resaltado (`highlightAt`).
List<TextNote> textNotesAt(Iterable<PlacedTextNote> notes, int offset) => [
  for (final placed in notes)
    if (placed.placed && placed.start! <= offset && offset <= placed.end!)
      placed.note,
];

/// El primer renglón de `[start, end)` dentro de [text] —un `RenderEditable`
/// o un `RenderParagraph`, con posiciones de lo que se ve—, en coordenadas
/// globales; `null` si todavía no se dibujó.
Rect? firstLineOf(RenderBox? text, int start, int end) {
  if (text == null || !text.attached || !text.hasSize || end <= start) {
    return null;
  }
  final selection = TextSelection(baseOffset: start, extentOffset: end);
  final boxes = switch (text) {
    RenderEditable() => text.getBoxesForSelection(selection),
    RenderParagraph() => text.getBoxesForSelection(selection),
    _ => const <TextBox>[],
  };
  if (boxes.isEmpty) return null;
  final first = boxes.first.toRect();
  return text.localToGlobal(first.topLeft) & first.size;
}

/// El texto [child] con su margen derecho de [gutter], donde van los
/// globitos de [notes] —las que empiezan en este texto—, cada uno a la altura
/// del primer renglón de su pedazo ([lineOf], en coordenadas globales).
///
/// [child] se dibuja con [gutter] menos de ancho a la derecha: es el margen
/// que la columna de lectura ya tenía, así que nada se mueve. El globito
/// mide lo que entra en el margen, nunca menos de 18; tocarlo —toda la altura
/// de su renglón, el ancho del margen— abre sus notas con [onOpen].
///
/// Cuándo se mide: después de cada cuadro en que esto se arma, y cuando
/// cambia el ancho. Lo medido solo vuelve a armar si algo se movió.
class TextNoteMargin extends StatefulWidget {
  const TextNoteMargin({
    required this.child,
    required this.gutter,
    required this.notes,
    required this.lineOf,
    required this.onOpen,
    super.key,
  });

  final Widget child;
  final double gutter;
  final List<PlacedTextNote> notes;
  final Rect? Function(PlacedTextNote note) lineOf;
  final ValueChanged<List<TextNote>> onOpen;

  @override
  State<TextNoteMargin> createState() => _TextNoteMarginState();
}

/// Un globito: su renglón, en el margen, y las notas que lleva.
@immutable
class _Spot {
  const _Spot(this.top, this.height, this.notes);

  final double top;
  final double height;
  final List<TextNote> notes;

  bool sameAs(_Spot other) =>
      (top - other.top).abs() < 0.5 &&
      (height - other.height).abs() < 0.5 &&
      listEquals(notes, other.notes);
}

class _TextNoteMarginState extends State<TextNoteMargin> {
  final _stack = GlobalKey();
  List<_Spot> _spots = const [];
  var _measuring = false;

  /// Lo que mide un globito en este margen.
  double get _size => (widget.gutter - 4).clamp(18, 28);

  void _measureSoon() {
    if (_measuring) return;
    _measuring = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measuring = false;
      if (mounted) _measure();
    });
  }

  void _measure() {
    final stack = _stack.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || !stack.attached || !stack.hasSize) return;
    final lines = <({double top, double height, TextNote note})>[];
    for (final placed in widget.notes) {
      final line = widget.lineOf(placed);
      if (line == null) continue;
      final top = stack.globalToLocal(line.topLeft).dy;
      lines.add((top: top, height: line.height, note: placed.note));
    }
    lines.sort((a, b) => a.top.compareTo(b.top));
    final spots = <_Spot>[];
    for (final line in lines) {
      final last = spots.isEmpty ? null : spots.last;
      // El mismo renglón: un solo globito, con el número.
      if (last != null && (line.top - last.top).abs() < 2) {
        spots[spots.length - 1] = _Spot(last.top, last.height, [
          ...last.notes,
          line.note,
        ]);
      } else {
        spots.add(_Spot(line.top, line.height, [line.note]));
      }
    }
    final same =
        spots.length == _spots.length &&
        [
          for (var i = 0; i < spots.length; i++) spots[i].sameAs(_spots[i]),
        ].every((s) => s);
    if (!same) setState(() => _spots = spots);
  }

  @override
  Widget build(BuildContext context) {
    _measureSoon();
    final size = _size;
    return LayoutBuilder(
      builder: (context, constraints) {
        _measureSoon();
        return Stack(
          key: _stack,
          children: [
            Padding(
              padding: EdgeInsets.only(right: widget.gutter),
              child: widget.child,
            ),
            if (widget.notes.isNotEmpty)
              for (final spot in _spots)
                Positioned(
                  right: 0,
                  width: widget.gutter,
                  top: spot.top - math.max(0, (size - spot.height) / 2),
                  height: math.max(spot.height, size),
                  child: TextNoteBubble(
                    notes: spot.notes,
                    size: size,
                    onTap: () => widget.onOpen(spot.notes),
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// El globito de un renglón: redondo, del color de su nota —o de la primera,
/// con el número si son varias—. Para el lector de pantalla, «Nota: …, sobre
/// "…"» o cuántas hay en el renglón, que se toca para abrir. Mide lo mismo con
/// la letra al doble: no crece con el texto, que es lo que no tiene que tapar.
class TextNoteBubble extends StatelessWidget {
  const TextNoteBubble({
    required this.notes,
    required this.size,
    required this.onTap,
    super.key,
  });

  final List<TextNote> notes;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final first = notes.first;
    final several = notes.length > 1;
    final line = textNoteLine(context, first.color);
    return Semantics(
      key: Key('text-note-bubble-${first.id}'),
      button: true,
      label: several
          ? l10n.f45S8bBubbleSeveral(notes.length)
          : textNoteSemantics(l10n, first),
      onTapHint: l10n.f45S8bOpenNote,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: textNoteFill(context, first.color),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(size / 2),
                topRight: Radius.circular(size / 2),
                bottomRight: Radius.circular(size / 2),
                bottomLeft: Radius.circular(size / 6),
              ),
              border: Border.all(color: line, width: 1.5),
            ),
            // La letra va oscura sobre un tono de resaltador, también en modo
            // oscuro.
            child: several
                ? Text(
                    '${notes.length}',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: size * 0.5,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  )
                : Icon(
                    Icons.notes_rounded,
                    size: size * 0.6,
                    color: Colors.black87,
                  ),
          ),
        ),
      ),
    );
  }
}
