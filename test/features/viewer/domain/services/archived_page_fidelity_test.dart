// Los trozos de HTML y de CSS se pegan tal cual: un espacio de más entre
// etiquetas o reglas cambiaría lo que se prueba.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/features/viewer/domain/services/archived_page_study.dart';

/// La página archivada se ve como la original (F39). Los casos salen de
/// páginas reales grabadas en `test/fixtures/web/`.
void main() {
  final wikipedia = File('test/fixtures/web/wikipedia_vector2022.html');
  final wikipediaCss = File('test/fixtures/web/wikipedia_vector2022.css');
  const colors = (
    summary: 0xFFC8F2C2,
    synthesis: 0xFFBDE6FF,
    keyword: 0xFFFFB3D9,
    summaryLine: 0xFF2E9A48,
  );

  Document shown(String html, {ArchivedPageStudy? study}) =>
      html_parser.parse(showableArchivedPage(html, study: study));

  group('el estado que un programa de la página le cambia al <html>', () {
    test('Wikipedia: client-nojs pasa a client-js, que es como la página '
        'llega a quien la mira', () {
      final page = shown(wikipedia.readAsStringSync());

      final classes = page.documentElement!.classes;
      expect(classes, contains('client-js'));
      expect(classes, isNot(contains('client-nojs')));
      // Lo demás que dice el servidor, intacto.
      expect(classes, contains('vector-feature-toc-pinned-clientpref-1'));
      expect(classes, contains('skin-theme-clientpref-day'));
    });

    test('la hoja grabada de Wikipedia solo esconde el índice con '
        'client-js', () {
      // La causa del índice abierto arriba de todo: sin la clase, la hoja lo
      // deja en una caja de 200 px en vez de esconderlo.
      final css = wikipediaCss.readAsStringSync();

      expect(
        css,
        contains(
          '.client-js .mw-table-of-contents-container.vector-toc-landmark'
          '{display:none}',
        ),
      );
      expect(
        css,
        contains(
          '.client-nojs.vector-feature-toc-pinned-clientpref-1 '
          '#vector-toc-pinned-container{max-height:200px}',
        ),
      );
      final page = shown(wikipedia.readAsStringSync());
      expect(
        page.querySelector('.client-js .mw-table-of-contents-container'),
        isNotNull,
      );
      expect(
        page.querySelector('.client-nojs .mw-table-of-contents-container'),
        isNull,
      );
    });

    test('con el programa de estudiar pasa lo mismo', () {
      final page = shown(
        wikipedia.readAsStringSync(),
        study: (
          content:
              'El Imperio romano fue el Estado que dominó el Mediterráneo.',
          colors: colors,
        ),
      );

      expect(page.documentElement!.classes, contains('client-js'));
    });

    test('si ningún programa de la página lo cambia, queda como estaba', () {
      // Uno que no toca el <html>, y uno que nombra la clase pero no la
      // pone: ninguno de los dos es el que da vuelta el estado.
      for (final script in [
        'var x = 1;',
        "console.log('client-js');",
        'document.documentElement.className = "otra";',
      ]) {
        final page = shown(
          '<html class="client-nojs"><head><script>$script</script></head>'
          '<body><p>Hola</p></body></html>',
        );

        expect(page.documentElement!.classes, contains('client-nojs'));
        expect(page.documentElement!.classes, isNot(contains('client-js')));
      }
    });

    test('un no-js genérico no se toca: esconder cosas hasta que un programa '
        'las muestre las dejaría escondidas', () {
      final page = shown(
        '<html class="no-js"><head><script>document.documentElement'
        ".className = document.documentElement.className.replace('no-js', "
        "'js');</script></head><body><p>Hola</p></body></html>",
      );

      expect(page.documentElement!.classes, contains('no-js'));
    });
  });

  group('lo que va en un <noscript>', () {
    test('el del <head> —las hojas de quien no tiene JavaScript— se va', () {
      final page = shown(wikipedia.readAsStringSync());

      expect(page.querySelectorAll('noscript'), isEmpty);
      expect(page.querySelector('link[href*="modules=noscript"]'), isNull);
    });

    test('la foto de respaldo de una carga perezosa no repite la que está '
        'al lado', () {
      const html =
          '<html><body><div><img class="lazy" src="data:image/gif;base64,R0lG" '
          'data-src="https://ejemplo.org/foto.jpg">'
          '<noscript><img src="https://ejemplo.org/foto.jpg"></noscript>'
          '</div></body></html>';

      for (final study in [null, (content: 'x', colors: colors)]) {
        final page = shown(html, study: study);

        expect(page.querySelectorAll('img'), hasLength(1), reason: '$study');
      }
    });

    test('una foto que está solo en el <noscript> sigue a la vista al '
        'estudiar', () {
      const html =
          '<html><body><div><p>Texto</p>'
          '<noscript><img src="https://ejemplo.org/sola.jpg"></noscript>'
          '</div></body></html>';

      final page = shown(html, study: (content: 'Texto', colors: colors));

      expect(page.querySelectorAll('img'), hasLength(1));
    });
  });

  group('lo que se agrega para estudiar no mueve nada', () {
    // Propiedades que cambian dónde queda una letra o cuánto ocupa algo.
    const layout = {
      'margin',
      'padding',
      'width',
      'height',
      'display',
      'position',
      'float',
      'border',
      'line-height',
      'font-size',
      'letter-spacing',
      'top',
      'left',
      'right',
      'bottom',
      'min-width',
      'max-width',
      'overflow',
      'transform',
    };

    Iterable<String> propertiesOf(String css) => RegExp(
      r'([a-z-]+)\s*:',
    ).allMatches(css.replaceAll(RegExp(r'\{|\}'), ';')).map((m) => m[1]!);

    test('el estilo que se inyecta no toca márgenes, anchos ni nada de lo '
        'que acomoda', () {
      final page = shown(
        '<html><head></head><body><p>Hola mundo</p></body></html>',
        study: (content: 'Hola mundo', colors: colors),
      );

      final css = page.getElementById('sinapsis-study')!.text;
      final touched = propertiesOf(css).toSet();

      expect(touched.intersection(layout), isEmpty);
    });

    test('lo que se marca no se ve afectado por lo que la página le ponga a '
        '<mark>', () {
      final page = shown(
        '<html><head><style>mark{margin:0 8px;border:2px solid red;'
        'font-weight:bold;display:block}</style></head>'
        '<body><p>Hola mundo</p></body></html>',
        study: (content: 'Hola mundo', colors: colors),
      );

      // `all: unset` en lo marcado: lo de la página para `mark` no entra.
      expect(
        page.getElementById('sinapsis-study')!.text,
        contains('mark.sn-m{all:unset}'),
      );
      // Y lo marcado es lo que pinta el programa, con esa clase (F39).
      expect(
        page.getElementById('sinapsis-study-script')!.text,
        contains("'sn-p sn-m sn-'"),
      );
    });

    test('el texto de la página, letra por letra, es el mismo', () {
      const html =
          '<html><body><p>Hola <b>mundo</b>, esto es una prueba.</p></body>'
          '</html>';

      final plain = shown(html).body!.text;
      final page = shown(
        html,
        study: (content: 'Hola mundo, esto es una prueba.', colors: colors),
      );
      // El programa de la app es un <script>: no es texto de la página.
      page.getElementById('sinapsis-study-script')!.remove();

      expect(page.body!.text, plain);
    });
  });
}
