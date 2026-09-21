import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/services/bibliographic_identifiers.dart';

/// Los identificadores con que F15 sabe que dos referencias son la misma obra:
/// deben dar el mismo texto escritos como se escriban, y nada si no valen.
void main() {
  group('DOI', () {
    test('el mismo DOI escrito de todas las formas da un solo texto', () {
      for (final raw in [
        '10.1000/XYZ123',
        'doi:10.1000/xyz123',
        'DOI: 10.1000/xyz123',
        'https://doi.org/10.1000/xyz123',
        'http://dx.doi.org/10.1000/XYZ123',
        'doi.org/10.1000/xyz123',
        '  10.1000/xyz123.  ',
      ]) {
        expect(normalizeDoi(raw), '10.1000/xyz123', reason: raw);
      }
    });

    test('desescapa un DOI que viene de una URL', () {
      expect(
        normalizeDoi('https://doi.org/10.1000%2Fxyz123'),
        '10.1000/xyz123',
      );
    });

    test('un DOI real, con paréntesis y punto y coma', () {
      expect(
        normalizeDoi('10.1016/S0140-6736(20)30183-5'),
        '10.1016/s0140-6736(20)30183-5',
      );
    });

    test('lo que no es un DOI no es nada', () {
      for (final raw in [
        '',
        'no es un doi',
        '10.12/x',
        '1000/xyz',
        '10.1000/',
      ]) {
        expect(normalizeDoi(raw), isNull, reason: raw);
      }
    });

    test('un escape roto no rompe: se deja como estaba', () {
      expect(normalizeDoi('10.1000/100%zz'), '10.1000/100%zz');
    });
  });

  group('ISBN', () {
    test('un ISBN-13 válido, con o sin guiones', () {
      expect(normalizeIsbn('978-0-306-40615-7'), '9780306406157');
      expect(normalizeIsbn('9780306406157'), '9780306406157');
      expect(normalizeIsbn('978 0 306 40615 7'), '9780306406157');
      expect(normalizeIsbn('978-0-06-088328-7'), '9780060883287');
    });

    test('un ISBN-10 se convierte a ISBN-13', () {
      expect(normalizeIsbn('0-306-40615-2'), '9780306406157');
      // Con X de control.
      expect(normalizeIsbn('0-8044-2957-X'), '9780804429573');
      expect(normalizeIsbn('080442957x'), '9780804429573');
    });

    test('el mismo libro da el mismo texto con cualquiera de sus dos ISBN', () {
      expect(
        normalizeIsbn('0-306-40615-2'),
        normalizeIsbn('978-0-306-40615-7'),
      );
    });

    test('acepta el prefijo y lo que venga detrás', () {
      expect(
        normalizeIsbn('ISBN: 978-0-306-40615-7 (tapa dura)'),
        '9780306406157',
      );
      expect(normalizeIsbn('ISBN-13: 978-0-306-40615-7'), '9780306406157');
    });

    test('con dos ISBN toma el primero válido', () {
      expect(
        normalizeIsbn('978-0-306-40615-8 (mal escrito); 0-306-40615-2'),
        '9780306406157',
      );
    });

    test('un dígito de control equivocado no se guarda', () {
      expect(normalizeIsbn('978-0-306-40615-8'), isNull);
      expect(normalizeIsbn('0-306-40615-3'), isNull);
    });

    test('lo que no es un ISBN no es nada', () {
      for (final raw in ['', '12345', 'sin ISBN', '978-0-306']) {
        expect(normalizeIsbn(raw), isNull, reason: raw);
      }
    });
  });

  group('ISSN', () {
    test('con o sin guion, con su dígito de control', () {
      expect(normalizeIssn('0378-5955'), '0378-5955');
      expect(normalizeIssn('03785955'), '0378-5955');
      expect(normalizeIssn('ISSN 0378 5955'), '0378-5955');
    });

    test('el dígito de control puede ser X', () {
      expect(normalizeIssn('2434-561X'), '2434-561X');
      expect(normalizeIssn('2434-561x'), '2434-561X');
    });

    test('un dígito de control equivocado no se guarda', () {
      expect(normalizeIssn('0378-5954'), isNull);
      expect(normalizeIssn('2434-5610'), isNull);
    });

    test('lo que no es un ISSN no es nada', () {
      expect(normalizeIssn(''), isNull);
      expect(normalizeIssn('1234'), isNull);
    });
  });

  group('enlace', () {
    test('ignora mayúsculas, www, puerto, barra, fragmento y rastreo', () {
      expect(
        canonicalUrl(
          'HTTPS://WWW.Example.COM:443/path/?utm_source=x&b=2&a=1#frag',
        ),
        'https://example.com/path?a=1&b=2',
      );
    });

    test('dos enlaces al mismo lugar dan el mismo texto', () {
      expect(
        canonicalUrl('http://example.com/articulo/'),
        canonicalUrl('http://www.example.com/articulo?fbclid=abc'),
      );
    });

    test(
      'la raíz no lleva barra, y un puerto que no es el de siempre se queda',
      () {
        expect(canonicalUrl('https://example.com/'), 'https://example.com');
        expect(
          canonicalUrl('http://example.com:8080/x'),
          'http://example.com:8080/x',
        );
      },
    );

    test('lo que cambia de página no se ignora', () {
      expect(
        canonicalUrl('https://example.com/a?id=1'),
        isNot(canonicalUrl('https://example.com/a?id=2')),
      );
      expect(
        canonicalUrl('https://example.com/a'),
        isNot(canonicalUrl('https://example.com/b')),
      );
    });

    test('no es un enlace web: no es nada', () {
      for (final raw in [
        '',
        'example.com/x',
        'ftp://example.com/x',
        'mailto:a@b.c',
      ]) {
        expect(canonicalUrl(raw), isNull, reason: raw);
      }
    });
  });
}
