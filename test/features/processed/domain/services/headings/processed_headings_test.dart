import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/processed/domain/services/headings/processed_headings.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';

/// Los títulos de un documento procesado, listos para el Índice (F46, paso
/// 1, decisiones B y C): de dónde sale cada uno según la clase de texto, con
/// sus niveles corridos, su tramo en el texto procesado, la página del texto
/// —la misma del lector— y la del PDF; un texto sin títulos es una sola
/// entrada, y nada se inventa.
void main() {
  const body = 'Un párrafo con lo que cuenta el documento, de punta a punta.';

  List<ProcessedHeading> read(
    List<String> pages, {
    ProcessedTextKind kind = ProcessedTextKind.markdown,
    PdfOutline? pdf,
  }) => readProcessedHeadings(
    ProcessedHeadingsSource(pages: pages, kind: kind, pdf: pdf),
  );

  /// Lo que cubre el tramo de [heading] en el texto de [pages].
  String spanOf(List<String> pages, ProcessedHeading heading) =>
      pages.join().substring(heading.start!, heading.end);

  PdfBookmark mark(String title, int depth, [int? page]) =>
      PdfBookmark(title: title, depth: depth, page: page);

  group('un texto en Markdown', () {
    test('sus títulos, en orden, con los niveles corridos, su tramo y la '
        'página del texto donde cae cada uno', () {
      final pages = ['# Roma\n\n$body\n\n', '### La caída\n\n$body'];
      final headings = read(pages);
      expect(headings, [
        const ProcessedHeading(
          order: 0,
          level: 1,
          title: 'Roma',
          origin: ProcessedHeadingOrigin.textHeading,
          start: 2,
          end: 6,
          textPage: 1,
        ),
        ProcessedHeading(
          order: 1,
          level: 2,
          title: 'La caída',
          origin: ProcessedHeadingOrigin.textHeading,
          start: pages.first.length + 4,
          end: pages.first.length + 12,
          textPage: 2,
        ),
      ]);
      expect(
        [for (final h in headings) spanOf(pages, h)],
        ['Roma', 'La caída'],
      );
    });

    test('la página del texto es la de sus páginas guardadas '
        '(kProcessedTextPageChars): la misma «Página 3 de 6» del lector', () {
      final text = [
        for (var i = 0; i < 40; i++) '## Capítulo $i\n\n${'$body ' * 8}',
      ].join('\n\n');
      final pages = [for (final page in processedTextPages(text)) page.text];
      expect(pages.length, greaterThanOrEqualTo(3));
      final headings = read(pages);
      expect(headings, hasLength(40));
      var start = 0;
      final starts = <int>[];
      for (final page in pages) {
        starts.add(start);
        start += page.length;
      }
      for (final heading in headings) {
        final page = heading.textPage!;
        expect(heading.start, greaterThanOrEqualTo(starts[page - 1]));
        if (page < pages.length) {
          expect(heading.start, lessThan(starts[page]));
        }
      }
      expect(headings.last.textPage, pages.length);
    });

    test('un título justo al comienzo de una página es de esa página', () {
      final headings = read(['$body\n\n', '# Arriba\n\n$body']);
      expect(headings.single.textPage, 2);
    });

    test('un documento que empieza en ### empieza en 1, y los repetidos van '
        'cada uno en su lugar', () {
      final headings = read([
        '### Notas\n\n$body\n\n#### Uno\n\n$body\n\n### Notas\n\n$body',
      ]);
      expect(
        [for (final h in headings) (h.level, h.title)],
        [(1, 'Notas'), (2, 'Uno'), (1, 'Notas')],
      );
      expect([for (final h in headings) h.order], [0, 1, 2]);
    });

    test('lo que no es un título no entra', () {
      const noise =
          '**Negrita suelta**\n\n```\n# código\n```\n\n> # cita\n\n'
          '| # | x |';
      final headings = read(['$noise\n\n# Real\n\n$body']);
      expect([for (final h in headings) h.title], ['Real']);
    });

    test('un PDF que se pasa por error a un Markdown no se lee como PDF', () {
      final headings = read([
        '# Uno\n\n$body',
      ], pdf: PdfOutline(pageCount: 1, bookmarks: [mark('Otro', 1, 1)]));
      expect(headings.single.origin, ProcessedHeadingOrigin.textHeading);
      expect(headings.single.pdfPage, isNull);
    });
  });

  group('un texto sin títulos', () {
    const whole = ProcessedHeading(
      order: 0,
      level: 1,
      title: '',
      origin: ProcessedHeadingOrigin.wholeText,
      start: 0,
      end: 0,
      textPage: 1,
    );

    test('es una sola entrada, «Texto completo», que abre desde el '
        'principio', () {
      expect(read(['$body\n\n$body']), [whole]);
    });

    test('una transcripción o un texto tal cual no tiene títulos, aunque '
        'algún renglón lo parezca', () {
      expect(
        read(['# 3 de la lista\n\n$body'], kind: ProcessedTextKind.plain),
        [whole],
      );
      expect(
        read(['[00:01] Hola\n[00:05] # no'], kind: ProcessedTextKind.plain),
        [whole],
      );
    });

    test('un PDF sin títulos lleva su primera página', () {
      expect(
        read(
          [body],
          kind: ProcessedTextKind.pdf,
          pdf: PdfOutline(pageCount: 3),
        ),
        [
          const ProcessedHeading(
            order: 0,
            level: 1,
            title: '',
            origin: ProcessedHeadingOrigin.wholeText,
            start: 0,
            end: 0,
            textPage: 1,
            pdfPage: 1,
          ),
        ],
      );
    });

    test('sin texto —un documento de solo imágenes—, ninguna', () {
      expect(read(const []), isEmpty);
      expect(read(['  \n\n ', '']), isEmpty);
    });
  });

  group('un PDF con marcadores', () {
    final pages = [
      ['Índice', 'Introducción', 'El origen', 'La caída'].join('\n'),
      'Introducción\n$body',
      'El origen\n$body\nLos reyes\n$body',
      'Una página sin títulos.',
    ];
    final text = pages.join(pdfPageSeparator);

    test('sus marcadores, con su página real y su nivel corrido, ubicados '
        'en el texto; lo que no se ubica queda con su página y sin lugar', () {
      final headings = read(
        [text],
        kind: ProcessedTextKind.pdf,
        pdf: PdfOutline(
          pageCount: 4,
          bookmarks: [
            mark('Introducción', 1, 2),
            mark('El origen', 1, 3),
            mark('Los reyes', 3, 3),
            mark('La caída', 1, 4),
          ],
        ),
      );
      expect(
        [for (final h in headings) (h.level, h.title, h.pdfPage)],
        [
          (1, 'Introducción', 2),
          (1, 'El origen', 3),
          (2, 'Los reyes', 3),
          (1, 'La caída', 4),
        ],
      );
      expect([
        for (final h in headings) h.origin,
      ], everyElement(ProcessedHeadingOrigin.bookmark));
      expect(headings[0].start, text.indexOf('Introducción\n$body'));
      expect(headings[2].start, text.indexOf('Los reyes'));
      expect(headings[3].located, isFalse);
      expect(headings[3].textPage, isNull);
      expect([for (final h in headings.take(3)) h.textPage], [1, 1, 1]);
    });

    test('un marcador sin título se saltea, y sus hijos suben; una página '
        'que el PDF no tiene no se dice', () {
      final headings = read(
        [text],
        kind: ProcessedTextKind.pdf,
        pdf: PdfOutline(
          pageCount: 4,
          bookmarks: [
            mark('  \u0000 ', 1, 2),
            mark('Introducción', 2, 2),
            mark('El origen', 2, 99),
          ],
        ),
      );
      expect(
        [for (final h in headings) (h.level, h.title, h.pdfPage)],
        [(1, 'Introducción', 2), (1, 'El origen', null)],
      );
      // Sin página, se busca entre vecinos: el del cuerpo, no el del índice.
      expect(headings[1].start, text.indexOf('El origen\n$body'));
    });

    test('el título de un marcador se lee limpio', () {
      final headings = read(
        [text],
        kind: ProcessedTextKind.pdf,
        pdf: PdfOutline(
          pageCount: 4,
          bookmarks: [mark('  El\r\norigen\u0000', 1, 3)],
        ),
      );
      expect(headings.single.title, 'El origen');
      expect(headings.single.located, isTrue);
    });
  });

  group('un PDF sin marcadores', () {
    final pages = ['La fundación\n\n$body', '$body\n\nLa república\n\n$body'];
    final text = pages.join(pdfPageSeparator);

    test('los títulos que dejó la IA, con la página del PDF donde caen', () {
      final headings = read(
        [text],
        kind: ProcessedTextKind.pdf,
        pdf: PdfOutline(pageCount: 2),
      );
      expect(
        [for (final h in headings) (h.title, h.origin, h.pdfPage, h.textPage)],
        [
          ('La fundación', ProcessedHeadingOrigin.aiTitle, 1, 1),
          ('La república', ProcessedHeadingOrigin.aiTitle, 2, 1),
        ],
      );
    });

    test('si el texto ya no tiene una raya por página, sin la página del '
        'PDF', () {
      final headings = read(
        [pages.join('\n\n')],
        kind: ProcessedTextKind.pdf,
        pdf: PdfOutline(pageCount: 2),
      );
      expect([for (final h in headings) h.pdfPage], [null, null]);
      expect(headings, hasLength(2));
    });

    test('si no se pudo leer el archivo, igual los títulos de la IA', () {
      final headings = read([text], kind: ProcessedTextKind.pdf);
      expect(
        [for (final h in headings) (h.title, h.pdfPage)],
        [('La fundación', null), ('La república', null)],
      );
    });

    test('con marcadores que no dicen nada, como si no tuviera', () {
      final headings = read(
        [text],
        kind: ProcessedTextKind.pdf,
        pdf: PdfOutline(pageCount: 2, bookmarks: [mark('  ', 1, 1)]),
      );
      expect([
        for (final h in headings) h.origin,
      ], everyElement(ProcessedHeadingOrigin.aiTitle));
    });
  });

  group('processedTextKindOf', () {
    test('Markdown gana; si no, un PDF por su nombre; si no, tal cual', () {
      expect(
        processedTextKindOf(markdown: true, originalFileName: 'a.pdf'),
        ProcessedTextKind.markdown,
      );
      expect(
        processedTextKindOf(markdown: false, originalFileName: 'x/LIBRO.PDF'),
        ProcessedTextKind.pdf,
      );
      expect(
        processedTextKindOf(markdown: false, originalFileName: 'notas.txt'),
        ProcessedTextKind.plain,
      );
      expect(processedTextKindOf(markdown: false), ProcessedTextKind.plain);
    });
  });

  test('cleanBookmarkTitle: sin caracteres de control y con un espacio', () {
    expect(cleanBookmarkTitle(' Cap\u0000ítulo\t 1\r\n '), 'Cap ítulo 1');
    expect(cleanBookmarkTitle('\u0000'), '');
  });

  group('escala: un libro de miles de títulos, en tiempo lineal', () {
    /// Cuánto tarda, en microsegundos, lo mejor de tres corridas de [run].
    int bestOf(void Function() run) {
      var best = 1 << 62;
      for (var i = 0; i < 3; i++) {
        final watch = Stopwatch()..start();
        run();
        watch.stop();
        if (watch.elapsedMicroseconds < best) {
          best = watch.elapsedMicroseconds;
        }
      }
      return best;
    }

    /// Que [run] sobre lo que arma [build] con ocho veces más títulos tarde
    /// bastante menos que 64 veces más —lo que tardaría si fuera
    /// cuadrático—: hasta 20 veces, con margen para el ruido de la máquina.
    void growsLinearly(
      ProcessedHeadingsSource Function(int titles) build,
      int Function(List<ProcessedHeading>) count,
    ) {
      const small = 1500;
      final smallSource = build(small);
      final bigSource = build(small * 8);
      // Calentar: la primera corrida compila.
      expect(count(readProcessedHeadings(smallSource)), small);
      expect(count(readProcessedHeadings(bigSource)), small * 8);
      final smallTime = bestOf(() => readProcessedHeadings(smallSource));
      final bigTime = bestOf(() => readProcessedHeadings(bigSource));
      expect(
        bigTime,
        lessThan(smallTime * 20),
        reason: '$small títulos: $smallTime µs; ${small * 8}: $bigTime µs',
      );
    }

    test('los títulos de un Markdown', () {
      growsLinearly(
        (n) => ProcessedHeadingsSource(
          pages: [
            for (final page in processedTextPages(
              [
                for (var i = 0; i < n; i++)
                  '${'#' * (i % 3 + 1)} Título $i\n\n$body',
              ].join('\n\n'),
            ))
              page.text,
          ],
          kind: ProcessedTextKind.markdown,
        ),
        (headings) => headings.length,
      );
    });

    test('los marcadores de un PDF, en su página', () {
      growsLinearly((n) {
        final text = [
          for (var i = 0; i < n; i++) 'Capítulo $i\n$body',
        ].join(pdfPageSeparator);
        return ProcessedHeadingsSource(
          pages: [for (final page in processedTextPages(text)) page.text],
          kind: ProcessedTextKind.pdf,
          pdf: PdfOutline(
            pageCount: n,
            bookmarks: [
              for (var i = 0; i < n; i++) mark('Capítulo $i', 1, i + 1),
            ],
          ),
        );
      }, (headings) => headings.where((h) => h.located).length);
    });

    test('los marcadores de un PDF sin una raya por página', () {
      growsLinearly((n) {
        final text = [
          for (var i = 0; i < n; i++) 'Capítulo $i\n\n$body',
        ].join('\n\n');
        return ProcessedHeadingsSource(
          pages: [for (final page in processedTextPages(text)) page.text],
          kind: ProcessedTextKind.pdf,
          pdf: PdfOutline(
            pageCount: n,
            bookmarks: [for (var i = 0; i < n; i++) mark('Capítulo $i', 1)],
          ),
        );
      }, (headings) => headings.where((h) => h.located).length);
    });

    test('los títulos que dejó la IA', () {
      growsLinearly((n) {
        final text = [
          for (var i = 0; i < n; i++) 'Capítulo $i\n\n$body',
        ].join(pdfPageSeparator);
        return ProcessedHeadingsSource(
          pages: [for (final page in processedTextPages(text)) page.text],
          kind: ProcessedTextKind.pdf,
          pdf: PdfOutline(pageCount: n),
        );
      }, (headings) => headings.length);
    });
  });
}
