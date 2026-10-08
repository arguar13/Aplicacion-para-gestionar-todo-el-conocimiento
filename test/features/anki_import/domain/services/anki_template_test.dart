import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_template.dart';

void main() {
  const fields = {'Front': 'Pregunta', 'Back': 'Respuesta', 'Empty': ''};

  String render(
    String template, {
    Map<String, String> values = fields,
    String frontSide = '',
    bool answerSide = false,
    Map<String, String> special = const {},
    String Function(String)? clozeFilter,
  }) => AnkiTemplate.parse(template).render(
    values,
    frontSide: frontSide,
    answerSide: answerSide,
    special: special,
    clozeFilter: clozeFilter,
  );

  group('campos y FrontSide', () {
    test('un campo', () {
      expect(render('{{Front}}'), 'Pregunta');
      expect(render('a {{Front}} b {{Back}} c'), 'a Pregunta b Respuesta c');
    });

    test('FrontSide es lo que se le pase', () {
      expect(
        render(
          '{{FrontSide}}<hr id=answer>{{Back}}',
          frontSide: 'FRENTE',
          answerSide: true,
        ),
        'FRENTE<hr id=answer>Respuesta',
      );
    });

    test('un campo que no existe es vacío; un nombre con espacios sirve', () {
      expect(render('[{{Nada}}]'), '[]');
      expect(render('{{Add Reverse}}', values: {'Add Reverse': 'sí'}), 'sí');
    });

    test('los campos especiales', () {
      expect(
        render(
          '{{Tags}} | {{Deck}} | {{Subdeck}} | {{Card}}',
          special: {
            'Tags': 'a b',
            'Deck': 'H::R',
            'Subdeck': 'R',
            'Card': 'Tarjeta 1',
          },
        ),
        'a b | H::R | R | Tarjeta 1',
      );
    });

    test('un campo del usuario le gana a uno especial', () {
      expect(
        render('{{Tags}}', values: {'Tags': 'mío'}, special: {'Tags': 'x'}),
        'mío',
      );
    });

    test('un comentario no cuenta como una variable de la plantilla', () {
      expect(
        AnkiTemplate.parse('{{!type:Back}} {{!cloze:Text}}').variables,
        isEmpty,
      );
    });

    test('un comentario no se escribe', () {
      expect(render('a{{! esto no va }}b'), 'ab');
    });
  });

  group('filtros', () {
    test('type: el frente no lo muestra, el dorso sí', () {
      expect(render('{{Front}}{{type:Back}}'), 'Pregunta');
      expect(
        render('{{Front}}{{type:Back}}', answerSide: true),
        'PreguntaRespuesta',
      );
    });

    test('hint: no se escribe', () {
      expect(render('{{hint:Back}}x'), 'x');
    });

    test('text: y los desconocidos dejan el valor', () {
      expect(render('{{text:Front}} {{furigana:Back}}'), 'Pregunta Respuesta');
    });

    test('cloze: pasa por el filtro dado, o deja el valor sin él', () {
      expect(render('{{cloze:Front}}'), 'Pregunta');
      expect(
        render('<{{cloze:Front}}>', clozeFilter: (v) => v.toUpperCase()),
        '<PREGUNTA>',
      );
      expect(render('<{{cloze:Front}}>', clozeFilter: (_) => ''), '<>');
    });

    test('variables lista cada etiqueta con sus filtros', () {
      final vars = AnkiTemplate.parse(
        '{{Front}}{{#Back}}{{type:Back}}{{/Back}}{{cloze:Text}}',
      ).variables;

      expect(vars.map((v) => v.field), ['Front', 'Back', 'Text']);
      expect(vars[1].hasFilter('type'), isTrue);
      expect(vars[2].hasFilter('cloze'), isTrue);
      expect(vars[0].filters, isEmpty);
    });
  });

  group('condicionales', () {
    test('{{#Campo}} solo si hay algo', () {
      expect(render('{{#Back}}[{{Back}}]{{/Back}}'), '[Respuesta]');
      expect(render('{{#Empty}}[{{Empty}}]{{/Empty}}x'), 'x');
      expect(render('{{#Nada}}no{{/Nada}}x'), 'x');
    });

    test('{{^Campo}} solo si no hay nada', () {
      expect(render('{{^Empty}}vacío{{/Empty}}'), 'vacío');
      expect(render('{{^Back}}vacío{{/Back}}x'), 'x');
    });

    test('un campo con solo <br> o <div> está vacío', () {
      expect(
        render(
          '{{#A}}si{{/A}}{{^A}}no{{/A}}',
          values: {'A': ' <br><div></div>\n<br />'},
        ),
        'no',
      );
      expect(render('{{#A}}si{{/A}}', values: {'A': '<b>x</b>'}), 'si');
    });

    test('anidados', () {
      expect(
        render('{{#Front}}a{{#Empty}}b{{/Empty}}{{#Back}}c{{/Back}}{{/Front}}'),
        'ac',
      );
    });

    test('la plantilla de "tarjeta invertida opcional"', () {
      const template = '{{#Add Reverse}}{{Back}}{{/Add Reverse}}';
      expect(render(template, values: {'Back': 'x', 'Add Reverse': 'y'}), 'x');
      expect(render(template, values: {'Back': 'x', 'Add Reverse': ''}), '');
    });
  });

  group('plantillas rotas no lanzan', () {
    test('una sección sin cerrar se cierra sola al final', () {
      expect(render('{{#Back}}a{{Front}}'), 'aPregunta');
    });

    test('un cierre de más se ignora', () {
      expect(render('a{{/Back}}b'), 'ab');
    });

    test('llaves sueltas son texto', () {
      expect(render('{ {Front} } {{Front'), '{ {Front} } {{Front');
    });

    test('plantilla vacía', () {
      expect(render(''), '');
    });
  });
}
