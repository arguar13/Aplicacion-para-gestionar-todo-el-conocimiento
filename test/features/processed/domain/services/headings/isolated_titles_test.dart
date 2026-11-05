import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/processed/domain/services/headings/isolated_titles.dart';

/// Los títulos de un PDF sin marcadores tal como los deja la IA al ordenar
/// el texto al triar (F46, decisión B; F45, decisión B): cada uno solo en su
/// renglón, entre dos en blanco. Se reconocen por esa forma y por lo que los
/// distingue de un párrafo, y si la forma no es la de un texto ordenado, no
/// se inventa ninguno.
void main() {
  List<(int, String)> titlesOf(String text) => [
    for (final title in isolatedTitles(text)) (title.level, title.title),
  ];

  const body =
      'Roma fue fundada, según la leyenda, por Rómulo y Remo en el año 753 '
      'antes de nuestra era, y creció hasta dominar el Mediterráneo.';

  group('lo que la IA deja como título', () {
    test('un renglón corto entre dos en blanco, con su tramo exacto', () {
      const text = 'La fundación\n\n$body\n\nLa república\n\n$body';
      final titles = isolatedTitles(text);
      expect(titlesOf(text), [(1, 'La fundación'), (1, 'La república')]);
      expect(
        [for (final t in titles) text.substring(t.start, t.end)],
        ['La fundación', 'La república'],
      );
    });

    test('en mayúsculas, con signos de pregunta o entre comillas', () {
      const text =
          'CAPÍTULO PRIMERO\n\n$body\n\n¿Qué es la historia?\n\n$body\n\n'
          '«El último rey»\n\n$body';
      expect(titlesOf(text), [
        (1, 'CAPÍTULO PRIMERO'),
        (1, '¿Qué es la historia?'),
        (1, '«El último rey»'),
      ]);
    });

    test('la numeración dice el nivel; sin numeración, nivel 1', () {
      const text =
          '1 Introducción\n\n$body\n\n1.1 El origen\n\n$body\n\n'
          '1.2.3. Un detalle\n\n$body\n\nColón en 1492\n\n$body';
      expect(titlesOf(text), [
        (1, '1 Introducción'),
        (2, '1.1 El origen'),
        (3, '1.2.3. Un detalle'),
        (1, 'Colón en 1492'),
      ]);
    });

    test('un año adelante no es numeración', () {
      expect(titlesOf('1492 La llegada\n\n$body'), [(1, '1492 La llegada')]);
    });

    test('un título seguido de otro: los dos', () {
      const text = 'Parte I\n\nCapítulo 1\n\n$body';
      expect(titlesOf(text), [(1, 'Parte I'), (1, 'Capítulo 1')]);
    });

    test('al comienzo de una página nueva, después de la raya', () {
      const text = '$body\n\n---\n\nLa república\n\n$body';
      expect(titlesOf(text), [(1, 'La república')]);
    });

    test('los repetidos, uno por lugar, si no están en el borde de las '
        'páginas', () {
      const text =
          '$body\n\nEjercicios\n\n$body\n\nEjercicios\n\n$body\n\n'
          'Ejercicios\n\n$body';
      final titles = isolatedTitles(text);
      expect(titles, hasLength(3));
      expect({for (final t in titles) t.start}, hasLength(3));
    });
  });

  group('lo que no es un título', () {
    test('un párrafo largo, o un renglón que termina como una oración', () {
      const text =
          '$body\n\nEsto es una oración corta.\n\n$body\n\n'
          'Y esto, una enumeración:\n\n$body';
      expect(titlesOf(text), isEmpty);
    });

    test('un renglón que sigue a un párrafo cortado a la mitad', () {
      const text =
          '$body Después, la guerra entre Roma y Cartago duró\n\n'
          'Más de un siglo\n\nY terminó con la ciudad arrasada.';
      expect(titlesOf(text), isEmpty);
    });

    test('un renglón al que sigue la continuación de su oración', () {
      const text = '$body\n\nLa guerra de los\n\ncien años fue larga.';
      expect(titlesOf(text), isEmpty);
    });

    test('lo que empieza en minúscula, o termina con un guion de corte', () {
      expect(titlesOf('$body\n\nla caída\n\n$body'), isEmpty);
      expect(titlesOf('$body\n\nLa caí-\n\n$body'), isEmpty);
    });

    test('un renglón de más de quince palabras o 120 caracteres', () {
      const long =
          'Uno dos tres cuatro cinco seis siete ocho nueve diez once doce '
          'trece catorce quince dieciséis';
      expect(titlesOf('$long\n\n$body'), isEmpty);
      final wide = 'A${'x' * 120}';
      expect(titlesOf('$wide\n\n$body'), isEmpty);
    });

    test(
      'números de página, viñetas, marcas de tiempo y la raya de página',
      () {
        const text =
            '$body\n\n12\n\n$body\n\n- Un ítem\n\n$body\n\n'
            '• Otro ítem\n\n$body\n\n1) Tercero\n\n$body\n\n'
            '[01:15] Hola\n\n$body\n\n---\n\n$body';
        expect(titlesOf(text), isEmpty);
      },
    );

    test('el último renglón del texto, sin nada después', () {
      expect(titlesOf('$body\n\nFin'), isEmpty);
    });

    test('un encabezado que se repite en el borde de las páginas', () {
      const page = 'Historia de Roma\n\n$body';
      const text = '$page\n\n---\n\n$page\n\n---\n\n$page';
      expect(titlesOf(text), isEmpty);
    });

    test('un renglón de un bloque de varios renglones', () {
      expect(titlesOf('Un título\ncon dos renglones\n\n$body'), isEmpty);
    });

    test('sin letras', () {
      expect(titlesOf('$body\n\n2024 — 2025\n\n$body'), isEmpty);
    });

    test('un texto sin títulos no tiene ninguno', () {
      expect(titlesOf(body), isEmpty);
      expect(titlesOf(''), isEmpty);
    });
  });

  group('si la forma no es la de un texto ordenado, ninguno', () {
    test('un poema o una lista con un renglón en blanco entre renglón y '
        'renglón no tiene capítulos inventados', () {
      // Cada renglón, corto y con mayúscula, pasaría por título: son casi
      // todos los bloques.
      final text = [
        for (var i = 0; i < 20; i++) 'Verso número $i del poema',
      ].join('\n\n');
      expect(titlesOf(text), isEmpty);
    });

    test('pocos así, en un texto corto, sí son títulos', () {
      final text = [
        for (var i = 0; i < 9; i++) 'Verso número $i del poema',
      ].join('\n\n');
      expect(titlesOf(text), hasLength(8));
    });

    test('un título por párrafo —la mitad de los bloques— sí los tiene, '
        'aunque sean muchos', () {
      final text = [
        for (var i = 0; i < 30; i++) 'Pregunta $i\n\n$body',
      ].join('\n\n');
      expect(titlesOf(text), hasLength(30));
    });
  });
}
