import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/transcript_timestamps.dart';

void main() {
  group('stripTimestamps (F22)', () {
    test('saca la marca de cada línea y deja cada línea en su lugar', () {
      expect(
        stripTimestamps('[0:00] Te amo Dios\n[0:14] Tu amor nunca me falla'),
        'Te amo Dios\nTu amor nunca me falla',
      );
    });

    test('pasada la hora, también', () {
      expect(stripTimestamps('[1:02:07] Y al final'), 'Y al final');
    });

    test('no toca nada más: ni líneas sin marca, ni sus espacios, ni los '
        'párrafos. La marca se lleva los espacios que la separan del '
        'texto, que son parte de ella', () {
      expect(
        stripTimestamps('[0:05]   con marca\n\n  sin marca  \n[0:09] fin'),
        'con marca\n\n  sin marca  \nfin',
      );
    });

    test('una línea que era solo su marca se va con ella', () {
      expect(
        stripTimestamps('[0:00] algo\n[0:14] \n[0:28] otra'),
        'algo\notra',
      );
    });

    test('un corchete en medio de la línea no es una marca', () {
      expect(stripTimestamps('Nota [1:30] al margen'), 'Nota [1:30] al margen');
    });
  });

  group('hasTimestamps', () {
    test('solo con una línea que empieza con su marca', () {
      expect(hasTimestamps('[2:07] Hola'), isTrue);
      expect(hasTimestamps('Hola [2:07]'), isFalse);
    });
  });

  group('formatTimestamp', () {
    test('con y sin hora', () {
      expect(formatTimestamp(const Duration(seconds: 7)), '0:07');
      expect(
        formatTimestamp(const Duration(hours: 1, minutes: 2, seconds: 7)),
        '1:02:07',
      );
    });
  });
}
