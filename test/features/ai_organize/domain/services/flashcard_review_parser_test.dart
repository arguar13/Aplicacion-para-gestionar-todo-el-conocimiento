import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_organize/domain/services/flashcard_review_parser.dart';
import 'package:sinapsis/features/ai_organize/domain/services/flashcard_reviewer.dart';

/// Cómo se lee lo que contesta el revisor de tarjetas (F33): lo que no se
/// entiende no se propone.
void main() {
  const originals = [
    (front: '¿Qué es la entropía?', back: 'Una medida del desorden.'),
    (front: '¿Quién escribió el Quijote?', back: 'Lope de Vega.'),
    (front: '¿Cuándo cayó Roma?', back: 'En 476.'),
  ];

  List<FlashcardVerdict> parse(String raw) =>
      parseFlashcardReview(raw, originals: originals);

  test('lee una corrección, una que se saca y una que está bien', () {
    final verdicts = parse('''
TARJETA 1: bien
TARJETA 2: corregir
P: ¿Quién escribió el Quijote?
R: Miguel de Cervantes.
POR QUÉ: El pasaje dice Cervantes, no Lope de Vega.
TARJETA 3: sacar
POR QUÉ: El pasaje no habla de Roma.
''');

    expect(verdicts, const [
      FlashcardCorrection(
        index: 1,
        reason: 'El pasaje dice Cervantes, no Lope de Vega.',
        front: '¿Quién escribió el Quijote?',
        back: 'Miguel de Cervantes.',
      ),
      FlashcardRemoval(index: 2, reason: 'El pasaje no habla de Roma.'),
    ]);
  });

  test('tolera negritas, viñetas, mayúsculas, guiones y «por que» sin '
      'tilde', () {
    final verdicts = parse('''
Revisé las tarjetas:

**TARJETA 2 – Corregir**
- p: ¿Quién escribió el Quijote?
- r: Cervantes.
* Por que: Era Cervantes.
''');

    expect(verdicts, const [
      FlashcardCorrection(
        index: 1,
        reason: 'Era Cervantes.',
        front: '¿Quién escribió el Quijote?',
        back: 'Cervantes.',
      ),
    ]);
  });

  test('«MOTIVO:» también vale como el porqué', () {
    expect(parse('TARJETA 3: sacar\nMOTIVO: No está en el texto.'), const [
      FlashcardRemoval(index: 2, reason: 'No está en el texto.'),
    ]);
  });

  test('sin el porqué no se propone nada', () {
    expect(parse('TARJETA 3: sacar\nTARJETA 1: bien'), isEmpty);
    expect(parse('TARJETA 2: corregir\nP: ¿Quién?\nR: Cervantes.'), isEmpty);
  });

  test('una corrección sin pregunta o sin respuesta se descarta', () {
    expect(parse('TARJETA 2: corregir\nR: Cervantes.\nPOR QUÉ: x'), isEmpty);
    expect(parse('TARJETA 2: corregir\nP: ¿Quién?\nPOR QUÉ: x'), isEmpty);
  });

  test('una «corrección» que deja la tarjeta igual no es una corrección', () {
    expect(
      parse('''
TARJETA 1: corregir
P:  ¿qué es la entropía?
R: Una medida   del desorden.
POR QUÉ: Está bien.
'''),
      isEmpty,
    );
  });

  test('cambiar solo la respuesta, o solo la pregunta, sí es una '
      'corrección', () {
    final verdicts = parse('''
TARJETA 3: corregir
P: ¿En qué año cayó el Imperio romano de Occidente?
R: En 476.
POR QUÉ: La pregunta no decía cuál Roma.
''');

    expect(verdicts.single, isA<FlashcardCorrection>());
  });

  test('un número fuera de la lista se ignora', () {
    expect(
      parse('TARJETA 0: sacar\nPOR QUÉ: x\nTARJETA 4: sacar\nPOR QUÉ: y'),
      isEmpty,
    );
  });

  test('si una tarjeta aparece dos veces, vale la primera', () {
    final verdicts = parse('''
TARJETA 3: sacar
POR QUÉ: Primera.
TARJETA 3: corregir
P: ¿Cuándo?
R: 476.
POR QUÉ: Segunda.
''');

    expect(verdicts, const [FlashcardRemoval(index: 2, reason: 'Primera.')]);
  });

  test('las líneas de una tarjeta que está bien no se le pegan a otra', () {
    final verdicts = parse('''
TARJETA 3: sacar
TARJETA 1: bien
POR QUÉ: Esta línea es de la 1, que está bien.
''');

    expect(verdicts, isEmpty);
  });

  test('una respuesta vacía o sin formato no propone nada', () {
    expect(parse(''), isEmpty);
    expect(parse('Todas las tarjetas están bien.'), isEmpty);
  });

  group('el pasaje de cada tarjeta', () {
    final text = List.generate(200, (i) => 'palabra$i').join(' ');

    test('un texto corto va entero', () {
      expect(
        passageForReview('  Corto.  ', start: 0, end: 3, chars: 400),
        'Corto.',
      );
    });

    test('pone la cita en el medio, sin partir palabras', () {
      final start = text.indexOf('palabra100');
      final passage = passageForReview(
        text,
        start: start,
        end: start + 'palabra100'.length,
        chars: 200,
      );

      expect(passage, contains('palabra100'));
      expect(passage, startsWith('…palabra'));
      expect(passage, endsWith('…'));
      expect(passage.length, lessThanOrEqualTo(202));
      expect(passage.length, greaterThan(150));
    });

    test('cerca del principio usa lo que sobra del otro lado', () {
      final passage = passageForReview(text, start: 0, end: 8, chars: 200);

      expect(passage, startsWith('palabra0 '));
      expect(passage.length, greaterThan(180));
    });

    test('cerca del final, lo mismo', () {
      final passage = passageForReview(
        text,
        start: text.length - 5,
        end: text.length,
        chars: 200,
      );

      expect(passage, endsWith('palabra199'));
      expect(passage.length, greaterThan(180));
    });

    test('sin lugar en el texto, el principio', () {
      final passage = passageForReview(
        text,
        start: null,
        end: null,
        chars: 120,
      );

      expect(passage, startsWith('palabra0 palabra1'));
      expect(passage, endsWith('…'));
    });
  });
}
