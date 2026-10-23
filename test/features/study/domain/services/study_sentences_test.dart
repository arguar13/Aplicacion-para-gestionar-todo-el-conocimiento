import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';

/// Las oraciones de un documento, tal cual están en su texto (F36).
void main() {
  List<String> sentencesOf(String content, {bool markdown = false}) => [
    for (final s in splitStudySentences(content, markdown: markdown))
      content.substring(s.start, s.end),
  ];

  group('dónde termina una oración', () {
    test('un punto, un signo de pregunta o de exclamación y un espacio', () {
      expect(sentencesOf('Uno. ¿Dos? ¡Tres! Cuatro…  Cinco'), [
        'Uno.',
        '¿Dos?',
        '¡Tres!',
        'Cuatro…',
        'Cinco',
      ]);
    });

    test('con las comillas y el paréntesis que cierran, adentro', () {
      expect(sentencesOf('Dijo «basta.» Luego (se fue.) Fin.'), [
        'Dijo «basta.»',
        'Luego (se fue.)',
        'Fin.',
      ]);
    });

    test('si lo que sigue empieza en minúscula, no termina', () {
      expect(sentencesOf('Libros, revistas, etc. y otras cosas. Fin.'), [
        'Libros, revistas, etc. y otras cosas.',
        'Fin.',
      ]);
    });

    test('ni una abreviatura ni una inicial la terminan', () {
      expect(
        sentencesOf(
          'El Sr. Pérez y la Dra. Gómez viajaron a EE. UU. en 1990. '
          'Lo escribió J. R. R. Tolkien. Ver el art. 5 de la ley.',
        ),
        [
          'El Sr. Pérez y la Dra. Gómez viajaron a EE. UU. en 1990.',
          'Lo escribió J. R. R. Tolkien.',
          'Ver el art. 5 de la ley.',
        ],
      );
    });

    test('«no.» termina una oración en castellano', () {
      expect(sentencesOf('Dijo que no. Luego se fue.'), [
        'Dijo que no.',
        'Luego se fue.',
      ]);
    });

    test('un número con punto no la termina', () {
      expect(sentencesOf('Mide 3.5 metros. Pesa 2.000 kilos.'), [
        'Mide 3.5 metros.',
        'Pesa 2.000 kilos.',
      ]);
    });
  });

  group('los renglones', () {
    test('en un PDF, un salto de línea solo no corta: la oración sigue', () {
      const page =
          'La revolución industrial empezó\nen Inglaterra. Cambió\ntodo.';
      expect(sentencesOf(page), [
        'La revolución industrial empezó\nen Inglaterra.',
        'Cambió\ntodo.',
      ]);
    });

    test('un renglón en blanco corta, aunque falte el punto', () {
      expect(sentencesOf('Un título sin punto\n\nEl párrafo.'), [
        'Un título sin punto',
        'El párrafo.',
      ]);
    });

    test('el separador de páginas corta y no es una oración', () {
      expect(sentencesOf('Fin de una página\n\n---\n\nOtra página.'), [
        'Fin de una página',
        'Otra página.',
      ]);
    });

    test('el separador corta aunque esté pegado al texto', () {
      expect(sentencesOf('Fin sin punto\n---\nOtra.'), [
        'Fin sin punto',
        'Otra.',
      ]);
    });

    test('en un texto sin Markdown, cada viñeta es su oración, sin la '
        'viñeta', () {
      const list = 'Ventajas:\n• rápido\n• barato\n- simple';
      expect(sentencesOf(list), ['Ventajas:', 'rápido', 'barato', 'simple']);
    });
  });

  group('en Markdown', () {
    test('un título es una oración, sin sus #', () {
      expect(sentencesOf('# Capítulo 1\nEra una vez.', markdown: true), [
        'Capítulo 1',
        'Era una vez.',
      ]);
    });

    test('los ítems de una lista y una cita, sin su marca', () {
      expect(sentencesOf('- uno\n- dos\n1. tres\n> cuatro', markdown: true), [
        'uno',
        'dos',
        'tres',
        'cuatro',
      ]);
    });

    test('la negrita que cierra una oración queda adentro', () {
      expect(sentencesOf('Es **clave.** Sigue.', markdown: true), [
        'Es **clave.**',
        'Sigue.',
      ]);
    });

    test('una imagen sola en su renglón no es una oración', () {
      expect(sentencesOf('![foto](a.png)\n\nTexto.', markdown: true), [
        'Texto.',
      ]);
    });
  });

  test('las posiciones son las del texto guardado', () {
    const content = '  Hola mundo.   Chau.';
    final sentences = splitStudySentences(content, markdown: false);
    expect(sentences, const [StudySentence(2, 13), StudySentence(16, 21)]);
  });

  test('sin una letra ni un número, no hay oración', () {
    expect(sentencesOf('...\n\n— — —\n\n!!'), isEmpty);
  });

  test('una tabla o una lista sin puntos se parte en sus renglones', () {
    final rows = List.generate(40, (i) => 'fila $i con varios datos sueltos');
    final content = rows.join('\n');
    final sentences = splitStudySentences(content, markdown: false);

    expect(sentences.length, greaterThan(1));
    for (final s in sentences) {
      expect(s.length, lessThanOrEqualTo(kMaxStudySentenceChars + 40));
    }
    expect(
      sentences.map((s) => content.substring(s.start, s.end)).join('\n'),
      content,
    );
  });

  test('la marca de tiempo de una transcripción queda afuera, y cada '
      'renglón es su bloque (F39)', () {
    const content =
        '[0:05] Hola a todos. Hoy hablamos del vapor.\n'
        '[1:02:10] Las fábricas cambiaron todo.';

    expect(sentencesOf(content), [
      'Hola a todos.',
      'Hoy hablamos del vapor.',
      'Las fábricas cambiaron todo.',
    ]);
    expect(
      splitStudySentences(
        content,
        markdown: true,
      ).map((s) => content.substring(s.start, s.end)),
      contains('Las fábricas cambiaron todo.'),
    );
  });
}
