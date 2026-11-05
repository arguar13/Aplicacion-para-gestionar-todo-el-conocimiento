import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sinapsis/features/creations/report/domain/report_canonical_text.dart';
import 'package:sinapsis/features/creations/report/domain/report_markup.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_text.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/services/text_note_placement.dart';
import 'package:sinapsis/features/text_notes/presentation/text_note_actions.dart';
import 'package:sinapsis/features/text_notes/presentation/widgets/text_note_margin.dart';

// Las notas sobre pedazos de un informe (F45, paso 8c): el informe se lee como
// un texto —su texto canónico, `ReportText`—, cada parte que se ve sabe dónde
// está en él (`ReportPartText`, con su `ReportTextPlace`), y con eso:
//
// - lo elegido se ubica en el texto, de la primera parte elegida a la última
//   ([ReportNoteParts.selected]), y se le pone «Nota»;
// - el pedazo de cada nota lleva el subrayado fino punteado de su color, y
//   tocarlo la abre;
// - el globito va en el margen derecho, a la altura del primer renglón de su
//   pedazo ([ReportNoteParts.lineOf]);
// - «Notas (N)» lleva a una nota —despliega su sección si estaba plegada— y
//   la marca un momento ([ReportNotes.flash]).

/// Las notas de un informe para las partes que lo dibujan (F45, paso 8c): su
/// texto, las notas ubicadas en él, la que se marca un momento —a la que se
/// fue desde «Notas (N)»— y dónde se anota cada parte que se ve. Sin esto
/// arriba —el índice, una vista previa— las partes se dibujan como siempre.
class ReportNotes extends InheritedWidget {
  const ReportNotes({
    required this.text,
    required this.notes,
    required this.parts,
    required this.onOpen,
    required super.child,
    this.flash,
    super.key,
  });

  /// El texto del informe, sobre el que valen las posiciones de [notes].
  final ReportText text;

  /// Las notas con lugar en [text], en el orden del texto.
  final List<PlacedTextNote> notes;

  /// Las partes que se ven ahora.
  final ReportNoteParts parts;

  /// Abre las notas que se tocaron.
  final ValueChanged<List<TextNote>> onOpen;

  /// `[start, end)` del texto, marcado un momento, o `null`.
  final (int, int)? flash;

  /// El de arriba, o `null` fuera de un informe con notas.
  static ReportNotes? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReportNotes>();

  @override
  bool updateShouldNotify(ReportNotes oldWidget) =>
      oldWidget.text != text ||
      oldWidget.flash != flash ||
      oldWidget.onOpen != onOpen ||
      !listEquals(oldWidget.notes, notes);
}

/// Las partes del informe que se ven ahora, por su lugar: para saber qué
/// está elegido, dónde está el renglón de una nota y a qué parte llevar la
/// vista.
class ReportNoteParts {
  final _built = <ReportTextPlace, _ReportPartTextState>{};

  void _add(ReportTextPlace place, _ReportPartTextState state) =>
      _built[place] = state;

  void _remove(ReportTextPlace place, _ReportPartTextState state) {
    if (identical(_built[place], state)) _built.remove(place);
  }

  /// El contexto de la parte de [place], si se ve.
  BuildContext? contextOf(ReportTextPlace place) {
    final state = _built[place];
    return state == null || !state.mounted ? null : state.context;
  }

  /// Lo elegido, en posiciones de [text]: de la primera letra elegida de la
  /// primera parte a la última de la última, en el orden del texto. `null`
  /// sin nada elegido en el informe.
  ({int start, int end})? selected(ReportText text) {
    int? start;
    int? end;
    for (final part in text.parts) {
      final range = _built[part.place]?.selectedRange;
      if (range == null) continue;
      start ??= part.start + range.start;
      end = part.start + range.end;
    }
    if (start == null || end == null || end <= start) return null;
    return (start: start, end: end);
  }

