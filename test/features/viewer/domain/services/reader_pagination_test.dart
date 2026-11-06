import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/markdown_inline.dart';
import 'package:sinapsis/features/viewer/domain/services/reader_pagination.dart';

void main() {
  test('contenido vacío no tiene páginas', () {
    expect(splitIntoReaderPages(''), isEmpty);
    expect(splitIntoReaderPages('   \n  '), isEmpty);
  });

  test('un texto corto entra en una sola página', () {
    final pages = splitIntoReaderPages('Un texto cualquiera, bien corto.');

    expect(pages, hasLength(1));
    expect(pages.single, 'Un texto cualquiera, bien corto.');
  });

  test('un PDF con el separador de página de PdfParser corta ahí — página '
      'del libro, página del lector', () {
    const content = 'Página uno.\n\n---\n\nPágina dos.\n\n---\n\nPágina tres.';

    final pages = splitIntoReaderPages(content);

    expect(pages, ['Página uno.', 'Página dos.', 'Página tres.']);
  });

  test('párrafos se van juntando en una página hasta acercarse al límite', () {
    final paragraphs = List.generate(5, (i) => 'Párrafo número $i.');
    final content = paragraphs.join('\n\n');

    final pages = splitIntoReaderPages(content, targetPageLength: 40);

    // Ninguna página se pasa del límite salvo que un párrafo solo ya lo
    // supere (no es el caso acá), y ningún párrafo queda partido.
    for (final page in pages) {
      expect(page.length, lessThanOrEqualTo(40));
    }
    expect(pages.join('\n\n'), content);
  });

  test('un párrafo más largo que el límite se corta él solo, en un espacio, '
      'sin partir palabras', () {
    final longParagraph = List.generate(20, (i) => 'palabra$i').join(' ');

    final pages = splitIntoReaderPages(longParagraph, targetPageLength: 30);

    expect(pages.length, greaterThan(1));
    for (final page in pages) {
      expect(page.length, lessThanOrEqualTo(30));
      // Ninguna página termina a mitad de una palabra: el último
      // carácter de cada tramo cortado es el final de una "palabraN"
      // completa, nunca un dígito seguido de más dígitos del original.
      expect(page.trim(), page);
    }
    // Ninguna palabra se perdió ni se duplicó al unir todo de nuevo.
    expect(pages.join(' '), longParagraph);
  });

  test('una página del PDF que por sí sola es enorme también se subdivide', () {
    final hugePage = List.generate(
      50,
      (i) => 'Oración número $i.',
    ).join('\n\n');
    final content = 'Corta.\n\n---\n\n$hugePage';

    final pages = splitIntoReaderPages(content, targetPageLength: 100);

    expect(pages.first, 'Corta.');
    expect(pages.length, greaterThan(2));
  });

  group('readerPageRanges (F36)', () {
    test('un separador pegado al principio o al final —una página vacía de '
        'un PDF— no deja una página con los guiones', () {
      const content = '\n\n---\n\nPágina dos.\n\n---\n\n';

      expect(splitIntoReaderPages(content), ['Página dos.']);
      expect(readerPageRanges(content).single.start, 7);
    });

    test('cada página es el tramo tal cual del contenido, con su lugar', () {
      const content =
          '  \nPágina uno.\n\n\n\nSigue uno.\n\n---\n\nPágina dos.  \n';

      final ranges = readerPageRanges(content, targetPageLength: 12);

      expect(
        [for (final r in ranges) content.substring(r.start, r.end)],
        ['Página uno.', 'Sigue uno.', 'Página dos.'],
      );
      expect(ranges.first.start, content.indexOf('Página uno.'));
      expect(ranges.last.end, content.indexOf('  \n', ranges.last.start));
    });

    test('las mismas páginas que splitIntoReaderPages, aunque haya varios '
        'renglones en blanco entre párrafos', () {
      final content = [
        for (var i = 0; i < 30; i++) 'Párrafo $i con algo de texto.',
      ].join('\n\n\n');

      final ranges = readerPageRanges(content, targetPageLength: 100);
      final pages = splitIntoReaderPages(content, targetPageLength: 100);

      expect(pages, [
        for (final r in ranges) content.substring(r.start, r.end),
      ]);
      for (var i = 1; i < ranges.length; i++) {
        expect(ranges[i].start, greaterThan(ranges[i - 1].end));
      }
      expect(pages.length, greaterThan(1));
    });

    test('un párrafo cortado a la fuerza deja tramos contiguos sin perder '
        'nada', () {
      final content = List.generate(40, (i) => 'palabra$i').join(' ');

      final ranges = readerPageRanges(content, targetPageLength: 50);

      expect(ranges.first.start, 0);
      expect(ranges.last.end, content.length);
      for (var i = 1; i < ranges.length; i++) {
        expect(content.substring(ranges[i - 1].end, ranges[i].start), ' ');
      }
    });
  });

  group('los títulos de un libro, para «Contenido» (F47, paso 1)', () {
    test('los de los tres primeros niveles, en orden, sin el formato de '
        'adentro', () {
      const content =
          '# Primera parte\n\nTexto.\n\n## Un **capítulo** con '
          '[enlace](https://x.org)\n\nMás.\n\n#### Muy adentro\n\n'
          '### Al final ##\n#sin espacio';
      final headings = readerHeadings(content);
      expect(
        [for (final h in headings) h.text],
        ['Primera parte', 'Un capítulo con enlace', 'Al final'],
      );
      expect([for (final h in headings) h.level], [1, 2, 3]);
      expect(content.substring(headings[1].offset), startsWith('## Un'));
    });

    test('hasta un tope, y lo mismo en otro hilo', () async {
      final content = [
        for (var i = 0; i < kReaderMaxHeadings + 50; i++) '## Título $i',
      ].join('\n\n');
      expect(readerHeadings(content), hasLength(kReaderMaxHeadings));
      final long = '${'x' * kReaderInlineChars}\n\n# Lejos';
      final off = await readerHeadingsOff(long);
      expect(off.single.text, 'Lejos');
      expect(off.single.offset, long.indexOf('# Lejos'));
    });
  });

  group('un corte nunca parte un enlace, una imagen ni un énfasis (F46, '
      'paso 5b)', () {
    /// Que ninguna construcción de [content] quede partida entre dos de
    /// [ranges], y que cada tramo, leído solo, tenga las mismas
    /// construcciones que tenía en el texto entero.
    void expectWholeConstructs(
      String content,
      List<({int start, int end})> ranges,
    ) {
      final spans = [
        for (final m in markdownInlinePattern.allMatches(content))
          (start: m.start, end: m.end),
      ];
      for (final span in spans) {
        expect(
          ranges.where((r) => r.start <= span.start && span.end <= r.end),
          hasLength(1),
          reason:
              'partida: «${content.substring(span.start, span.end)}» entre '
              '$ranges',
        );
      }
      for (final range in ranges) {
        final alone = [
          for (final m in markdownInlinePattern.allMatches(
            content.substring(range.start, range.end),
          ))
            (start: range.start + m.start, end: range.start + m.end),
        ];
        expect(alone, [
          for (final s in spans)
            if (range.start <= s.start && s.end <= range.end) s,
        ]);
      }
    }

    test('el párrafo de Fotosíntesis que se vio crudo en el emulador', () {
      // El primer párrafo del artículo, tal como lo guardó la app: 2.404
      // caracteres de un solo párrafo, que en bloques de 1.200 (el visor de
      // «Leer») se cortaba en «[bacterias» | «purpúreas](…)».
      final paragraph = File(
        'test/fixtures/web/wikipedia_fotosintesis_parrafo.md',
      ).readAsStringSync().trim();

      for (final target in [1200, 2400, 300, 80]) {
        final ranges = readerPageRanges(paragraph, targetPageLength: target);
        expectWholeConstructs(paragraph, ranges);
        expect(
          [for (final r in ranges) paragraph.substring(r.start, r.end)].any(
            (piece) =>
                piece.endsWith('[bacterias') || piece.startsWith('purpúreas]'),
          ),
          isFalse,
        );
      }
    });

    test('se corta justo antes del enlace que tapa el límite, y lo que '
        'sigue no cambia', () {
      const content =
          'Las bacterias del azufre se dividen en dos grupos: las '
          '[bacterias purpúreas](https://es.wikipedia.org/wiki/Bacteria) y '
          'las verdes.';
      final cut = content.indexOf('[bacterias');

      final pages = splitIntoReaderPages(content, targetPageLength: cut + 12);

      expect(pages.first, content.substring(0, cut).trim());
      expect(pages[1], startsWith('[bacterias purpúreas](https://'));
      expect(pages.join(' '), content);
    });

    test('un enlace más largo que una página va entero en la suya', () {
      final link = '[un documento](https://x.org/${'a' * 3000})';
      final content = 'Antes del enlace. $link y después del enlace.';

      final ranges = readerPageRanges(content, targetPageLength: 1200);

      expectWholeConstructs(content, ranges);
      expect([
        for (final r in ranges) content.substring(r.start, r.end),
      ], contains(link));
    });

    test('al azar: párrafos con enlaces, imágenes, énfasis y código, en '
        'páginas de cualquier largo', () {
      final random = Random(5);
      const pieces = [
        'palabra ',
        'otra palabra, ',
        'fin. ',
        '[un enlace con texto largo](https://es.wikipedia.org/wiki/X_(y)) ',
        '![una imagen](https://x.org/i.jpg) ',
        '**negrita de varias palabras** ',
        '*cursiva de varias palabras* ',
        '`código con espacios` ',
        '<sup>[[3]](#cite_note-3)</sup> ',
        '\n',
        '\n\n',
      ];
      for (var round = 0; round < 200; round++) {
        final buffer = StringBuffer();
        for (var i = random.nextInt(120); i > 0; i--) {
          buffer.write(pieces[random.nextInt(pieces.length)]);
        }
        final content = buffer.toString();
        final target = 20 + random.nextInt(300);
        final ranges = readerPageRanges(content, targetPageLength: target);
        expectWholeConstructs(content, ranges);
        // Nada se pierde: entre una página y la otra solo hay espacios.
        var at = 0;
        for (final r in ranges) {
          expect(content.substring(at, r.start).trim(), isEmpty);
          at = r.end;
        }
        expect(content.substring(at).trim(), isEmpty);
      }
    });

    test('un texto que no es Markdown se corta como siempre', () {
      final content = List.generate(40, (i) => 'palabra$i').join(' ');

      expect(
        splitIntoReaderPages(content, targetPageLength: 50).first,
        'palabra0 palabra1 palabra2 palabra3 palabra4',
      );
    });
  });
}
