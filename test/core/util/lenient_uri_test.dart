import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/lenient_uri.dart';

/// Las direcciones que trae una página no las controla quien las lee:
/// Wikipedia tiene enlaces con un `%E3%A` suelto, y `Uri.pathSegments` lanza
/// una `FormatException` ante eso.
void main() {
  group('decodePercentLenient', () {
    test('decodifica lo bien escrito', () {
      expect(decodePercentLenient('El%20ni%C3%B1o.xhtml'), 'El niño.xhtml');
      expect(decodePercentLenient('Jes%c3%bas'), 'Jesús');
    });

    test('lo que no tiene % queda igual, con sus acentos', () {
      expect(decodePercentLenient('Teresa de Jesús'), 'Teresa de Jesús');
    });

    test('un % sin sus dos cifras queda como venía, y no corta lo demás', () {
      expect(decodePercentLenient('100%.pdf'), '100%.pdf');
      expect(decodePercentLenient('a%2'), 'a%2');
      expect(decodePercentLenient('a%zzb'), 'a%zzb');
      expect(decodePercentLenient('%'), '%');
      expect(decodePercentLenient('a%20b%'), 'a b%');
    });

    test('bytes que no son UTF-8 no lanzan', () {
      // `%E3%A` es el caso real: un byte de arranque y media cifra.
      expect(() => decodePercentLenient('Teresa%E3%A.pdf'), returnsNormally);
      expect(decodePercentLenient('Teresa%E3%A.pdf'), endsWith('A.pdf'));
      expect(() => decodePercentLenient('%FF%FE'), returnsNormally);
    });

    test('caracteres de más de un código (emoji) pasan enteros', () {
      expect(decodePercentLenient('foto 😀 %41'), 'foto 😀 A');
    });
  });

  group('lastPathSegmentOf', () {
    test('el nombre del archivo, decodificado', () {
      expect(
        lastPathSegmentOf(Uri.parse('https://a.org/x/El%20ni%C3%B1o.pdf')),
        'El niño.pdf',
      );
    });

    test('ignora la barra del final y el vacío', () {
      expect(lastPathSegmentOf(Uri.parse('https://a.org/x/y/')), 'y');
      expect(lastPathSegmentOf(Uri.parse('https://a.org')), isNull);
      expect(lastPathSegmentOf(Uri.parse('https://a.org/')), isNull);
    });

    test('con una dirección mal escrita no lanza, a diferencia de '
        '`Uri.pathSegments`', () {
      final broken = Uri.parse('https://es.wikipedia.org/wiki/Teresa%E3%A.pdf');

      expect(() => broken.pathSegments, throwsFormatException);
      expect(() => lastPathSegmentOf(broken), returnsNormally);
      expect(lastPathSegmentOf(broken), endsWith('A.pdf'));
    });
  });
}
