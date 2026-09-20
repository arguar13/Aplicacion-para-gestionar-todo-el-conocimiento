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

  group('la cita de la fuente (F11)', () {
    test('una línea C: después de la respuesta es la cita de la tarjeta', () {
      const raw = '''
P: ¿Quién fundó Roma?
R: Rómulo.
C: Rómulo fundó la ciudad en el 753 a. C.
''';

      final drafts = parseFlashcardDrafts(raw);

      expect(drafts, hasLength(1));
      expect(drafts.single.front, '¿Quién fundó Roma?');
      expect(drafts.single.back, 'Rómulo.');
      expect(drafts.single.quote, 'Rómulo fundó la ciudad en el 753 a. C.');
    });

    test('sin la línea C: la tarjeta queda sin cita, no se pierde', () {
      final drafts = parseFlashcardDrafts('P: pregunta\nR: respuesta');

      expect(drafts.single.quote, isNull);
    });

    test(
      'cada cita va con su tarjeta, también cuando solo algunas la traen',
      () {
        const raw = '''
P: Uno
R: Respuesta uno
C: cita uno
P: Dos
R: Respuesta dos
P: Tres
R: Respuesta tres
C: cita tres
''';

        final drafts = parseFlashcardDrafts(raw);

        expect(drafts.map((d) => d.quote), ['cita uno', null, 'cita tres']);
      },
    );

    test('una C: suelta, antes de cualquier tarjeta, se ignora', () {
      final drafts = parseFlashcardDrafts('C: una cita sin tarjeta');

      expect(drafts, isEmpty);
    });

    test('una C: entre la pregunta y su respuesta no es la cita de nadie', () {
      const raw = '''
P: pregunta
C: cita fuera de lugar
R: respuesta
''';

      final drafts = parseFlashcardDrafts(raw);

      expect(drafts.single.front, 'pregunta');
      expect(drafts.single.back, 'respuesta');
      expect(drafts.single.quote, isNull);
    });

    test('una segunda C: para la misma tarjeta no pisa la primera', () {
      const raw = '''
P: pregunta
R: respuesta
C: la primera
C: la segunda
''';

      expect(parseFlashcardDrafts(raw).single.quote, 'la primera');
    });

    test('una cita en blanco no cuenta', () {
      expect(parseFlashcardDrafts('P: p\nR: r\nC:   ').single.quote, isNull);
    });

    test('no distingue mayúsculas en el prefijo', () {
      expect(
        parseFlashcardDrafts('p: p\nr: r\nc: la cita').single.quote,
        'la cita',
      );
    });
  });
}
