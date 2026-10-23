// Los trozos de HTML y de CSS se pegan tal cual: un espacio de más entre
// etiquetas o reglas cambiaría lo que se prueba.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/archive/html_page_archiver.dart';

import '../../../../support/sample_files.dart';
import '../../../../support/transform_test_doubles.dart';

/// La fidelidad del archivado (F39): lo que hace que la página guardada se
/// vea como la original. Los casos salen de páginas reales grabadas en
/// `test/fixtures/web/` —nunca de la red—.
void main() {
  final png = withSignature([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final wikipedia = Uri.parse('https://es.wikipedia.org/wiki/Imperio_romano');

  Future<String> archive(
    HtmlPageArchiver archiver,
    String html, {
    Uri? uri,
  }) async {
    final bytes = await archiver.archive(
      html,
      baseUri: uri ?? Uri.parse('https://ejemplo.org/articulo'),
    );
    return utf8.decode(bytes!);
  }

  Uint8List text(String value) => Uint8List.fromList(utf8.encode(value));

  group('Wikipedia (Vector 2022), grabada', () {
    final page = File('test/fixtures/web/wikipedia_vector2022.html');
    final css = File('test/fixtures/web/wikipedia_vector2022.css');
    const menuIcon =
        'https://es.wikipedia.org/w/load.php?modules=skins.vector.icons'
        '&image=menu&format=original&lang=es&skin=vector-2022&version=1w2mk';
    const flaskIcon =
        'https://es.wikipedia.org/w/load.php?modules=skins.vector.icons'
        '&image=labFlask&format=original&lang=es&skin=vector-2022'
        '&version=1w2mk';
    final svg = text('<svg xmlns="http://www.w3.org/2000/svg"><path/></svg>');

    FakeResourceFetcher wikipediaFetcher() => FakeResourceFetcher(
      byUrl: {
        'https://es.wikipedia.org/w/load.php?lang=es&modules=skins.vector.styles'
            '&only=styles&skin=vector-2022': text(
          css.readAsStringSync(),
        ),
        'https://es.wikipedia.org/w/load.php?lang=es&modules='
            'ext.gadget.imagenesinfobox&only=styles&skin=vector-2022': text(
          '.infobox{float:right}',
        ),
        'https://es.wikipedia.org/w/load.php?lang=es&modules=site.styles'
            '&only=styles&skin=vector-2022': text(
          '.mw-parser-output .infobox{border:1px solid #a2a9b1}',
        ),
        menuIcon: svg,
        flaskIcon: svg,
        'https://upload.wikimedia.org/wikipedia/commons/thumb/6/6f/'
                'Roman_Empire_117.png/640px-Roman_Empire_117.png':
            png,
      },
    );

    test('con las fotos de sobra, sus hojas de estilo se guardan igual: '
        'el tope de pedidos de las fotos no se las lleva', () async {
      // Wikipedia tiene 63 fotos en el artículo; el tope de 60 se las comía:
      // el `site.styles` —el del cuadro de datos— quedaba sin guardar.
      final fetcher = wikipediaFetcher();
      final archiver = HtmlPageArchiver(fetcher: fetcher, maxRequests: 0);

      final result = await archive(
        archiver,
        page.readAsStringSync(),
        uri: wikipedia,
      );

      expect(result, contains('.infobox{float:right}'));
      expect(result, contains('border:1px solid #a2a9b1'));
      expect(
        result,
        contains('#vector-toc-pinned-container{max-height:200px}'),
      );
      expect(result, isNot(contains('modules=site.styles')));
      expect(result, isNot(contains('modules=skins.vector.styles')));
    });

    test('conserva las clases del <html> y el viewport tal cual', () async {
      final result = await archive(
        HtmlPageArchiver(fetcher: wikipediaFetcher()),
        page.readAsStringSync(),
        uri: wikipedia,
      );

      expect(result, contains('<html class="client-nojs '));
      expect(result, contains('<meta name="viewport" content="width=1120">'));
    });

    test('de los íconos de la hoja baja solo los que la página usa', () async {
      final fetcher = wikipediaFetcher();

      final result = await archive(
        HtmlPageArchiver(fetcher: fetcher),
        page.readAsStringSync(),
        uri: wikipedia,
      );

      // El del menú está en la página; el del frasco, no.
      expect(fetcher.requested.map((u) => u.toString()), contains(menuIcon));
      expect(
        fetcher.requested.map((u) => u.toString()),
        isNot(contains(flaskIcon)),
      );
      expect(result, contains('image/svg+xml;base64,'));
      // El que no se bajó queda con su dirección completa.
      expect(result, contains("url('$flaskIcon')"));
    });
  });

  group('hojas de estilo', () {
    test('una hoja con media conserva su media: una de impresión no manda '
        'en la pantalla', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {
          'https://ejemplo.org/print.css': text('nav{display:none}'),
          'https://ejemplo.org/todo.css': text('p{color:red}'),
        },
      );

      final result = await archive(
        HtmlPageArchiver(fetcher: fetcher),
        '<html><head>'
        '<link rel="stylesheet" href="print.css" media="print">'
        '<link rel="stylesheet" href="todo.css" media="all">'
        '</head><body></body></html>',
      );

      expect(result, contains('<style media="print">nav{display:none}'));
      expect(result, contains('<style>p{color:red}</style>'));
    });

    test('los @import se traen y quedan donde estaban, con su media', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {
          'https://ejemplo.org/css/tema.css': text(
            "@import url('base.css'); @import 'ancho.css' (min-width:800px);"
            'p{margin:0}',
          ),
          'https://ejemplo.org/css/base.css': text(
            "body{background:url('fondo.png')}",
          ),
          'https://ejemplo.org/css/ancho.css': text('h1{font-size:2em}'),
          'https://ejemplo.org/css/fondo.png': png,
        },
      );

      final result = await archive(
        HtmlPageArchiver(fetcher: fetcher),
        '<html><head><link rel="stylesheet" href="css/tema.css">'
        '</head><body></body></html>',
      );

      expect(result, isNot(contains('@import')));
      // En el orden de la hoja, y el fondo resuelto contra la hoja importada.
      expect(
        result,
        contains(
          RegExp(
            r"body\{background:url\('data:image/png;base64,[^']+'\)\}\s*"
            r'@media \(min-width:800px\)\{h1\{font-size:2em\}\}\s*'
            r'p\{margin:0\}',
          ),
        ),
      );
    });

    test('un @import que no se pudo traer queda con su dirección completa, '
        'no relativa a la página', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {
          'https://ejemplo.org/css/tema.css': text("@import 'rota.css';"),
        },
      );

      final result = await archive(
        HtmlPageArchiver(fetcher: fetcher),
        '<html><head><link rel="stylesheet" href="css/tema.css">'
        '</head><body></body></html>',
      );

      expect(
        result,
        contains("@import url('https://ejemplo.org/css/rota.css')"),
      );
    });

    test('una hoja que se carga con rel=preload as=style también se '
        'guarda', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {'https://ejemplo.org/tarde.css': text('p{color:blue}')},
      );

      final result = await archive(
        HtmlPageArchiver(fetcher: fetcher),
        '<html><head><link rel="preload" as="style" href="tarde.css" '
        "onload=\"this.rel='stylesheet'\"></head><body></body></html>",
      );

      expect(result, contains('<style>p{color:blue}</style>'));
    });

    test('lo que nombra una hoja que no se pudo guardar queda con su '
        'dirección completa', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {
          'https://ejemplo.org/css/tema.css': text(
            "body{background:url('../img/fondo.png')}",
          ),
        },
      );

      final result = await archive(
        HtmlPageArchiver(fetcher: fetcher),
        '<html><head><link rel="stylesheet" href="css/tema.css">'
        '</head><body></body></html>',
      );

      expect(result, contains("url('https://ejemplo.org/img/fondo.png')"));
    });
  });

  group('tipografías', () {
    final woff2 = Uint8List.fromList([...ascii.encode('wOF2'), 0, 1, 2, 3]);
    final woff = Uint8List.fromList([...ascii.encode('wOFF'), 0, 1, 2, 3]);

    test('se guarda una sola fuente por regla, la mejor, y la regla sigue '
        'ahí', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {
          'https://ejemplo.org/tema.css': text(
            '@font-face{font-family:Titulo;font-weight:700;'
            "src:url('t.eot'),url('t.woff') format('woff'),"
            "url('t.woff2') format('woff2')}"
            'h1{font-family:Titulo}',
          ),
          'https://ejemplo.org/t.woff2': woff2,
          'https://ejemplo.org/t.woff': woff,
        },
      );

      final result = await archive(
        HtmlPageArchiver(fetcher: fetcher),
        '<html><head><link rel="stylesheet" href="tema.css"></head>'
        '<body><h1>Hola</h1></body></html>',
      );

      expect(
        result,
        contains('@font-face{font-family:Titulo;font-weight:700;'),
      );
      expect(result, contains("url('data:font/woff2;base64,"));
      expect(result, contains("format('woff2')"));
      expect(result, isNot(contains('t.eot')));
      expect(result, isNot(contains('font/woff;')));
      expect(
        fetcher.requested.map((u) => u.path),
        isNot(anyOf(contains('/t.eot'), contains('/t.woff'))),
      );
    });

    test('una regla con unicode-range de letras que la página no tiene se '
        'quita y no se baja (F21)', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {
          'https://ejemplo.org/tema.css': text(
            "@font-face{font-family:Arm;src:url('arm.woff2') format('woff2');"
            'unicode-range:U+0530-058F}'
            "@font-face{font-family:Lat;src:url('lat.woff2') format('woff2');"
            'unicode-range:U+0000-00FF,U+0131}',
          ),
          'https://ejemplo.org/arm.woff2': woff2,
          'https://ejemplo.org/lat.woff2': woff2,
        },
      );

      final result = await archive(
        HtmlPageArchiver(fetcher: fetcher),
        '<html><head><link rel="stylesheet" href="tema.css"></head>'
        '<body><p>Año nuevo</p></body></html>',
      );

      expect(result, contains('font-family:Lat'));
      expect(result, isNot(contains('font-family:Arm')));
      expect(
        fetcher.requested.map((u) => u.path),
        isNot(contains('/arm.woff2')),
      );
    });

    test('un comodín del unicode-range (U+4??) cuenta', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {
          'https://ejemplo.org/tema.css': text(
            "@font-face{font-family:Lat;src:url('lat.woff2');"
            'unicode-range:U+4??}',
          ),
          'https://ejemplo.org/lat.woff2': woff2,
        },
      );

      final result = await archive(
        HtmlPageArchiver(fetcher: fetcher),
        '<html><head><link rel="stylesheet" href="tema.css"></head>'
        '<body><p>Привет</p></body></html>',
      );

      expect(result, contains("url('data:font/woff2;base64,"));
    });

    test('pasado el tope de tipografías, las que sobran se quitan', () async {
      final faces = [
        for (var i = 0; i < 15; i++)
          "@font-face{font-family:F$i;src:url('f$i.woff2')}",
      ].join();
      final fetcher = FakeResourceFetcher(
        byUrl: {
          'https://ejemplo.org/tema.css': text(faces),
          for (var i = 0; i < 15; i++) 'https://ejemplo.org/f$i.woff2': woff2,
        },
      );

      final result = await archive(
        HtmlPageArchiver(fetcher: fetcher),
        '<html><head><link rel="stylesheet" href="tema.css"></head>'
        '<body><p>a</p></body></html>',
      );

      expect('@font-face'.allMatches(result), hasLength(12));
      expect(
        fetcher.requested.where((u) => u.path.endsWith('.woff2')),
        hasLength(12),
      );
    });
  });

  group('el resto de lo que hace a la página', () {
    test('las imágenes de un style="" se incrustan', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {'https://ejemplo.org/portada.png': png},
      );

      final result = await archive(
        HtmlPageArchiver(fetcher: fetcher),
        '<html><body><div style="background-image:url(portada.png);'
        'height:10px"></div></body></html>',
      );

      expect(result, contains("background-image:url('data:image/png;base64,"));
      expect(result, contains('height:10px'));
    });

    test('un SVG se reconoce y se incrusta', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {
          'https://ejemplo.org/logo.svg': text(
            '<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg"/>',
          ),
        },
      );

      final result = await archive(
        HtmlPageArchiver(fetcher: fetcher),
        '<html><body><img src="logo.svg"></body></html>',
      );

      expect(result, contains('src="data:image/svg+xml;base64,'));
    });

    test(
      'lo relativo se resuelve contra el <base href> de la página',
      () async {
        final fetcher = FakeResourceFetcher(
          byUrl: {'https://cdn.ejemplo.org/img/foto.png': png},
        );

        final result = await archive(
          HtmlPageArchiver(fetcher: fetcher),
          '<html><head><base href="https://cdn.ejemplo.org/img/"></head>'
          '<body><img src="foto.png"></body></html>',
        );

        expect(result, contains('src="data:image/png;base64,'));
      },
    );

    test(
      'se saca la política de contenido: bloquearía lo incrustado',
      () async {
        final result = await archive(
          HtmlPageArchiver(fetcher: FakeResourceFetcher()),
          '<html><head><meta http-equiv="Content-Security-Policy" '
          "content=\"default-src 'self'\"></head><body></body></html>",
        );

        expect(result, isNot(contains('Content-Security-Policy')));
      },
    );
  });
}
