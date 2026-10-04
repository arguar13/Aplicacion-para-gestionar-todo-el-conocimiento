import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/domain/services/chat_passages.dart';

/// Qué se busca de una pregunta y qué pasaje se cita (F30).
void main() {
  group('questionTerms', () {
    test('saca las palabras vacías y los pedidos del chat', () {
      expect(
        questionTerms('Contame qué dice mi bóveda sobre la religión romana'),
        ['religión', 'romana'],
      );
    });

    test('sin repetidas, sin las cortas, y con los años', () {
      expect(questionTerms('Roma, roma y RÓMA en el año 44 a. C.'), [
        'Roma',
        'año',
        '44',
      ]);
    });

    test('como mucho las pedidas', () {
      expect(questionTerms('alfa beta gamma delta épsilon', max: 3), [
        'alfa',
        'beta',
        'gamma',
      ]);
    });
  });

  group('passageWindow', () {
    test('un texto corto va entero', () {
      expect(passageWindow('Roma.', ['roma']), (start: 0, end: 5));
    });

    test('elige la ventana que junta más palabras distintas', () {
      final text =
          'Roma aparece acá sola. ${'relleno ' * 80}'
          'Acá están Roma y el Senado juntos. ${'cola ' * 80}';

      final window = passageWindow(text, ['senado', 'roma'], maxChars: 120);
      final passage = text.substring(window.start, window.end);

      expect(passage, contains('Roma y el Senado juntos'));
      expect(passage.length, lessThanOrEqualTo(120));
    });

    test('coincide sin acentos ni mayúsculas, como el índice', () {
      final text = '${'x ' * 300}La RELIGIÓN de los romanos. ${'y ' * 300}';

      final window = passageWindow(text, ['religion'], maxChars: 100);

      expect(text.substring(window.start, window.end), contains('RELIGIÓN'));
    });

    test('sin coincidencias, el principio, cortado en una palabra', () {
      final text = 'palabra ' * 200;

      final window = passageWindow(text, ['nada'], maxChars: 50);

      expect(window.start, 0);
      expect(window.end, lessThanOrEqualTo(50));
      expect(
        text.substring(window.start, window.end).trim(),
        endsWith('palabra'),
      );
    });
  });
}
