import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/processed/domain/services/headings/heading_text.dart';
import 'package:sinapsis/features/processed/domain/services/headings/markdown_headings.dart';

/// El lector de títulos de un texto en Markdown (F46, paso 1): los de una
/// página web, un Word, un EPUB o un `.md`, con el nivel que traen y su
/// tramo exacto en el texto, y nada que no sea un título.
void main() {
  /// Los títulos de [text] como (nivel, título).
  List<(int, String)> titlesOf(String text) => [
    for (final heading in markdownHeadings(text))
      (heading.level, heading.title),
  ];

  /// Lo que cubre el tramo de cada título de [text].
  List<String> spansOf(String text) => [
    for (final heading in markdownHeadings(text))
      text.substring(heading.start, heading.end),
  ];

  group('los títulos con #', () {
    test('con su nivel y su tramo, sin los # de las puntas', () {
      const text = '# Roma\n\nUn párrafo.\n\n### La caída ###\n\nFin.';
      expect(titlesOf(text), [(1, 'Roma'), (3, 'La caída')]);
      expect(spansOf(text), ['Roma', 'La caída']);
    });

    test('con hasta tres espacios adelante; con cuatro, o un tabulador, es '
        'código', () {
      expect(titlesOf('   ## Tres espacios'), [(2, 'Tres espacios')]);
      expect(titlesOf('    ## Cuatro espacios'), isEmpty);
      expect(titlesOf('\t## Tabulado'), isEmpty);
    });

    test('un # pegado al texto o siete # no son títulos', () {
      expect(titlesOf('#etiqueta y #otra'), isEmpty);
      expect(titlesOf('####### Siete'), isEmpty);
    });

    test('un # que no cierra queda en el título', () {
      expect(titlesOf('## C# y F#'), [(2, 'C# y F#')]);
      expect(titlesOf('## Dos ## más'), [(2, 'Dos ## más')]);
    });

    test('las marcas de adentro no se leen, y el tramo es el del renglón', () {
      const text = '## **Roma** y [Cartago](https://x.org)';
      expect(titlesOf(text), [(2, 'Roma y Cartago')]);
      expect(spansOf(text), ['**Roma** y [Cartago](https://x.org)']);
    });

    test('con numeración, y en mayúsculas, quedan tal cual', () {
      expect(titlesOf('### 1.2.3 El origen\n\n# INTRODUCCIÓN'), [
        (3, '1.2.3 El origen'),
        (1, 'INTRODUCCIÓN'),
      ]);
    });

    test('los repetidos son uno por lugar', () {
      const text = '## Notas\n\nUno.\n\n## Notas\n\nDos.';
      final headings = markdownHeadings(text);
      expect([for (final h in headings) h.title], ['Notas', 'Notas']);
      expect(headings.first.start, isNot(headings.last.start));
      expect(text.substring(headings.last.start), startsWith('Notas\n\nDos.'));
    });

    test('vacíos, o solo marcas y puntuación, no son títulos', () {
      expect(titlesOf('#\n\n## \n\n### ###\n\n# ***\n\n## · · ·'), isEmpty);
    });

    test('un título partido en renglones del mismo nivel es uno solo', () {
      const text = '# Capítulo 2\n# El comienzo\n\nTexto.';
      expect(titlesOf(text), [(1, 'Capítulo 2 El comienzo')]);
      expect(spansOf(text), ['Capítulo 2\n# El comienzo']);
    });

    test('dos del mismo nivel con un renglón en blanco, o de distinto nivel '
        'seguidos, son dos', () {
      expect(titlesOf('# Uno\n\n# Dos'), [(1, 'Uno'), (1, 'Dos')]);
      expect(titlesOf('# Uno\n## Dos'), [(1, 'Uno'), (2, 'Dos')]);
    });

    test('uno vacío en el medio no une a sus vecinos', () {
      expect(titlesOf('# Uno\n#\n# Dos'), [(1, 'Uno'), (1, 'Dos')]);
    });

    test('un título corta el párrafo de arriba', () {
      expect(titlesOf('Un párrafo\n## Sigue'), [(2, 'Sigue')]);
    });

    test(r'con \r\n, el \r no es parte del título', () {
      const text = '# Uno\r\n\r\nTexto\r\n## Dos  \r\n';
      expect(titlesOf(text), [(1, 'Uno'), (2, 'Dos')]);
      expect(spansOf(text), ['Uno', 'Dos']);
    });
  });

  group('los títulos subrayados', () {
    test('con === es de nivel 1, con --- de nivel 2, y el tramo es su '
        'párrafo', () {
      const text = 'Primero\n=======\n\nTexto.\n\nSegundo\n---\n';
      expect(titlesOf(text), [(1, 'Primero'), (2, 'Segundo')]);
      expect(spansOf(text), ['Primero', 'Segundo']);
    });

    test('un párrafo de dos renglones subrayado es un título', () {
      const text = 'La caída\ndel imperio\n---';
      expect(titlesOf(text), [(2, 'La caída del imperio')]);
      expect(spansOf(text), ['La caída\ndel imperio']);
    });

    test('una raya después de un renglón en blanco es una raya', () {
      expect(titlesOf('Texto.\n\n---\n\nMás.'), isEmpty);
      expect(titlesOf('Texto.\n***'), isEmpty);
      expect(titlesOf('===\n\nTexto.'), isEmpty);
    });

    test('debajo de una lista o una cita, una raya no es un subrayado', () {
      expect(titlesOf('- un ítem\n---'), isEmpty);
      expect(titlesOf('> una cita\n---'), isEmpty);
    });
  });

  group('lo que no es un título', () {
    test('un renglón en negrita suelto', () {
      expect(titlesOf('**Capítulo 1**\n\nTexto.\n\n__Otro__'), isEmpty);
    });

    test('lo que está dentro de un bloque de código', () {
      const text =
          '```dart\n# no\n```\n'
          '# Sí\n'
          '~~~~\n# tampoco\n~~~\n# todavía no\n~~~~~\n'
          '## También';
      expect(titlesOf(text), [(1, 'Sí'), (2, 'También')]);
    });

    test('un bloque de código sin cerrar llega hasta el final', () {
      expect(titlesOf('# Antes\n```\n# adentro\n\n# sigue adentro'), [
        (1, 'Antes'),
      ]);
    });

    test('tres comillas con comillas en su información no abren código', () {
      expect(titlesOf('``` no `abre`\n# Título'), [(1, 'Título')]);
    });

    test('lo que está en una cita, una lista o una tabla', () {
      expect(titlesOf('> # Citado'), isEmpty);
      expect(titlesOf('- # En la lista'), isEmpty);
      expect(titlesOf('1. # En la lista numerada'), isEmpty);
      expect(titlesOf('- ítem\n\n  # Del ítem\n\n# Afuera'), [(1, 'Afuera')]);
      expect(titlesOf('| # | a |\n|---|---|\n| # | b |'), isEmpty);
      expect(titlesOf('Nombre | Valor\n--- | ---\nUno | 1'), isEmpty);
      // Una raya debajo de la tabla no la subraya: la tabla no es un párrafo.
      expect(titlesOf('Nombre | Valor\n--- | ---\nUno | 1\n---'), isEmpty);
    });

    test('lo que está en un bloque de HTML, hasta el renglón en blanco', () {
      expect(titlesOf('<div>\n# adentro\n</div>\n\n# Afuera'), [(1, 'Afuera')]);
      // En medio de un párrafo, una etiqueta es parte del texto.
      expect(titlesOf('Un párrafo\n<b>sigue</b>\n---'), [
        (2, 'Un párrafo sigue'),
      ]);
    });

    test('el encabezado de datos de un .md', () {
      const text = '---\ntitulo: Algo\nautor: Yo\n---\n# Real';
      expect(titlesOf(text), [(1, 'Real')]);
    });

    test('una raya arriba sin datos es una raya, y lo que sigue se lee', () {
      expect(titlesOf('---\n\n# Uno'), [(1, 'Uno')]);
    });

    test('un texto sin títulos no tiene ninguno', () {
      expect(titlesOf('Solo un párrafo.\n\nY otro.'), isEmpty);
      expect(titlesOf(''), isEmpty);
    });
  });

  test('cada tramo es un pedazo del texto, en orden', () {
    const text = '# A\n\nx\n\nB\n=\n\n## C\n## D\n\n### E';
    final headings = markdownHeadings(text);
    for (var i = 1; i < headings.length; i++) {
      expect(headings[i].start, greaterThan(headings[i - 1].end));
    }
    expect([for (final h in headings) h.title], ['A', 'B', 'C D', 'E']);
    expect(runningLevels([for (final h in headings) h.level]), [1, 1, 2, 3]);
  });
}
