// Los trozos de HTML se pegan tal cual: un espacio de más entre etiquetas
// cambiaría el texto de la página que se prueba.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/features/viewer/domain/services/archived_page_alignment.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_study.dart';

void main() {
  ArchivedPageAlignment align(String body, String content) => alignArchivedPage(
    '<html><head></head><body>$body</body></html>',
    content,
  )!;

  /// `[start, end)` de [snippet] en el texto de la página.
  PageRange onPage(ArchivedPageAlignment a, String snippet, {int from = 0}) {
    final at = a.pageText.indexOf(snippet, from);
    expect(at, greaterThanOrEqualTo(0), reason: 'no está «$snippet»');
    return (start: at, end: at + snippet.length);
  }

  /// Lo que del extraído es [snippet] seleccionado en la página.
  String? picked(ArchivedPageAlignment a, String snippet, {int from = 0}) {
    final range = onPage(a, snippet, from: from);
    final slice = a.contentRangeOf(range.start, range.end);
    return slice == null ? null : a.content.substring(slice.start, slice.end);
  }

  group('de una selección en la página al texto extraído (F38)', () {
    const content =
        'Intro del sitio.\n\n'
        'La **revolución** industrial cambió todo.\n\n'
        'Y después vino la electricidad.';
    const body =
        '<nav>Menú Inicio Contacto</nav><h1>Intro del sitio.</h1>'
        '<p>La <b>revolución</b> industrial cambió todo.</p>'
        '<p>Y después vino la electricidad.</p><footer>Pie</footer>';

    test('unas palabras del medio de un párrafo', () {
      final a = align(body, content);

      expect(picked(a, 'industrial cambió'), 'industrial cambió');
    });

    test('cruzando una etiqueta: el extraído trae su marca de negrita '
        'adentro', () {
      final a = align(body, content);

      expect(picked(a, 'revolución industrial'), 'revolución** industrial');
    });

    test('el punto del final, solo si se eligió', () {
      final a = align(body, content);

      expect(picked(a, 'cambió todo.'), 'cambió todo.');
      expect(picked(a, 'cambió todo'), 'cambió todo');
    });

    test('las comillas de las puntas, también', () {
      final a = align(
        '<p>Dijo: “Hola mundo” ahora mismo.</p>',
        'Dijo: “Hola mundo” ahora mismo.',
      );

      expect(picked(a, '“Hola mundo”'), '“Hola mundo”');
      expect(picked(a, 'Hola mundo'), 'Hola mundo');
    });

    test('un párrafo entero, y uno de otra parte', () {
      final a = align(body, content);

      expect(
        picked(a, 'Y después vino la electricidad.'),
        'Y después vino la electricidad.',
      );
    });

    test('mayúsculas y acentos no importan para encontrarlo', () {
      final a = align(
        '<p>LA REVOLUCIÓN INDUSTRIAL cambió todo el panorama.</p>',
        'la revolución industrial cambió todo el panorama.',
      );

      expect(picked(a, 'REVOLUCIÓN INDUSTRIAL'), 'revolución industrial');
    });

    test('un título corto se encuentra entre los párrafos que lo rodean', () {
      final a = align(
        '<nav>Introducción Contacto</nav>'
            '<p>Un primer párrafo bastante largo que está en el texto.</p>'
            '<h2>Introducción</h2>'
            '<p>Un segundo párrafo bastante largo que también está en el '
            'texto.</p>',
        'Un primer párrafo bastante largo que está en el texto.\n\n'
            'Introducción\n\n'
            'Un segundo párrafo bastante largo que también está en el texto.',
      );

      // El del menú no es el título.
      final title = a.pageText.indexOf('Introducción', 30);
      final slice = a.contentRangeOf(title, title + 'Introducción'.length)!;
      expect(a.content.substring(slice.start, slice.end), 'Introducción');
      final menu = a.pageText.indexOf('Introducción');
      expect(a.contentRangeOf(menu, menu + 'Introducción'.length), isNull);
    });

    test('lo que no es del artículo —el menú, el pie— no se ubica', () {
      final a = align(body, content);

      expect(picked(a, 'Menú Inicio Contacto'), isNull);
      expect(picked(a, 'Pie'), isNull);
    });

    test('una selección que es casi toda del menú tampoco', () {
      final a = align(body, content);
      final menu = a.pageText.indexOf('Menú');
      final end = a.pageText.indexOf('La revolución') + 'La'.length;

      expect(a.contentRangeOf(menu, end), isNull);
    });

    test('el menú pegado al principio de lo elegido no entra', () {
      final a = align(
        '<nav>Menú Inicio Contacto</nav>'
            '<p>La <b>revolución</b> industrial cambió todo.</p>',
        'La **revolución** industrial cambió todo.',
      );
      final end = a.pageText.indexOf('industrial') + 'industrial'.length;
      final start = a.pageText.indexOf('Contacto');

      final slice = a.contentRangeOf(start, end);
      expect(
        a.content.substring(slice!.start, slice.end),
        'La **revolución** industrial',
      );
    });

    test('lo que el extraído dice en otro orden se encuentra igual', () {
      final a = align(
        '<p>Va primera, con su texto largo.</p>'
            '<p>Va segunda, con su otro texto largo.</p>',
        'Va segunda, con su otro texto largo.\n\n'
            'Va primera, con su texto largo.',
      );

      expect(
        picked(a, 'Va primera, con su texto largo.'),
        'Va primera, con su texto largo.',
      );
      expect(
        picked(a, 'Va segunda, con su otro texto largo.'),
        'Va segunda, con su otro texto largo.',
      );
    });

    test('un enlace del Markdown: la dirección no está en la página', () {
      const text = 'Mirá [el sitio oficial](https://x.org/a) hoy mismo.';
      final a = align(
        '<p>Mirá <a href="https://x.org/a">el sitio oficial</a> hoy mismo.</p>',
        text,
      );

      expect(
        picked(a, 'el sitio oficial hoy'),
        'el sitio oficial](https://x.org/a) hoy',
      );
      expect(picked(a, 'Mirá el sitio'), 'Mirá [el sitio');
    });

    test('un renglón con algo de más en el extraído —una nota al pie—: lo que '
        'sí está en la página se ubica por pedazos', () {
      final a = align(
        '<p>Primera mitad del renglón largo que sigue siendo largo y claro '
            'y segunda mitad del renglón que sigue y sigue bastante.</p>',
        'Primera mitad del renglón largo que sigue siendo largo y claro '
            '[1234567890 nota al pie extra] '
            'y segunda mitad del renglón que sigue y sigue bastante.',
      );

      expect(
        picked(a, 'segunda mitad del renglón'),
        'segunda mitad del renglón',
      );
      expect(picked(a, 'Primera mitad del'), 'Primera mitad del');
    });

    test('nada seleccionado, o fuera del texto', () {
      final a = align(body, content);

      expect(a.contentRangeOf(5, 5), isNull);
      expect(a.contentRangeOf(-5, 0), isNull);
      expect(a.contentRangeOf(9999, 10000), isNull);
    });
  });

  group('de un resaltado a la página', () {
    const content = 'Intro.\n\nLa **revolución** industrial cambió todo.';
    const body =
        '<h1>Intro del sitio</h1><p>La <b>revolución</b> industrial '
        'cambió todo.</p>';

    test('el tramo de la página que cubre un resaltado', () {
      final a = align(body, content);
      final start = content.indexOf('industrial');
      final end = start + 'industrial cambió'.length;

      final ranges = a.pageRangesOf(start, end);

      expect(
        [for (final r in ranges) a.pageText.substring(r.start, r.end)],
        ['industrial cambió'],
      );
    });

    test('cruzando etiquetas, un solo tramo seguido', () {
      final a = align(body, content);
      final start = content.indexOf('La **');
      final end = content.indexOf(' industrial');

      final ranges = a.pageRangesOf(start, end);

      expect(
        [for (final r in ranges) a.pageText.substring(r.start, r.end)],
        ['La revolución'],
      );
    });

    test('con el punto del final y las comillas pegadas', () {
      final a = align(
        '<p>Dijo: “Hola mundo” ahora mismo.</p>',
        'Dijo: “Hola mundo” ahora mismo.',
      );
      final start = a.content.indexOf('“');
      final end = a.content.indexOf('mismo.') + 'mismo.'.length;

      final ranges = a.pageRangesOf(start, end);

      expect(
        [for (final r in ranges) a.pageText.substring(r.start, r.end)],
        ['“Hola mundo” ahora mismo.'],
      );
    });

    test('lo que el extraído tiene y la página no parte el tramo', () {
      const text = 'Mirá [el sitio](https://x.org/a) hoy.';
      final a = align(
        '<p>Mirá <a href="https://x.org/a">el sitio</a> hoy.</p>',
        text,
      );

      final ranges = a.pageRangesOf(0, text.length);

      expect(ranges, hasLength(1));
      expect(
        a.pageText.substring(ranges.single.start, ranges.single.end),
        'Mirá el sitio hoy.',
      );
    });

    test('lo que no está en la página no da ningún tramo', () {
      final a = align(
        '<p>Solo esto está en la página.</p>',
        'Solo esto está en la página.\n\nEsto no aparece nunca en ella.',
      );
      final start = a.content.indexOf('Esto no');

      expect(a.pageRangesOf(start, a.content.length), isEmpty);
    });

    test('ida y vuelta: lo que se pinta se vuelve a seleccionar igual', () {
      final a = align(body, content);
      final start = content.indexOf('revolución');
      final end = start + 'revolución** industrial cambió'.length;

      final ranges = a.pageRangesOf(start, end);
      final back = a.contentRangeOf(ranges.single.start, ranges.single.end);

      expect(back, (start: start, end: end));
    });
  });

  group('la selección que dice el navegador', () {
    test('coincide si son las letras de ese tramo, con otro espaciado', () {
      final a = align(
        '<p>Una frase\n   con saltos.</p>',
        'Una frase con saltos.',
      );
      final range = onPage(a, 'Una frase\n   con saltos.');

      expect(a.agrees(range.start, range.end, 'Una frase con saltos.'), isTrue);
    });

    test('con algo escondido adentro que el navegador no cuenta, también', () {
      final a = align(
        '<p>Una frase <span style="display:none">escondida</span>con '
            'saltos largos de verdad.</p>',
        'Una frase con saltos largos de verdad.',
      );
      final range = onPage(
        a,
        'Una frase escondidacon saltos largos de verdad.',
      );

      expect(
        a.agrees(
          range.start,
          range.end,
          'Una frase con saltos largos de verdad.',
        ),
        isTrue,
      );
    });

    test('con otro texto, no: no se habla de la misma página', () {
      final a = align('<p>Una frase cualquiera.</p>', 'Una frase cualquiera.');
      final range = onPage(a, 'Una frase');

      expect(a.agrees(range.start, range.end, 'Otra cosa distinta'), isFalse);
      expect(a.agrees(range.start, range.end, ''), isFalse);
    });

    test('lo que el navegador cuenta de menos —casi nada— tampoco', () {
      final a = align('<p>Una frase cualquiera larga.</p>', 'Una frase.');
      final range = onPage(a, 'Una frase cualquiera larga.');

      expect(a.agrees(range.start, range.end, 'Una'), isFalse);
    });
  });

  group('el texto de la página es el mismo después de marcarla', () {
    // La app cuenta posiciones sobre este texto, y la página las cuenta sobre
    // el suyo: partir los textos para marcar oraciones y palabras no los
    // puede cambiar.
    String pageTextOf(Document document) {
      const opaque = {
        'script', 'style', 'noscript', 'template', 'textarea', 'select',
        'option', 'title', 'svg', 'math', //
      };
      final out = StringBuffer();
      void walk(Node node) {
        for (final child in node.nodes) {
          if (child is Text) {
            out.write(child.data);
          } else if (child is Element && !opaque.contains(child.localName)) {
            walk(child);
          }
        }
      }

      walk(document.body!);
      return out.toString();
    }

    test('la copia para estudiar no lleva nada marcado adentro (F39)', () {
      const content = 'La **revolución** industrial cambió todo. Después, más.';
      final shown = showArchivedPage(
        '<html><head><title>Un título</title></head><body>'
        '<nav>Menú</nav>\n<p>La <b>revolución</b> industrial cambió '
        'todo.</p>\n<script>var x = 1;</script>'
        '<noscript><p>Sin programas</p></noscript>'
        '<p>Después, <i>más</i>.</p></body></html>',
        study: (
          content: content,
          colors: (
            summary: 0xFF00FF00,
            synthesis: 0xFF0000FF,
            keyword: 0xFFFF0000,
            summaryLine: 0xFF008800,
          ),
        ),
      );

      expect(shown.html, isNot(contains('<mark')));
      final after = pageTextOf(html_parser.parse(shown.html));
      expect(after, shown.alignment!.pageText);
      expect(after, contains('Sin programas'));
      expect(after, isNot(contains('var x')));
    });

    test('sin texto no hay correspondencia', () {
      expect(showArchivedPage('<p>Hola</p>').alignment, isNull);
    });
  });

  group('lo que la página y la app se dicen', () {
    test('el pedido para pintar: los tramos, el color y el estilo', () {
      final script = archivedPageMarksScript([
        (
          id: 'a',
          ranges: const [(start: 3, end: 9), (start: 20, end: 25)],
          color: 0xFFFFCC8A,
          underline: false,
        ),
        (
          id: 'b',
          ranges: const [(start: 0, end: 4)],
          color: 0xFFB36B00,
          underline: true,
        ),
      ]);

      expect(script, startsWith('window.sinapsis && window.sinapsis.marks('));
      final json =
          jsonDecode(
                script.substring(
                  script.indexOf('marks(') + 6,
                  script.length - 2,
                ),
              )
              as List<dynamic>;
      expect(json, [
        {
          'id': 'a',
          'ranges': [
            [3, 9],
            [20, 25],
          ],
          'color': '#ffcc8a',
          'underline': false,
        },
        {
          'id': 'b',
          'ranges': [
            [0, 4],
          ],
          'color': '#b36b00',
          'underline': true,
        },
      ]);
    });

    test('una selección nueva, con dónde está', () {
      final event = parseArchivedPageEvent(
        jsonEncode({
          't': 'sel',
          'a': 10,
          'b': 24,
          'text': 'unas palabras',
          'rect': [10.5, 20, 110, 44.25],
          'vw': 360,
        }),
      );

      expect(event, isA<ArchivedPageSelected>());
      final selected = event! as ArchivedPageSelected;
      expect(
        (selected.start, selected.end, selected.text),
        (10, 24, 'unas palabras'),
      );
      expect(selected.bounds, (
        left: 10.5,
        top: 20.0,
        right: 110.0,
        bottom: 44.25,
      ));
      expect(selected.viewWidth, 360);
    });

    test('ya no hay selección, o se tocó un resaltado', () {
      expect(
        parseArchivedPageEvent(jsonEncode({'t': 'sel', 'empty': true})),
        isA<ArchivedPageDeselected>(),
      );
      final tap = parseArchivedPageEvent(jsonEncode({'t': 'tap', 'id': 'h-1'}));
      expect((tap! as ArchivedPageMarkTapped).id, 'h-1');
    });

    test('lo que avisa para seguir lo que se lee en voz alta: que la '
        'persona la movió, que lo que suena llegó solo a la vista y por dónde '
        'va la vista', () {
      expect(
        parseArchivedPageEvent(jsonEncode({'t': 'moved'})),
        isA<ArchivedPageMoved>(),
      );
      expect(
        parseArchivedPageEvent(jsonEncode({'t': 'seen'})),
        isA<ArchivedPageReadingSeen>(),
      );
      final view = parseArchivedPageEvent(jsonEncode({'t': 'view', 'at': 42}));
      expect((view! as ArchivedPageViewed).position, 42);
      expect(
        parseArchivedPageEvent(jsonEncode({'t': 'view', 'at': 'x'})),
        isNull,
      );
    });

    test('lo que no se entiende se ignora', () {
      expect(parseArchivedPageEvent('no es json'), isNull);
      expect(parseArchivedPageEvent('[1,2]'), isNull);
      expect(parseArchivedPageEvent(jsonEncode({'t': 'otra'})), isNull);
      expect(
        parseArchivedPageEvent(jsonEncode({'t': 'sel', 'a': 'x'})),
        isNull,
      );
    });

    test('la página que se muestra lleva el programa y el estilo de los '
        'resaltados: lo de adentro, encima', () {
      final shown = showableArchivedPage(
        '<html><head></head><body><p>Hola mundo largo.</p></body></html>',
        study: (
          content: 'Hola mundo largo.',
          colors: (
            summary: 0xFF00FF00,
            synthesis: 0xFF0000FF,
            keyword: 0xFFFF0000,
            summaryLine: 0xFF008800,
          ),
        ),
      );
      final document = html_parser.parse(shown);

      final css = document.getElementById('sinapsis-study')!.text;
      expect(css, contains('.sn-hf{color:#000!important}'));
      // Las palabras clave, todas, estén o no en una oración resaltada; y
      // con el resumen y la síntesis prendidos, la síntesis encima (F39).
      expect(css, contains('html.sn-kw mark.sn-k{background:#ff0000'));
      expect(css, isNot(contains('mark.sn-summary.sn-k')));
      expect(
        css.indexOf('html.sn-l-synthesis mark.sn-synthesis{'),
        greaterThan(css.indexOf('html.sn-l-summary mark.sn-summary{')),
      );
      expect(css, isNot(contains('.sn-hu{background')));
      final script = document.getElementById('sinapsis-study-script')!.text;
      expect(script, contains('marks: function (items)'));
      // De afuera hacia adentro: el resumen, la síntesis, los de la persona
      // y las palabras clave, que se ven encima de todo (F39).
      final order = [
        "markOf('summary')",
        "markOf('synthesis')",
        'spanOf(hand[k])',
        "markOf('k')",
      ].map(script.indexOf).toList();
      expect(order, everyElement(greaterThan(0)));
      expect([...order]..sort(), order);
      expect(script, contains('document.caretRangeFromPoint(x, y)'));
      expect(script, contains('document.caretPositionFromPoint(x, y)'));
      expect(script, contains("t: 'tap'"));
      expect(script, contains('SinapsisMarks'));
      expect(archivedPageMarksChannel, 'SinapsisMarks');
    });

    test('lo que se lee en voz alta va en una capa aparte, por encima de '
        'todo, y se vuelve a pintar después de cada repintada', () {
      final shown = showableArchivedPage(
        '<html><head></head><body><p>Hola mundo largo.</p></body></html>',
        study: (
          content: 'Hola mundo largo.',
          colors: (summary: 0, synthesis: 0, keyword: 0, summaryLine: 0),
        ),
      );
      final script = html_parser
          .parse(shown)
          .getElementById('sinapsis-study-script')!
          .text;

      expect(script, contains('reading: function (state)'));
      // Un resaltado del navegador, sin tocar la página; donde no lo hay, una
      // marca que va adentro de todo lo demás.
      expect(script, contains("CSS.highlights.set('sn-reading', highlight)"));
      expect(script, contains('::highlight(sn-reading){background-color:'));
      expect(script, contains("paint(each(reading.ranges), markOf('r'))"));
      expect(script, contains('mark.sn-r{background:'));
      final repaint = script.substring(script.indexOf('function repaint()'));
      expect(
        repaint.indexOf('paintReading();'),
        greaterThan(
          repaint.indexOf("paint(each(study.keyword), markOf('k'));"),
        ),
      );
      // Sigue con lo que se ve de verdad —con zoom— y avisa lo que la
      // persona hace.
      expect(script, contains('window.visualViewport'));
      expect(script, contains("behavior: reading.smooth ? 'smooth' : 'auto'"));
      expect(script, contains("post({t: 'moved'})"));
      expect(script, contains("post({t: 'seen'})"));
      expect(script, contains("post({t: 'view', at:"));
    });
  });
}
