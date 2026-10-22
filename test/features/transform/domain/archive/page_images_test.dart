import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/features/transform/domain/archive/page_images.dart';

void main() {
  Element img(String html) =>
      html_parser.parse('<body>$html</body>').querySelector('img')!;

  group('parseSrcset', () {
    test('descriptores de densidad y de ancho', () {
      expect(parseSrcset('a.jpg 1x, b.jpg 2x'), [
        (url: 'a.jpg', descriptor: '1x'),
        (url: 'b.jpg', descriptor: '2x'),
      ]);
      expect(parseSrcset(' a.jpg 320w ,b.jpg 640w'), [
        (url: 'a.jpg', descriptor: '320w'),
        (url: 'b.jpg', descriptor: '640w'),
      ]);
    });

    test('una dirección con comas adentro no se parte', () {
      expect(parseSrcset('https://cdn/w_640,h_480/f.jpg 640w, x.jpg'), [
        (url: 'https://cdn/w_640,h_480/f.jpg', descriptor: '640w'),
        (url: 'x.jpg', descriptor: ''),
      ]);
    });

    test('una sola dirección sin descriptor', () {
      expect(parseSrcset('solo.jpg'), [(url: 'solo.jpg', descriptor: '')]);
      expect(parseSrcset(''), isEmpty);
    });
  });

  group('la mejor de un srcset, para leer', () {
    String? best(String? srcset) =>
        bestSrcsetCandidate(srcset, size: ImageSize.screen);

    test('por ancho, la más grande que entra', () {
      expect(
        best('a.jpg 320w, b.jpg 1024w, c.jpg 1600w, d.jpg 2400w'),
        'c.jpg',
      );
    });

    test('si todas son más grandes, la más chica', () {
      expect(best('d.jpg 2400w, e.jpg 3000w'), 'd.jpg');
    });

    test('por densidad, hasta 2x; sin nada, es 1x', () {
      expect(best('a.jpg, b.jpg 2x, c.jpg 3x'), 'b.jpg');
      expect(best('c.jpg 3x, d.jpg 4x'), 'c.jpg');
    });

    test('un ancho le gana a una densidad: dice cuánto mide', () {
      expect(best('a.jpg 3x, b.jpg 800w'), 'b.jpg');
      expect(best('a.jpg 2000w, b.jpg 1x'), 'a.jpg');
    });

    test('una dirección con comas adentro no se parte', () {
      expect(
        best('https://x.org/w_300,h_200/f.jpg 300w'),
        'https://x.org/w_300,h_200/f.jpg',
      );
    });

    test('un dato incrustado no cuenta, y vacío no hay ninguna', () {
      expect(best('data:image/gif;base64,R0 1x'), isNull);
      expect(best(''), isNull);
      expect(best(null), isNull);
    });
  });

  test('la mejor de un srcset, para bajar: la más grande, sin tope', () {
    String? best(String srcset) =>
        bestSrcsetCandidate(srcset, size: ImageSize.largest);

    expect(best('a.jpg 320w, d.jpg 2400w, b.jpg 1024w'), 'd.jpg');
    expect(best('a.jpg, c.jpg 3x, b.jpg 2x'), 'c.jpg');
  });

  group('la foto de verdad', () {
    String? best(String html) =>
        bestImageSource(img(html), size: ImageSize.screen);

    test('la de la carga perezosa antes que el cuadradito del src', () {
      expect(
        best('<img src="data:image/gif;base64,R0" data-src="real.jpg">'),
        'real.jpg',
      );
    });

    test('la de la carga perezosa antes que el srcset borroso de al lado', () {
      expect(
        best('<img srcset="borrosa.jpg 1x" data-src="real.jpg">'),
        'real.jpg',
      );
      expect(
        best('<img srcset="borrosa.jpg 1x" data-srcset="real.jpg 800w">'),
        'real.jpg',
      );
    });

    test('un cuadradito puesto en la carga perezosa no cuenta', () {
      expect(
        best('<img src="real.jpg" data-src="data:image/gif;base64,R0">'),
        'real.jpg',
      );
    });

    test('la del srcset antes que el src', () {
      expect(
        best('<img src="chica.jpg" srcset="grande.jpg 2x">'),
        'grande.jpg',
      );
    });

    test('la de un <source> de su <picture>', () {
      expect(
        best(
          '<picture><source srcset="f.webp 800w"><img src="f.jpg"></picture>',
        ),
        'f.webp',
      );
    });

    test('si no tiene otra, su src; un dato o nada, ninguna', () {
      expect(best('<img src="f.jpg">'), 'f.jpg');
      expect(best('<img src="data:image/png;base64,AAAA">'), isNull);
      expect(best('<img alt="x">'), isNull);
    });

    test('para bajar, la más grande que ofrece', () {
      expect(
        bestImageSource(
          img('<img src="a.jpg" srcset="b.jpg 800w, c.jpg 2400w">'),
          size: ImageSize.largest,
        ),
        'c.jpg',
      );
    });
  });

  test('una foto resuelta queda sola: sin alternativas ni <source>', () {
    final image = img(
      '<picture><source srcset="f.webp"><img src="f.jpg" srcset="g.jpg 2x" '
      'sizes="50vw" data-src="h.jpg" alt="Una foto"></picture>',
    );

    settleImage(image, 'data:image/png;base64,AAA');

    expect(image.attributes, {
      'src': 'data:image/png;base64,AAA',
      'alt': 'Una foto',
    });
    expect(image.parent!.querySelector('source'), isNull);
  });

  group('las fotos de una página ya archivada', () {
    final saved = 'data:image/png;base64,${'A' * 600}';

    String show(String body) {
      final document = html_parser.parse('<body>$body</body>');
      showArchivedImages(document);
      return document.body!.innerHtml;
    }

    test('la guardada queda, sin el srcset que el teléfono preferiría', () {
      final result = show('<img src="$saved" srcset="g.jpg 2x">');

      expect(result, contains(saved));
      expect(result, isNot(contains('srcset')));
    });

    test('la de una carga perezosa pasa a su foto de verdad', () {
      final result = show(
        '<img src="data:image/gif;base64,R0lGOD" data-src="real.jpg">',
      );

      expect(result, contains('src="real.jpg"'));
      expect(result, isNot(contains('R0lGOD')));
    });

    test('una sin alternativas no cambia', () {
      expect(show('<img src="f.jpg" alt="x">'), '<img src="f.jpg" alt="x">');
    });
  });
}
