import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/features/transform/data/clients/page_urls.dart';

void main() {
  final base = Uri.parse('https://ejemplo.org/blog/nota');

  group('resolvePageUrl', () {
    test('completa lo relativo como un navegador', () {
      expect(
        resolvePageUrl(base, '//cdn.ejemplo.net/a.jpg').toString(),
        'https://cdn.ejemplo.net/a.jpg',
      );
      expect(
        resolvePageUrl(base, '/raiz.pdf').toString(),
        'https://ejemplo.org/raiz.pdf',
      );
      expect(
        resolvePageUrl(base, '../arriba.mp3').toString(),
        'https://ejemplo.org/arriba.mp3',
      );
      expect(
        resolvePageUrl(base, ' fotos/\nb.png ').toString(),
        'https://ejemplo.org/blog/fotos/b.png',
      );
    });

    test('lo que no es web da null', () {
      expect(resolvePageUrl(base, 'mailto:a@b.c'), isNull);
      expect(resolvePageUrl(base, 'javascript:void(0)'), isNull);
      expect(resolvePageUrl(base, 'data:image/png;base64,AAAA'), isNull);
      expect(resolvePageUrl(base, 'file:///etc/passwd'), isNull);
      expect(resolvePageUrl(base, ''), isNull);
    });
  });

  group('absolutizePageUrls', () {
    String absolutized(String body) {
      final document = html_parser.parse('<body>$body</body>');
      absolutizePageUrls(document, base);
      return document.body!.innerHtml;
    }

    test('completa enlaces y fotos; un ancla y lo que no es web quedan', () {
      expect(
        absolutized(
          '<a href="/wiki/Roma">R</a> <a href="#nota">n</a> '
          '<img src="img/a.png" srcset="b.png 2x"> '
          '<a href="mailto:x@y.org">m</a>',
        ),
        '<a href="https://ejemplo.org/wiki/Roma">R</a> <a href="#nota">n</a> '
        '<img src="https://ejemplo.org/blog/img/a.png" '
        'srcset="https://ejemplo.org/blog/b.png 2x"> '
        '<a href="mailto:x@y.org">m</a>',
      );
    });

    test('también lo de la carga perezosa: la foto de verdad de un '
        'cuadradito', () {
      expect(
        absolutized(
          '<img data-src="real.jpg" data-srcset="a.jpg 320w, b.jpg 640w">',
        ),
        '<img data-src="https://ejemplo.org/blog/real.jpg" '
        'data-srcset="https://ejemplo.org/blog/a.jpg 320w, '
        'https://ejemplo.org/blog/b.jpg 640w">',
      );
    });
  });
}
