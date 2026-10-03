import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_organize/domain/services/text_parts.dart';

void main() {
  group('splitIntoParts', () {
    test('un texto corto queda en un solo tramo', () {
      expect(splitIntoParts('Hola.', maxChars: 100), [
        const TextPart(start: 0, text: 'Hola.'),
      ]);
      expect(splitIntoParts('', maxChars: 100), isEmpty);
    });

    test('los tramos, juntos, son el texto entero y ninguno se pasa', () {
      final text = List.generate(
        200,
        (i) => 'Oración número $i del libro.${i % 7 == 0 ? '\n\n' : ' '}',
      ).join();

      final parts = splitIntoParts(text, maxChars: 300);

      expect(parts.map((p) => p.text).join(), text);
      expect(parts.every((p) => p.text.length <= 300), isTrue);
      for (var i = 1; i < parts.length; i++) {
        expect(parts[i].start, parts[i - 1].end);
      }
    });

    test('corta al final de un párrafo si hay uno en la segunda mitad', () {
      final text = '${'a' * 60}\n\n${'b' * 60}';

      final parts = splitIntoParts(text, maxChars: 100);

      expect(parts.first.text, '${'a' * 60}\n\n');
      expect(parts.last.text, 'b' * 60);
    });

    test('si no, al final de una oración', () {
      final text = '${'a' * 60}. ${'b' * 60}';

      expect(splitIntoParts(text, maxChars: 100).first.text, '${'a' * 60}. ');
    });

    test('sin ningún separador, corta justo en el tope', () {
      final parts = splitIntoParts('x' * 250, maxChars: 100);

      expect(parts.map((p) => p.text.length), [100, 100, 50]);
    });
  });

  group('spreadIndices', () {
    test('reparte parejo, sin repetir y sin quedarse en los bordes', () {
      expect(spreadIndices(100, 4), [12, 37, 62, 87]);
    });

    test('si alcanza para todos, son todos', () {
      expect(spreadIndices(3, 5), [0, 1, 2]);
      expect(spreadIndices(0, 5), isEmpty);
    });
  });
}
