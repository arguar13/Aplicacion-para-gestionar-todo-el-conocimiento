import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_study.dart';

void main() {
  const colors = (
    summary: 0xFFC8F2C2,
    synthesis: 0xFFBDE6FF,
    keyword: 0xFFFFB3D9,
  );

  Document show(
    String body, {
    required String content,
    required List<ArchivedPageSentence> sentences,
  }) => html_parser.parse(
    showableArchivedPage(
      '<html><head></head><body>$body</body></html>',
      study: (content: content, sentences: sentences, colors: colors),
    ),
  );

  ArchivedPageSentence summary(String content, String sentence) {
    final start = content.indexOf(sentence);
    return (
      start: start,
      end: start + sentence.length,
      kind: StudyMarkKind.summary,
    );
  }

  /// El texto de la página que quedó con [selector], junto.
  String textOf(Document page, String selector) =>
      page.querySelectorAll(selector).map((e) => e.text).join();

  group('las oraciones, sobre la página', () {
    test('se encuentran aunque crucen etiquetas y el Markdown tenga sus '
        'marcas: queda envuelta entera, con el punto', () {
      const content = 'Intro.\n\nLa **revolución** industrial cambió todo.';
      final page = show(
        '<nav>Menú</nav><p>Intro.</p>'
        '<p>La <b>revolución</b> industrial cambió todo.</p>',
        content: content,
        sentences: [
          summary(content, 'La **revolución** industrial cambió todo.'),
        ],
      );

      expect(
        textOf(page, 'mark.sn-summary'),
        'La revolución industrial cambió todo.',
      );
      expect(page.querySelector('b mark.sn-summary')?.text, 'revolución');
      expect(page.querySelector('nav mark'), isNull);
    });

    test('cada palabra lleva su lugar en el texto, para tocarla y para '
        'marcarla como clave', () {
      const content = 'La revolución industrial.';
      final page = show(
        '<p>La revolución industrial.</p>',
        content: content,
        sentences: [summary(content, content)],
      );

      final words = {
        for (final w in page.querySelectorAll('mark.sn-w'))
          w.text: w.attributes['data-o'],
      };
      expect(words, {'La': '0', 'revolución': '3', 'industrial': '14'});
    });

    test('una palabra cortada por una etiqueta lleva el mismo lugar en los '
        'dos pedazos', () {
      const content = 'Una palabra partida.';
      final page = show(
        '<p>Una pala<i>bra</i> partida.</p>',
        content: content,
        sentences: [summary(content, content)],
      );

      final pieces = page
          .querySelectorAll('mark.sn-w')
          .where((w) => w.attributes['data-o'] == '4')
          .map((w) => w.text);
      expect(pieces, ['pala', 'bra']);
    });

    test('una del resumen y de la síntesis lleva las dos clases', () {
      const content = 'Una sola idea.';
      final page = show(
        '<p>Una sola idea.</p>',
        content: content,
        sentences: [
          summary(content, content),
          (start: 0, end: content.length, kind: StudyMarkKind.synthesis),
        ],
      );

      expect(textOf(page, 'mark.sn-summary.sn-synthesis'), contains('idea'));
    });

    test('la dirección de un enlace del Markdown no está en la página, y no '
        'impide encontrar la oración', () {
      const content = 'Mirá [el sitio](https://x.org/a) hoy.';
      final page = show(
        '<p>Mirá <a href="https://x.org/a">el sitio</a> hoy.</p>',
        content: content,
        sentences: [summary(content, content)],
      );

      expect(textOf(page, 'mark.sn-summary'), 'Mirá el sitio hoy.');
    });

    test('el texto repetido —el título arriba, en el menú— se busca en '
        'orden: la segunda oración después de la primera', () {
      const content = 'Primero esto. Después lo otro.';
      final page = show(
        '<header>Después lo otro.</header> '
        '<p>Primero esto. Después lo otro.</p>',
        content: content,
        sentences: [
          summary(content, 'Primero esto.'),
          summary(content, 'Después lo otro.'),
        ],
      );

      expect(page.querySelector('header mark'), isNull);
      expect(textOf(page, 'p mark.sn-summary'), contains('lo otro'));
    });

    test('una que en la página está antes que la anterior también se '
        'encuentra: el texto extraído no siempre sigue el orden de la '
        'página', () {
      const content = 'Va segunda. Va primera.';
      final page = show(
        '<p>Va primera.</p><p>Va segunda.</p>',
        content: content,
        sentences: [
          summary(content, 'Va segunda.'),
          summary(content, 'Va primera.'),
        ],
      );

      expect(textOf(page, 'mark.sn-summary'), 'Va primera.Va segunda.');
    });

    test('lo que no es de una oración queda como texto, sin envolver', () {
      const content = 'Antes. La frase.';
      final page = show(
        '<p>Antes. La frase.</p>',
        content: content,
        sentences: [summary(content, 'La frase.')],
      );

      expect(textOf(page, 'mark'), 'La frase.');
    });

    test('adentro de lo que no es texto de leer —un desplegable, un campo— '
        'no se marca nada', () {
      const content = 'Hola.';
      final page = show(
        '<select><option>Hola.</option></select>'
        '<textarea>Hola.</textarea><p>Hola.</p>',
        content: content,
        sentences: [summary(content, content)],
      );

      expect(page.querySelector('option mark'), isNull);
      expect(page.querySelector('textarea mark'), isNull);
      expect(textOf(page, 'p mark'), 'Hola.');
    });

    test('una que no está en la página se saltea, y las demás se ven', () {
      const content = 'No aparece. Sí aparece.';
      final page = show(
        '<p>Sí aparece.</p>',
        content: content,
        sentences: [
          summary(content, 'No aparece.'),
          summary(content, 'Sí aparece.'),
        ],
      );

      expect(textOf(page, 'mark.sn-summary'), 'Sí aparece.');
    });

    test('los espacios entre bloques no se envuelven: un <mark> entre filas '
        'de una tabla movería cosas', () {
      const content = 'Uno dos';
      final page = show(
        '<table><tr><td>Uno</td>\n<td>dos</td></tr></table>',
        content: content,
        sentences: [summary(content, content)],
      );

      expect(page.querySelectorAll('mark').map((m) => m.text), ['Uno', 'dos']);
    });
  });

  group('la página se ve como hasta ahora, con un solo programa: el de la '
      'app', () {
    final page = show(
      '<script>alert(1)</script> '
      '<noscript><img src="foto.jpg"></noscript> '
      '<a href="javascript:void(0)" onclick="robar()">enlace</a> '
      '<p>Hola.</p>',
      content: 'Hola.',
      sentences: [(start: 0, end: 5, kind: StudyMarkKind.summary)],
    );

    test('sin sus programas ni sus atributos on… ni enlaces javascript:', () {
      final scripts = page.querySelectorAll('script');
      expect(scripts.map((s) => s.id), ['sinapsis-study-script']);
      final link = page.querySelector('a')!;
      expect(link.attributes.containsKey('onclick'), isFalse);
      expect(link.attributes.containsKey('href'), isFalse);
    });

    test('lo de <noscript> queda a la vista', () {
      expect(page.querySelector('noscript'), isNull);
      expect(page.querySelector('img')?.attributes['src'], 'foto.jpg');
    });

    test('con los colores de resaltador en su hoja', () {
      final css = page.querySelector('#sinapsis-study')!.text;
      expect(css, contains('#c8f2c2'));
      expect(css, contains('#bde6ff'));
      expect(css, contains('#ffb3d9'));
    });
  });

  test('sin nada estudiado, solo se arreglan las fotos: los programas de la '
      'página no se tocan', () {
    final page = html_parser.parse(
      showableArchivedPage(
        '<html><body><script>x()</script>'
        '<img src="data:image/gif;base64,R0" data-src="real.jpg"></body></html>',
      ),
    );

    expect(page.querySelector('script')?.text, 'x()');
    expect(page.querySelector('img')?.attributes['src'], 'real.jpg');
    expect(page.querySelector('#sinapsis-study'), isNull);
  });

  test('lo que se le pide a la página: qué se prende —cada uno por su '
      'lado (F39)— y qué palabras', () {
    Map<String, Object?> state(String script) =>
        jsonDecode(RegExp(r'set\((.*)\);$').firstMatch(script)!.group(1)!)
            as Map<String, Object?>;

    expect(
      state(
        archivedPageStateScript(
          summary: false,
          synthesis: true,
          keywords: true,
          picking: false,
          keywordOffsets: [3, 14],
        ),
      ),
      {
        'summary': false,
        'synthesis': true,
        'keywords': true,
        'picking': false,
        'kw': [3, 14],
      },
    );
    expect(
      state(
        archivedPageStateScript(
          summary: true,
          synthesis: true,
          keywords: false,
          picking: true,
          keywordOffsets: const [],
        ),
      ),
      {
        'summary': true,
        'synthesis': true,
        'keywords': false,
        'picking': true,
        'kw': <Object?>[],
      },
    );
  });
}