  /// El primer renglón de `[start, end)` de [text] que se ve, en coordenadas
  /// globales; `null` si su parte no se ve —una sección plegada, una
  /// pregunta en el formato de lectura— o todavía no se dibujó.
  Rect? lineOf(ReportText text, int start, int end) {
    final part = text.firstPartOf(start, end);
    if (part == null) return null;
    final clipped = ReportText.clip(part, start, end);
    final state = _built[part.place];
    if (clipped == null || state == null || !state.mounted) return null;
    return firstLineOf(state.paragraph, clipped.$1, clipped.$2);
  }
}

/// Una parte del texto de un informe (F45, paso 8c): [inlines] con su estilo
/// sobre [style], como `ReportRichText`, y además, dentro de un informe con
/// notas ([ReportNotes]), lo que hace falta para llevarlas:
///
/// - le cuenta a la selección del informe qué tiene elegido;
/// - el pedazo de cada nota que la toca, con el subrayado fino punteado de su
///   color, y tocarlo la abre;
/// - el de la nota a la que se fue, con el fondo de resaltar un momento.
///
/// [place] dice qué parte es. Si el informe no la tiene con estas mismas
/// letras —un título de sección vacío, que se ve como «Sección 3»—, se
/// dibuja como siempre.
class ReportPartText extends StatefulWidget {
  const ReportPartText({
    required this.place,
    required this.inlines,
    required this.style,
    required this.typography,
    this.textAlign,
    this.textKey,
    super.key,
  });

  /// Una parte sin estilos adentro: un término, una opción, un título.
  ReportPartText.plain({
    required ReportTextPlace place,
    required String text,
    required TextStyle style,
    required ReportTypography typography,
    TextAlign? textAlign,
    Key? textKey,
    Key? key,
  }) : this(
         place: place,
         inlines: [ReportInline(text)],
         style: style,
         typography: typography,
         textAlign: textAlign,
         textKey: textKey,
         key: key,
       );

  final ReportTextPlace place;
  final List<ReportInline> inlines;
  final TextStyle style;
  final ReportTypography typography;
  final TextAlign? textAlign;

  /// La clave del texto que se dibuja.
  final Key? textKey;

  @override
  State<ReportPartText> createState() => _ReportPartTextState();
}

class _ReportPartTextState extends State<ReportPartText> {
  final _text = GlobalKey();
  final _selection = SelectionListenerNotifier();
  ReportNoteParts? _parts;
  ReportTextPlace? _registered;

