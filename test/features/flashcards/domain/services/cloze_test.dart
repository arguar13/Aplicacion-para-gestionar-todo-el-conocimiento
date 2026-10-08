import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';

void main() {
  group('parseCloze: un hueco', () {
    test('saca la pregunta y la respuesta del ejemplo del plan', () {
      final cloze = parseCloze('El {{c1::Imperio romano}} cayó en 476');

      expect(cloze.isValid, isTrue);
      expect(cloze.numbers, [1]);
      expect(cloze.questionFor(1), 'El [...] cayó en 476');
      expect(cloze.answerFor(1), 'El **Imperio romano** cayó en 476');
      expect(cloze.plainText, 'El Imperio romano cayó en 476');
    });

    test('con pista, el frente muestra la pista y no los puntos', () {
      final cloze = parseCloze(
        'La capital de Francia es {{c1::París::ciudad}}.',
      );

      expect(cloze.questionFor(1), 'La capital de Francia es [ciudad].');
      expect(cloze.answerFor(1), 'La capital de Francia es **París**.');
      expect(cloze.deletions.single.hint, 'ciudad');
    });

    test('una pista en blanco es como no tener pista', () {
      final cloze = parseCloze('A {{c1::b::   }} c');

      expect(cloze.deletions.single.hint, isNull);
      expect(cloze.questionFor(1), 'A [...] c');
    });

    test('la posición del hueco devuelve el hueco entero', () {
      const text = 'antes {{c1::medio::p}} después';
      final d = parseCloze(text).deletions.single;

      expect(text.substring(d.start, d.end), '{{c1::medio::p}}');
    });
  });

  group('parseCloze: varios huecos', () {
    test('cada número es una tarjeta y los demás huecos van revelados', () {
      final cloze = parseCloze(
        '{{c1::Roma}} fue fundada en {{c2::753 a. C.}} '
        'según {{c3::Tito Livio}}',
      );

      expect(cloze.numbers, [1, 2, 3]);
      expect(
        cloze.questionFor(1),
        '[...] fue fundada en 753 a. C. según Tito Livio',
      );
      expect(
        cloze.questionFor(2),
        'Roma fue fundada en [...] según Tito Livio',
      );
      expect(
        cloze.answerFor(3),
        'Roma fue fundada en 753 a. C. según **Tito Livio**',
      );
      expect(cloze.cards, hasLength(3));
      expect(cloze.cards.map((c) => c.number), [1, 2, 3]);
    });

    test('varios huecos con el mismo número se piden juntos', () {
      final cloze = parseCloze(
        '{{c1::Madrid}} es la capital de {{c1::España}} y {{c2::Lisboa}} de '
        'Portugal',
      );

      expect(cloze.numbers, [1, 2]);
      expect(
        cloze.questionFor(1),
        '[...] es la capital de [...] y Lisboa de Portugal',
      );
      expect(
        cloze.answerFor(1),
        '**Madrid** es la capital de **España** y Lisboa de Portugal',
      );
      expect(cloze.cards, hasLength(2));
    });

    test('los números salen ordenados aunque aparezcan desordenados', () {
      final cloze = parseCloze('{{c3::c}} {{c1::a}} {{c2::b}} {{c1::a2}}');

      expect(cloze.numbers, [1, 2, 3]);
    });

    test('los segmentos distinguen texto, hueco oculto y hueco revelado', () {
      final cloze = parseCloze('a {{c1::b}} c {{c2::d}}');

      expect(cloze.questionSegmentsFor(1), const [
        ClozeSegment('a ', ClozeSegmentKind.plain),
        ClozeSegment('[...]', ClozeSegmentKind.hidden),
        ClozeSegment(' c d', ClozeSegmentKind.plain),
      ]);
      expect(cloze.answerSegmentsFor(2), const [
        ClozeSegment('a b c ', ClozeSegmentKind.plain),
        ClozeSegment('d', ClozeSegmentKind.revealed),
      ]);
    });

    test('un hueco al principio o al final no deja segmentos vacíos', () {
      final cloze = parseCloze('{{c1::todo}}');

      expect(cloze.questionSegmentsFor(1), const [
        ClozeSegment('[...]', ClozeSegmentKind.hidden),
      ]);
    });
  });

  group('parseCloze: formas raras', () {
    test('Unicode: acentos, ñ y emoji no se parten', () {
      final cloze = parseCloze(
        'El niño 🧒🏽 comió {{c1::piña 🍍}} con {{c2::ñoquis}}',
      );

      expect(cloze.questionFor(1), 'El niño 🧒🏽 comió [...] con ñoquis');
      expect(cloze.answerFor(2), 'El niño 🧒🏽 comió piña 🍍 con **ñoquis**');
      expect(cloze.deletions.first.answer, 'piña 🍍');
    });

    test('una llave simple dentro de la respuesta se conserva', () {
      final cloze = parseCloze('Vale {{c1::f(x) = {a}}} siempre');

      expect(cloze.problems, isEmpty);
      expect(cloze.deletions.single.answer, 'f(x) = {a}');
      expect(cloze.questionFor(1), 'Vale [...] siempre');
    });

    test('llaves sueltas fuera de un hueco son texto común', () {
      final cloze = parseCloze('Un conjunto {1, 2} y }} sueltas {{c1::ok}} {');

      expect(cloze.problems, isEmpty);
      expect(cloze.questionFor(1), 'Un conjunto {1, 2} y }} sueltas [...] {');
    });

    test('un hueco anidado no genera tarjeta propia y queda revelado', () {
      final cloze = parseCloze('{{c1::el {{c2::Imperio}} romano}} cayó');

      expect(cloze.numbers, [1]);
      expect(cloze.deletions.single.answer, 'el Imperio romano');
      expect(cloze.questionFor(1), '[...] cayó');
    });

    test('un "::" después de la pista queda en la pista', () {
      final cloze = parseCloze('{{c1::a::b::c}}');

      expect(cloze.deletions.single.answer, 'a');
      expect(cloze.deletions.single.hint, 'b::c');
    });

    test(
      'un texto de un millón de caracteres se lee en un tiempo razonable',
      () {
        final text = '${'palabra ' * 125000}{{c1::final}} ${'x' * 1000}';
        final watch = Stopwatch()..start();
        final cloze = parseCloze(text);
        watch.stop();

        expect(cloze.numbers, [1]);
        expect(cloze.questionFor(1).endsWith('[...] ${'x' * 1000}'), isTrue);
        expect(watch.elapsedMilliseconds, lessThan(2000));
      },
    );

    test('muchos huecos seguidos no rompen', () {
      final text = List.generate(2000, (i) => '{{c${i + 1}::p$i}}').join(' ');
      final cloze = parseCloze(text);

      expect(cloze.numbers, hasLength(2000));
      expect(cloze.questionFor(2000).endsWith('[...]'), isTrue);
    });
  });

  group('validateCloze', () {
    test('un texto sin huecos es un error claro', () {
      expect(validateCloze('Sin ningún hueco'), [ClozeProblem.noDeletions]);
      expect(validateCloze(''), [ClozeProblem.noDeletions]);
      expect(
        clozeProblemMessage(ClozeProblem.noDeletions),
        contains('ningún hueco'),
      );
    });

    test('un hueco que no se cierra', () {
      expect(
        validateCloze('Hola {{c1::mundo'),
        contains(ClozeProblem.unclosed),
      );
      expect(
        validateCloze('Hola {{c1::mundo'),
        contains(ClozeProblem.noDeletions),
      );
    });

    test('un hueco roto junto a uno bueno avisa sin perder el bueno', () {
      final cloze = parseCloze('{{c1::bien}} y {{c2::mal');

      expect(cloze.problems, [ClozeProblem.unclosed]);
      expect(cloze.numbers, [1]);
      expect(cloze.isValid, isFalse);
      expect(validateCloze('{{c1::bien}} y {{c2::mal'), [
        ClozeProblem.unclosed,
      ]);
    });

    test('un hueco vacío', () {
      expect(validateCloze('a {{c1::}} b'), contains(ClozeProblem.emptyAnswer));
      expect(
        validateCloze('a {{c1::   }} b'),
        contains(ClozeProblem.emptyAnswer),
      );
    });

    test('el número cero y los gigantes no valen', () {
      expect(validateCloze('{{c0::a}}'), contains(ClozeProblem.invalidNumber));
      expect(
        validateCloze('{{c99999999999999999999999::a}}'),
        contains(ClozeProblem.invalidNumber),
      );
      expect(parseCloze('{{c9999::a}}').numbers, [9999]);
      expect(
        validateCloze('{{c10000::a}}'),
        contains(ClozeProblem.invalidNumber),
      );
    });

    test('lo que se parece a un hueco pero no lo es no avisa nada raro', () {
      // `{{cuando}}` y `{{c1:solo uno}}` no son encabezados de hueco.
      expect(validateCloze('{{cuando}} {{c1:x}}'), [ClozeProblem.noDeletions]);
    });

    test('un texto válido no tiene problemas', () {
      expect(validateCloze('a {{c1::b}} c'), isEmpty);
      expect(parseCloze('a {{c1::b}} c').isValid, isTrue);
    });

    test('todos los problemas tienen mensaje en español', () {
      for (final problem in ClozeProblem.values) {
        expect(clozeProblemMessage(problem), isNotEmpty);
      }
    });
  });

  group('wrapAsCloze y nextClozeNumber', () {
    test('envuelve la selección con el número y la pista', () {
      expect(
        wrapAsCloze('El Imperio cayó', 3, 10, number: 2, hint: 'sustantivo'),
        'El {{c2::Imperio::sustantivo}} cayó',
      );
      expect(
        wrapAsCloze('El Imperio cayó', 3, 10, number: 1),
        'El {{c1::Imperio}} cayó',
      );
    });

    test('una selección vacía o inválida no cambia nada', () {
      const text = 'abc';
      expect(wrapAsCloze(text, 1, 1, number: 1), text);
      expect(wrapAsCloze(text, 2, 1, number: 1), text);
      expect(wrapAsCloze(text, -1, 2, number: 1), text);
      expect(wrapAsCloze(text, 0, 9, number: 1), text);
      expect(wrapAsCloze('a  b', 1, 3, number: 1), 'a  b');
      expect(wrapAsCloze(text, 0, 1, number: 0), text);
    });

    test('el siguiente número', () {
      expect(nextClozeNumber('sin huecos'), 1);
      expect(nextClozeNumber('{{c1::a}} {{c4::b}}'), 5);
    });

    test('envolver y leer de nuevo es una vuelta completa', () {
      final wrapped = wrapAsCloze('Roma cayó en 476', 0, 4, number: 1);
      final cloze = parseCloze(wrapped);

      expect(cloze.questionFor(1), '[...] cayó en 476');
    });
  });

  group('la IA', () {
    test('el pedido lleva la cantidad y el contenido', () {
      final request = buildClozeRequest(content: 'Texto fuente', count: 3);

      expect(request, contains('hasta 3 frases'));
      expect(request, endsWith('Texto fuente'));
    });

    test('las instrucciones explican el formato exacto que se parsea', () {
      expect(clozeSystemInstruction, contains('{{c1::'));
      expect(clozeSystemInstruction, contains('H: '));
      expect(clozeSystemInstruction, contains('Respondé siempre en español'));
    });

    test('interpreta frases con su cita', () {
      final drafts = parseClozeDrafts('''
H: El {{c1::Imperio romano}} cayó en 476.
C: El Imperio romano cayó en 476.
H: La {{c1::fotosíntesis::proceso}} ocurre en los {{c2::cloroplastos}}.
''');

      expect(drafts, hasLength(2));
      expect(drafts[0].text, 'El {{c1::Imperio romano}} cayó en 476.');
      expect(drafts[0].quote, 'El Imperio romano cayó en 476.');
      expect(drafts[1].quote, isNull);
      expect(parseCloze(drafts[1].text).numbers, [1, 2]);
    });

    test(
      'descarta frases sin huecos o con huecos rotos, pero no las demás',
      () {
        final drafts = parseClozeDrafts('''
H: Una frase sin ningún hueco.
H: Un hueco {{c1::roto
H: Esta {{c1::sí}} sirve.
''');

        expect(drafts.map((d) => d.text), ['Esta {{c1::sí}} sirve.']);
      },
    );

    test('tolera viñetas, números y mayúsculas, y la línea sin etiqueta', () {
      final drafts = parseClozeDrafts('''
- h: Uno {{c1::a}}
2. H: Dos {{c1::b}}
Tres {{c1::c}} sin etiqueta
Charla del modelo: aquí van las frases
''');

      expect(drafts.map((d) => d.text), [
        'Uno {{c1::a}}',
        'Dos {{c1::b}}',
        'Tres {{c1::c}} sin etiqueta',
      ]);
    });

    test(
      'una cita suelta, sin frase antes o tras una descartada, se ignora',
      () {
        final drafts = parseClozeDrafts('''
C: cita huérfana
H: sin huecos
C: cita de una descartada
H: Con {{c1::hueco}}
C: la buena
C: una segunda cita
''');

        expect(drafts, hasLength(1));
        expect(drafts.single.quote, 'la buena');
      },
    );

    test('una respuesta vacía o sin nada útil da lista vacía', () {
      expect(parseClozeDrafts(''), isEmpty);
      expect(parseClozeDrafts('No puedo ayudarte con eso.'), isEmpty);
    });
  });
}
