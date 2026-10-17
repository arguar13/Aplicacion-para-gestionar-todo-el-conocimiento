import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/features/ai_organize/domain/services/things_review_parser.dart';
import 'package:sinapsis/features/ai_organize/domain/services/things_reviewer.dart';

/// Cómo se lee lo que contesta el revisor de «lo demás» (F33): lo que no se
/// entiende, o no cumple las reglas de cada cosa, no se propone.
void main() {
  const relation = ThingToReview(
    subject: CorrectionSubject.relation,
    name: 'vínculo con «Cortázar»',
    value: 'relacionado',
    note: 'El autor.',
    options: ['relacionado', 'continua', 'contradice', 'cita', 'resume'],
  );
  const tag = ThingToReview(
    subject: CorrectionSubject.property,
    name: 'etiqueta',
    value: 'Cuento',
    options: ['Cuento', 'Novela'],
  );
  const pages = ThingToReview(
    subject: CorrectionSubject.property,
    name: 'propiedad «Páginas»',
    value: '320',
    canFix: false,
  );
  const publisher = ThingToReview(
    subject: CorrectionSubject.reference,
    name: 'Editorial de la referencia',
    value: 'Planeta',
  );
  const intro = ThingToReview(
    subject: CorrectionSubject.mapIntro,
    name: 'introducción',
    value: 'Lo que la IA dice.',
    canRemove: false,
  );
  const things = [relation, tag, pages, publisher, intro];

  List<ThingVerdict> parse(String raw) =>
      parseThingsReview(raw, things: things);

  test('lee una corrección de cada clase y una que se saca', () {
    final verdicts = parse('''
DATO 1: corregir
TIPO: contradice
FRASE: Dicen lo contrario.
POR QUÉ: El texto lo discute.
DATO 2: corregir
VALOR: novela
POR QUÉ: Es una novela.
DATO 3: sacar
POR QUÉ: No dice cuántas páginas.
DATO 4: corregir
VALOR:   Sudamericana
POR QUÉ: La primera edición.
DATO 5: corregir
VALOR: Una **introducción** mejor
de verdad.
POR QUÉ: Dice más.
''');

    expect(verdicts, const [
      ThingCorrection(
        index: 0,
        reason: 'El texto lo discute.',
        value: 'contradice',
        note: 'Dicen lo contrario.',
      ),
      // Escrita como la opción.
      ThingCorrection(index: 1, reason: 'Es una novela.', value: 'Novela'),
      ThingRemoval(index: 2, reason: 'No dice cuántas páginas.'),
      ThingCorrection(
        index: 3,
        reason: 'La primera edición.',
        value: 'Sudamericana',
      ),
      // Limpia como la escribe la IA; la línea suelta no es parte del valor.
      ThingCorrection(
        index: 4,
        reason: 'Dice más.',
        value: 'Una introducción mejor',
      ),
    ]);
  });

  test('en un vínculo, lo que no dice queda como estaba', () {
    expect(
      parse('''
DATO 1: corregir
TIPO: cita
POR QUÉ: Lo cita.
'''),
      const [
        ThingCorrection(
          index: 0,
          reason: 'Lo cita.',
          value: 'cita',
          note: 'El autor.',
        ),
      ],
    );
    expect(
      parse('''
DATO 1: corregir
FRASE: Es su autor.
POR QUÉ: Más claro.
'''),
      const [
        ThingCorrection(
          index: 0,
          reason: 'Más claro.',
          value: 'relacionado',
          note: 'Es su autor.',
        ),
      ],
    );
  });

  test('un valor que no está entre las opciones, o un tipo que no existe, no '
      'se propone', () {
    expect(
      parse('''
DATO 1: corregir
TIPO: indexa
POR QUÉ: Es un índice.
DATO 2: corregir
VALOR: Poesía
POR QUÉ: Son poemas.
'''),
      isEmpty,
    );
  });

  test('no saca lo que no se saca ni corrige lo que no se corrige', () {
    expect(
      parse('''
DATO 3: corregir
VALOR: 310
POR QUÉ: Son 310.
DATO 5: sacar
POR QUÉ: Sobra.
'''),
      isEmpty,
    );
  });

  test('una corrección que deja todo igual no es una corrección', () {
    expect(
      parse('''
DATO 1: corregir
TIPO: Relacionado
FRASE:  el autor.
POR QUÉ: Igual.
DATO 2: corregir
VALOR: cuento
POR QUÉ: Igual.
DATO 4: corregir
VALOR: planeta
POR QUÉ: Igual.
DATO 5: corregir
VALOR: [[Lo que la IA dice.]]
POR QUÉ: Igual.
'''),
      isEmpty,
    );
  });

  test('sin porqué, sin valor, fuera de la lista o repetido, no se propone; '
      'vale el primero', () {
    expect(
      parse('''
DATO 2: corregir
VALOR: Novela
DATO 4: corregir
POR QUÉ: Falta el valor.
DATO 9: sacar
POR QUÉ: No existe.
DATO 0: sacar
POR QUÉ: Tampoco.
DATO 4: sacar
POR QUÉ: Primero.
DATO 4: corregir
VALOR: Otra
POR QUÉ: Segundo.
'''),
      const [ThingRemoval(index: 3, reason: 'Primero.')],
    );
  });

  test('tolera negritas, viñetas, mayúsculas y guiones', () {
    expect(
      parse('''
Revisé todo:

**DATO 2 – Corregir**
- valor: Novela
* Por que: Es una novela.
'''),
      const [
        ThingCorrection(index: 1, reason: 'Es una novela.', value: 'Novela'),
      ],
    );
  });

  test('lo que está bien no trae veredicto', () {
    expect(parse('DATO 1: bien\nDATO 2: bien\nPOR QUÉ: Está bien.'), isEmpty);
  });
}
