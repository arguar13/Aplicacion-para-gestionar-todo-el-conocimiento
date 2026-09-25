import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_response_parser.dart';

void main() {
  test('una afirmación con su cita', () {
    const raw = 'A: Roma fue fundada por Rómulo\nC: Rómulo fundó la ciudad';

    final sections = parseDerivedNoteResponse(raw);

    expect(sections, hasLength(1));
    expect(sections.single.heading, isNull);
    expect(sections.single.claims, hasLength(1));
    expect(sections.single.claims.single.text, 'Roma fue fundada por Rómulo');
    expect(sections.single.claims.single.quote, 'Rómulo fundó la ciudad');
  });

  test('una afirmación sin cita se descarta cuando se ancla, pero acá se '
      'parsea igual', () {
    final sections = parseDerivedNoteResponse('A: una afirmación sin cita');

    expect(sections.single.claims.single.quote, isNull);
  });

  test('un título agrupa las afirmaciones que le siguen', () {
    const raw = '''
T: Fundación de Roma
A: Roma fue fundada por Rómulo
C: Rómulo fundó la ciudad
A: El año fue el 753 a. C.
C: en el 753 a. C.
''';

    final sections = parseDerivedNoteResponse(raw);

    expect(sections, hasLength(1));
    expect(sections.single.heading, 'Fundación de Roma');
    expect(sections.single.claims, hasLength(2));
  });

  test('un segundo título abre una sección nueva', () {
    const raw = '''
T: Uno
A: primera
C: cita uno
T: Dos
A: segunda
C: cita dos
''';

    final sections = parseDerivedNoteResponse(raw);

    expect(sections, hasLength(2));
    expect(sections[0].heading, 'Uno');
    expect(sections[1].heading, 'Dos');
  });

  test('afirmaciones sin ningún título quedan en una sola sección sin '
      'título', () {
    const raw = '''
A: primera
C: cita uno
A: segunda
C: cita dos
''';

    final sections = parseDerivedNoteResponse(raw);

    expect(sections, hasLength(1));
    expect(sections.single.heading, isNull);
    expect(sections.single.claims, hasLength(2));
  });

  test('un título sin ninguna afirmación no genera una sección', () {
    const raw = 'T: título huérfano\nT: otro título';

    expect(parseDerivedNoteResponse(raw), isEmpty);
  });

  test('una C: suelta, antes de cualquier afirmación, se ignora', () {
    final sections = parseDerivedNoteResponse('C: cita sin afirmación');

    expect(sections, isEmpty);
  });

  test('una segunda C: para la misma afirmación no pisa la primera', () {
    const raw = 'A: afirmación\nC: la primera\nC: la segunda';

    expect(
      parseDerivedNoteResponse(raw).single.claims.single.quote,
      'la primera',
    );
  });

  test('no distingue mayúsculas en los prefijos', () {
    final sections = parseDerivedNoteResponse(
      't: título\na: afirmación\nc: cita',
    );

    expect(sections.single.heading, 'título');
    expect(sections.single.claims.single.text, 'afirmación');
    expect(sections.single.claims.single.quote, 'cita');
  });

  test('recorta espacios de los bordes', () {
    final sections = parseDerivedNoteResponse('A:   afirmación  \nC:   cita  ');

    expect(sections.single.claims.single.text, 'afirmación');
    expect(sections.single.claims.single.quote, 'cita');
  });

  test('una afirmación o título en blanco se descarta', () {
    final sections = parseDerivedNoteResponse('T:   \nA:   \nC: cita');

    expect(sections, isEmpty);
  });

  test(
    'ignora en silencio las líneas que no matchean, sin romper el resto',
    () {
      const raw = '''
Una introducción que el modelo no debería poner.
A: afirmación válida
C: cita válida
Un cierre fuera de formato.
''';

      final sections = parseDerivedNoteResponse(raw);

      expect(sections.single.claims.single.text, 'afirmación válida');
    },
  );

  test('una entrada vacía no devuelve nada', () {
    expect(parseDerivedNoteResponse(''), isEmpty);
  });

  test('una entrada sin ningún formato reconocible no devuelve nada', () {
    expect(parseDerivedNoteResponse('esto no tiene ningún formato'), isEmpty);
  });
}
