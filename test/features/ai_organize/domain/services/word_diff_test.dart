import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_organize/domain/services/word_diff.dart';

/// El antes y el después de una corrección, palabra por palabra (F33).
void main() {
  const same = DiffKind.same;
  const removed = DiffKind.removed;
  const added = DiffKind.added;

  String joined(List<DiffSegment> segments) =>
      segments.map((s) => s.text).join();

  test('marca lo que se va y lo que llega, y deja igual lo demás', () {
    final diff = wordDiff(
      'Lo escribió Lope de Vega.',
      'Lo escribió Cervantes.',
    );

    expect(diff.before, const [
      DiffSegment(same, 'Lo escribió '),
      DiffSegment(removed, 'Lope de Vega.'),
    ]);
    expect(diff.after, const [
      DiffSegment(same, 'Lo escribió '),
      DiffSegment(added, 'Cervantes.'),
    ]);
  });

  test('un cambio en el medio deja iguales los dos lados', () {
    final diff = wordDiff(
      'Roma cayó en 1453 según el texto',
      'Roma cayó en 476 según el texto',
    );

    expect(diff.before, const [
      DiffSegment(same, 'Roma cayó en '),
      DiffSegment(removed, '1453 '),
      DiffSegment(same, 'según el texto'),
    ]);
    expect(diff.after, const [
      DiffSegment(same, 'Roma cayó en '),
      DiffSegment(added, '476 '),
      DiffSegment(same, 'según el texto'),
    ]);
  });

  test('pegar los pedazos devuelve cada texto tal cual, con sus espacios', () {
    const before = '  Una   respuesta\ncon saltos ';
    const after = 'Una respuesta distinta\ncon saltos';

    final diff = wordDiff(before, after);

    expect(joined(diff.before), before);
    expect(joined(diff.after), after);
  });

  test('no distingue mayúsculas al buscar lo común', () {
    final diff = wordDiff('el senado romano', 'El Senado romano y griego');

    expect(diff.before, const [DiffSegment(same, 'el senado romano')]);
    expect(diff.after, const [
      DiffSegment(same, 'El Senado romano '),
      DiffSegment(added, 'y griego'),
    ]);
  });

  test('sin nada en común, todo se va y todo llega', () {
    final diff = wordDiff('uno dos', 'tres cuatro');

    expect(diff.before, const [DiffSegment(removed, 'uno dos')]);
    expect(diff.after, const [DiffSegment(added, 'tres cuatro')]);
  });

  test('un texto vacío no deja pedazos', () {
    expect(wordDiff('', 'algo').before, isEmpty);
    expect(wordDiff('algo', '').after, isEmpty);
  });

  test('un texto enorme no se compara palabra por palabra', () {
    final huge = List.filled(600, 'palabra').join(' ');
    // Casi igual: si se comparara, quedaría casi todo como está.
    final other = [...List.filled(599, 'palabra'), 'otra'].join(' ');

    final diff = wordDiff(huge, other);

    expect(diff.before, [DiffSegment(removed, huge)]);
    expect(diff.after, [DiffSegment(added, other)]);
  });
}
