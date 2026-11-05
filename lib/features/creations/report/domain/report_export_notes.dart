import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_canonical_text.dart';
import 'package:sinapsis/features/creations/report/domain/report_markup.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/services/text_note_placement.dart';

/// Una nota sobre un pedazo de un informe, para lo que se descarga (F45, paso
/// 8c): la parte donde termina su pedazo ([place]), dónde termina dentro de
/// ella ([at], contado desde su comienzo) —ahí va su llamada— y lo que dice
/// ([note]).
@immutable
class ReportPieceNote {
  const ReportPieceNote({
    required this.place,
    required this.at,
    required this.note,
  });

  final ReportTextPlace place;
  final int at;
  final String note;
}

/// Las notas de un informe en lo que se descarga (F45, paso 8c), en el PDF y
/// en el Markdown:
///
/// - **al comienzo**, después del título, un bloque con su título ([title],
///   «Notas del informe») y las notas sobre el informe entero ([whole]);
/// - **en el texto**, la llamada de cada nota sobre un pedazo ([pieces]) —su
///   número volado— justo después del pedazo, y lo que dice al final, como
///   una nota al pie, con [piecesTitle] arriba en el PDF.
@immutable
class ReportExportNotes {
  const ReportExportNotes({
    this.title = '',
    this.piecesTitle = '',
    this.whole = const [],
    this.pieces = const [],
  });

  /// Sin ninguna.
  static const none = ReportExportNotes();

  final String title;
  final String piecesTitle;

  /// Lo que dicen las notas del comienzo, en el orden en que se escribieron.
  final List<String> whole;

  /// Las notas sobre pedazos, en el orden del texto.
  final List<ReportPieceNote> pieces;

  bool get isEmpty => whole.isEmpty && pieces.isEmpty;
}

/// Las notas de un informe para descargarlo (F45, paso 8c): [notes] —las de
/// la creación— ubicadas en el texto de [report] (`ReportText`, con
/// `placeTextNotes`).
///
/// - Las del informe entero van al comienzo, en el orden en que se
///   escribieron.
/// - Las de un pedazo, a su lugar. La de una pregunta o una opción en el
///   formato de lectura —que no las lleva— no tiene dónde ir en el texto:
///   va al comienzo con el pedazo que cita, «…» — y lo que dice.
/// - La que quedó sin lugar —su pedazo ya no está en el informe— se deja
///   afuera, como en la descarga de un documento; sigue en la app.
ReportExportNotes reportExportNotes({
  required Report report,
  required List<TextNote> notes,
  required bool interactive,
  required String title,
  required String piecesTitle,
}) {
  if (notes.isEmpty) return ReportExportNotes.none;
  final text = ReportText.of(report);
  final whole = [
    for (final note in notes)
      if (note.wholeText) note,
  ]..sort(compareInTextOrder);
  final opening = [for (final note in whole) note.note];
  final pieces = <ReportPieceNote>[];
  for (final placed in placeTextNotes(notes, content: text.content)) {
    if (!placed.placed) continue;
    // La llamada va después de la última letra del pedazo.
    final part = text.partContaining(placed.end! - 1);
    if (part == null) continue;
    if (part.place.interactiveOnly && !interactive) {
      opening.add('«${placed.note.excerpt}» — ${placed.note.note}');
      continue;
    }
    pieces.add(
      ReportPieceNote(
        place: part.place,
        at: placed.end! - part.start,
        note: placed.note.note,
      ),
    );
  }
  if (opening.isEmpty && pieces.isEmpty) return ReportExportNotes.none;
  return ReportExportNotes(
    title: title,
    piecesTitle: piecesTitle,
    whole: opening,
    pieces: pieces,
  );
}

/// Una llamada a una nota: dónde va dentro de su parte (`at`) y su número.
typedef ReportNoteCall = ({int at, int number});

/// Los números de las llamadas de unas notas, en el orden en que se escriben
/// (F45, paso 8c): quien escribe el informe pide las de cada parte cuando
/// la escribe ([callsAt]), y cada nota toma el número que sigue; al final,
/// [written] tiene lo que dice cada una en ese orden, para las notas al pie.
class ReportNoteCalls {
  ReportNoteCalls(ReportExportNotes notes) {
    for (final piece in notes.pieces) {
      (_byPlace[piece.place] ??= []).add(piece);
    }
  }

  final _byPlace = <ReportTextPlace, List<ReportPieceNote>>{};
  final _numbers = <ReportPieceNote, int>{};

  /// Lo que dice cada nota, en el orden de sus números.
  final written = <String>[];

  /// Las llamadas de la parte [place], de la primera a la última; una nota
  /// que ya tenía número lo conserva.
  List<ReportNoteCall> callsAt(ReportTextPlace place) {
    final pieces = [...?_byPlace[place]]..sort((a, b) => a.at.compareTo(b.at));
    return [
      for (final piece in pieces)
        (at: piece.at, number: _numbers[piece] ??= _next(piece)),
    ];
  }

  int _next(ReportPieceNote piece) {
    written.add(piece.note);
    return written.length;
  }
}

/// [inlines] partidos donde va cada una de [calls] —contadas desde su
/// comienzo—: pedazos de texto ([ReportInline]) y, entre ellos, los números
/// de las llamadas (`int`). Una llamada después del final va al final.
List<Object> reportInlinesWithCalls(
  List<ReportInline> inlines,
  List<ReportNoteCall> calls,
) {
  if (calls.isEmpty) return inlines;
  final out = <Object>[];
  var pending = 0;
  var at = 0;
  for (final inline in inlines) {
    final end = at + inline.text.length;
    var cut = 0;
    while (pending < calls.length && calls[pending].at <= end) {
      final local = calls[pending].at - at;
      if (local > cut) {
        out.add(inline.copyWith(text: inline.text.substring(cut, local)));
        cut = local;
      }
      out.add(calls[pending].number);
      pending++;
    }
    if (cut < inline.text.length) {
      out.add(inline.copyWith(text: inline.text.substring(cut)));
    }
    at = end;
  }
  for (; pending < calls.length; pending++) {
    out.add(calls[pending].number);
  }
  return out;
}