  /// El párrafo que se dibuja: dentro de una `SelectionArea`, el `Text` lo
  /// envuelve con lo suyo, así que se lo busca adentro.
  RenderParagraph? get paragraph {
    RenderParagraph? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderParagraph) {
        found = object;
      } else {
        object.visitChildren(visit);
      }
    }

    final root = _text.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  /// Lo elegido en esta parte, contado desde su comienzo.
  ({int start, int end})? get selectedRange {
    if (!_selection.registered) return null;
    final details = _selection.selection;
    final range = details.range;
    if (details.status != SelectionStatus.uncollapsed || range == null) {
      return null;
    }
    final start = math.min(range.startOffset, range.endOffset);
    final end = math.max(range.startOffset, range.endOffset);
    return end > start ? (start: start, end: end) : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register(ReportNotes.maybeOf(context)?.parts);
  }

  @override
  void didUpdateWidget(ReportPartText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place != widget.place) _register(_parts, force: true);
  }

  void _register(ReportNoteParts? parts, {bool force = false}) {
    if (!force && identical(parts, _parts)) return;
    final registered = _registered;
    if (registered != null) _parts?._remove(registered, this);
    _parts = parts;
    _registered = parts == null ? null : widget.place;
    parts?._add(widget.place, this);
  }

  @override
  void dispose() {
    final registered = _registered;
    if (registered != null) _parts?._remove(registered, this);
    _selection.dispose();
    _dropRecognizers();
    super.dispose();
  }

  /// Los toques de los pedazos con nota del último cuadro.
  List<TapGestureRecognizer> _recognizers = const [];

  void _dropRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers = const [];
  }

  @override
  Widget build(BuildContext context) {
    _dropRecognizers();
    final scope = ReportNotes.maybeOf(context);
    final part = scope?.text.partAt(widget.place);
    final text = reportInlinesText(widget.inlines);
    if (scope == null || part == null || part.text != text) {
      return Text.rich(
        TextSpan(style: widget.style, children: _spans(context, const [])),
        key: widget.textKey,
        textAlign: widget.textAlign,
      );
    }

    // Lo de las notas que cae en esta parte, contado desde su comienzo.
    final marks = [
      for (final placed in scope.notes)
        if (ReportText.clip(part, placed.start!, placed.end!) case (
          final s,
          final e,
        ))
          (start: s, end: e, note: placed.note),
    ];
    final flash = switch (scope.flash) {
      (final start, final end) => ReportText.clip(part, start, end),
      null => null,
    };

    return KeyedSubtree(
      key: widget.textKey,
      child: SelectionListener(
        selectionNotifier: _selection,
        child: Text.rich(
          TextSpan(
            style: widget.style,
            children: _spans(context, marks, flash: flash, open: scope.onOpen),
          ),
          key: _text,
          textAlign: widget.textAlign,
        ),
      ),
    );
  }

  /// Los pedazos con su estilo —el de cada uno, el punteado de las notas que
  /// lo tocan y el fondo de la nota a la que se fue—, partidos donde empieza
  /// o termina cualquiera de ellos.
  ///
  /// Tocar un pedazo con nota la abre ([open]): el toque es del pedazo y no de
  /// la parte entera, así que lo demás sigue siendo de lo que la envuelve
  /// —una opción que se elige, un título que pliega su sección—.
  List<InlineSpan> _spans(
    BuildContext context,
    List<({int start, int end, TextNote note})> marks, {
    (int, int)? flash,
    ValueChanged<List<TextNote>>? open,
  }) {
    final typography = widget.typography;
    final flashColor = Theme.of(context).colorScheme.tertiaryContainer;
    final recognizers = <TapGestureRecognizer>[];
    final spans = <InlineSpan>[];
    var at = 0;
    for (final inline in widget.inlines) {
      final from = at;
      final to = at + inline.text.length;
      at = to;
      final cuts = <int>{from, to};
      for (final mark in marks) {
        if (mark.start > from && mark.start < to) cuts.add(mark.start);
        if (mark.end > from && mark.end < to) cuts.add(mark.end);
      }
      if (flash != null) {
        if (flash.$1 > from && flash.$1 < to) cuts.add(flash.$1);
        if (flash.$2 > from && flash.$2 < to) cuts.add(flash.$2);
      }
      final sorted = cuts.toList()..sort();
      final base = typography.styleOf(inline, widget.style);
      for (var i = 0; i + 1 < sorted.length; i++) {
        final start = sorted[i];
        final end = sorted[i + 1];
        var style = base;
        final noted = <TextNote>[];
        for (final mark in marks) {
          if (mark.start <= start && end <= mark.end) {
            noted.add(mark.note);
            style = style.copyWith(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: textNoteLine(context, mark.note.color),
              decorationThickness: 2,
            );
          }
        }
        if (flash != null && flash.$1 <= start && end <= flash.$2) {
          style = style.copyWith(backgroundColor: flashColor);
        }
        TapGestureRecognizer? recognizer;
        if (noted.isNotEmpty && open != null) {
          recognizer = TapGestureRecognizer()..onTap = () => open(noted);
          recognizers.add(recognizer);
        }
        spans.add(
          TextSpan(
            text: inline.text.substring(start - from, end - from),
            style: style,
            recognizer: recognizer,
          ),
        );
      }
    }
    _recognizers = recognizers;
    return spans;
  }
}

/// El renglón de la nota a la que se fue, marcado [duration] y después
/// apagado: lo que hace tocar una nota en «Notas (N)».
class ReportNoteFlash {
  ReportNoteFlash(this._onChanged);

  final VoidCallback _onChanged;
  Timer? _timer;

  /// `[start, end)` del texto, o `null`.
  (int, int)? get range => _range;
  (int, int)? _range;

  static const duration = Duration(seconds: 2);

  void show(int start, int end) {
    _timer?.cancel();
    _range = (start, end);
    _onChanged();
    _timer = Timer(duration, () {
      _range = null;
      _onChanged();
    });
  }

  void dispose() => _timer?.cancel();
}
