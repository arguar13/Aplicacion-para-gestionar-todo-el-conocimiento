import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/domain/services/structured_json.dart';

/// Leer con tolerancia el JSON que contesta un modelo (F43): bloques de
/// código, frases antes y después, comas colgantes y respuestas cortadas.
void main() {
  group('lo que se lee', () {
    test('un JSON solo, tal cual', () {
      expect(extractJsonValue('{"titulo": "Éxodo", "n": 3}'), {
        'titulo': 'Éxodo',
        'n': 3,
      });
      expect(extractJsonValue('  [1, 2, 3]\n'), [1, 2, 3]);
    });

    test('dentro de un bloque de código, con o sin «json»', () {
      expect(extractJsonValue('Acá está:\n```json\n{"a": 1}\n```\n¡Listo!'), {
        'a': 1,
      });
      expect(extractJsonValue('```\n[{"a": 1}]\n```'), [
        {'a': 1},
      ]);
    });

    test('un bloque sin cerrar: lo que sigue', () {
      expect(extractJsonValue('```json\n{"a": [1, 2]}'), {
        'a': [1, 2],
      });
    });

    test('con una frase antes y después: el objeto más de afuera', () {
      expect(
        extractJsonValue(
          '¡Claro! Este es el mapa {"raiz": {"hijos": [{"t": "Moisés"}]}} '
          'espero que sirva.',
        ),
        {
          'raiz': {
            'hijos': [
              {'t': 'Moisés'},
            ],
          },
        },
      );
    });

    test(
      'una cita entre corchetes antes no confunde: se prueba el próximo',
      () {
        expect(extractJsonValue('Según la fuente [1], va así: {"ok": true}'), {
          'ok': true,
        });
      },
    );

    test('llaves y corchetes dentro de un texto no cuentan', () {
      expect(
        extractJsonValue(r'{"t": "un } y un ] y un \" escapado", "n": [1]}'),
        {
          't': 'un } y un ] y un " escapado',
          'n': [1],
        },
      );
    });

    test('sin las comas colgantes, que fuera de un texto sobran', () {
      expect(extractJsonValue('{"a": [1, 2,], "b": "x,}",}'), {
        'a': [1, 2],
        'b': 'x,}',
      });
    });
  });

  group('lo que no se puede leer, con su motivo', () {
    test('vacía', () {
      expect(
        () => extractJsonValue('   '),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'motivo',
            contains('vacía'),
          ),
        ),
      );
    });

    test('sin ningún JSON', () {
      expect(
        () => extractJsonValue('No puedo hacer eso.'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'motivo',
            contains('ningún JSON'),
          ),
        ),
      );
    });

    test('cortada antes de cerrarse: lo dice, para pedir que la complete', () {
      expect(
        () => extractJsonValue('{"secciones": [{"t": "Intro"}, {"t": "Pla'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'motivo',
            contains('se cortó'),
          ),
        ),
      );
    });
  });

  test('una cita y después un JSON cortado: se cortó, no la cita', () {
    expect(
      () => extractJsonValue('Según [1], acá va: {"titulo": "Éxod'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'motivo',
          contains('se cortó'),
        ),
      ),
    );
  });

  test('las comas colgantes solo se sacan fuera de los textos', () {
    expect(withoutTrailingCommas('[1, 2 ,\n]'), '[1, 2 \n]');
    expect(withoutTrailingCommas('{"a": ",]"}'), '{"a": ",]"}');
  });
}
