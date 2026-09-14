import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_draft_parser.dart';

void main() {
  test('interpreta un par P/R simple', () {
    final drafts = parseFlashcardDrafts('P: ¿Qué es SM-2?\nR: Un algoritmo.');

    expect(drafts, hasLength(1));
    expect(drafts.single.front, '¿Qué es SM-2?');
    expect(drafts.single.back, 'Un algoritmo.');
  });

  test('interpreta varios pares seguidos', () {
    const raw = '''
P: Pregunta uno
R: Respuesta uno
P: Pregunta dos
R: Respuesta dos
''';

    final drafts = parseFlashcardDrafts(raw);

    expect(drafts, hasLength(2));
    expect(drafts[0].front, 'Pregunta uno');
    expect(drafts[0].back, 'Respuesta uno');
    expect(drafts[1].front, 'Pregunta dos');
    expect(drafts[1].back, 'Respuesta dos');
  });

  test('no distingue mayúsculas en los prefijos', () {
    final drafts = parseFlashcardDrafts('p: pregunta\nr: respuesta');

    expect(drafts, hasLength(1));
  });

  test(
    'ignora en silencio las líneas que no matchean, sin romper el resto',
    () {
      const raw = '''
Acá va una introducción que el modelo no debería poner.
P: Pregunta válida
R: Respuesta válida
Y un comentario final fuera de formato.
''';

      final drafts = parseFlashcardDrafts(raw);

      expect(drafts, hasLength(1));
      expect(drafts.single.front, 'Pregunta válida');
    },
  );

  test('una respuesta sin pregunta previa se descarta', () {
    final drafts = parseFlashcardDrafts('R: Respuesta huérfana');

    expect(drafts, isEmpty);
  });

  test('una pregunta sin respuesta nunca se agrega', () {
    final drafts = parseFlashcardDrafts('P: Pregunta sin respuesta');

    expect(drafts, isEmpty);
  });

  test('una pregunta repetida antes de su respuesta usa la última', () {
    const raw = '''
P: Primera versión
P: Segunda versión
R: Respuesta
''';

    final drafts = parseFlashcardDrafts(raw);

    expect(drafts, hasLength(1));
    expect(drafts.single.front, 'Segunda versión');
  });

  test('una pregunta o respuesta en blanco se descarta', () {
    final drafts = parseFlashcardDrafts('P:   \nR: algo');

    expect(drafts, isEmpty);
  });

  test('recorta espacios de los bordes', () {
    final drafts = parseFlashcardDrafts('P:   pregunta  \nR:   respuesta  ');

    expect(drafts.single.front, 'pregunta');
    expect(drafts.single.back, 'respuesta');
  });

  test('una entrada vacía no devuelve nada', () {
    expect(parseFlashcardDrafts(''), isEmpty);
  });

  test('una entrada sin ningún formato reconocible no devuelve nada', () {
    expect(parseFlashcardDrafts('esto no tiene ningún formato'), isEmpty);
  });
}
