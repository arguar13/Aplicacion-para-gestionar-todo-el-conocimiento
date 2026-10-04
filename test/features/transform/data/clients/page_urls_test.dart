import 'package:flutter_test/flutter_test.dart';
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
}
