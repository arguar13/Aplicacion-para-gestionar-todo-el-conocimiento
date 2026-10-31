import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/domain/services/text_note_placement.dart';

/// Dónde cae cada nota en el texto que se muestra (F45, mejora 19): lo
/// guardado mientras siga siendo verdad, el pedazo citado si el texto cambió,
/// o sin lugar —nunca afuera—.
void main() {
  const text = 'Moisés sube al monte.\nBaja con las tablas de la ley.';
  const target = TextNoteTarget.sourceOriginal(
    sourceId: 'fuente',
    renditionId: 'rend',
  );

  TextNote note(
    String id,
    String excerpt, {
    int? start,
    int? end,
    String? renditionId = 'rend',
    int minute = 0,
  }) => TextNote(
    id: id,
    origin: TextNoteOrigin.note,
    target: target,
    start: start,
    end: end,
    excerpt: excerpt,
    note: 'nota $id',
    color: HighlightColor.lime,
    renditionId: renditionId,
    createdAt: DateTime(2026, 10, 30, 12, minute),
    updatedAt: DateTime(2026, 10, 30, 12, minute),
  );

  List<(String, int?, int?)> places(List<PlacedTextNote> placed) => [
    for (final p in placed) (p.note.id, p.start, p.end),
  ];

  test('lo guardado vale mientras en su lugar siga el pedazo', () {
    final start = text.indexOf('monte');
    final placed = placeTextNotes([
      note('a', 'monte', start: start, end: start + 5),
    ], content: text);

    expect(places(placed), [('a', start, start + 5)]);
    expect(placed.single.placed, isTrue);
  });

  test('si el texto cambió, el pedazo se busca —también cortado en '
      'renglones— cerca de donde estaba', () {
    const changed = 'Primero.\nMoisés sube al mon-\nte. Baja con las tablas.';
    final placed = placeTextNotes([
      note('a', 'al monte', start: 12, end: 20),
    ], content: changed);

    final [only] = placed;
    expect(only.placed, isTrue);
    expect(changed.substring(only.start!, only.end), 'al mon-\nte');
  });

  test('si el pedazo ya no está, queda sin lugar, y va al final', () {
    final start = text.indexOf('tablas');
    final placed = placeTextNotes([
      note('perdida', 'el becerro de oro', start: 0, end: 17),
      note('b', 'tablas', start: start, end: start + 6),
    ], content: text);

    expect(places(placed), [('b', start, start + 6), ('perdida', null, null)]);
    expect(placed.last.placed, isFalse);
  });

  test('una escrita sobre otra forma del original se ubica por su pedazo, '
      'no por sus posiciones', () {
    // En la otra forma, «sube» estaba en el 0; acá, el 0 es «Moisés».
    final placed = placeTextNotes([
      note('otra', 'sube', start: 0, end: 4, renditionId: 'otra-forma'),
    ], content: text);

    final [only] = placed;
    expect(text.substring(only.start!, only.end), 'sube');
  });

  test('si el pedazo está más de una vez, gana la aparición más cercana a '
      'donde estaba', () {
    // Era la segunda «ley», en 12; con dos letras de más adelante, está en 14.
    const changed = 'A la ley y la ley';
    final placed = placeTextNotes([
      note('segunda', 'ley', start: 12, end: 15),
    ], content: changed);

    expect(placed.single.start, 14);
  });

  test('una sin lugar guardado se busca igual, y vuelve si el pedazo está', () {
    final placed = placeTextNotes([note('vuelve', 'ley')], content: text);

    expect(text.substring(placed.single.start!, placed.single.end), 'ley');
  });

  test('en el orden del texto, y a igual lugar la más vieja primero', () {
    int at(String s) => text.indexOf(s);
    final placed = placeTextNotes([
      note('ley', 'ley', start: at('ley'), end: at('ley') + 3),
      note('nueva', 'Baja', start: at('Baja'), end: at('Baja') + 4, minute: 9),
      note('vieja', 'Baja', start: at('Baja'), end: at('Baja') + 4),
      note('monte', 'monte', start: at('monte'), end: at('monte') + 5),
    ], content: text);

    expect(
      [for (final p in placed) p.note.id],
      ['monte', 'vieja', 'nueva', 'ley'],
    );
  });
}
