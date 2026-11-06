import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/markdown_inline.dart';
import 'package:sinapsis/features/ai_organize/domain/services/text_parts.dart';

const _link = 'https://x.org/wiki/Bacteria';

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

  group('splitIntoParts con markdown: true (F46, paso 5b)', () {
    /// Ninguna construcción de [text] partida entre dos de [parts].
    void expectNoneCut(String text, List<TextPart> parts) {
      for (final m in markdownInlinePattern.allMatches(text)) {
        expect(
          parts.where((p) => p.start <= m.start && m.end <= p.end),
          hasLength(1),
          reason: 'partida: «${m[0]}»',
        );
      }
    }

    test(
      'ni en una oración ni en un espacio que caen adentro de un enlace',
      () {
        // Sin párrafo en la segunda mitad: lo de siempre cortaría en «Dr. » o
        // en el espacio de «bacterias purpúreas».
        final text =
            '${'a' * 50} [el Dr. Who y las bacterias purpúreas]($_link) '
            '${'b' * 60}';

        final parts = splitIntoParts(text, maxChars: 100, markdown: true);

        expect(parts.map((p) => p.text).join(), text);
        expectNoneCut(text, parts);
        // Sin la regla, el mismo texto se parte adentro del enlace.
        expect(
          () => expectNoneCut(text, splitIntoParts(text, maxChars: 100)),
          throwsA(isA<TestFailure>()),
        );
      },
    );

    test('un enlace más largo que el tramo va entero, aunque se pase', () {
      final link = '[un documento](https://x.org/${'a' * 300})';
      final text = 'Antes. $link y después.';

      final parts = splitIntoParts(text, maxChars: 100, markdown: true);

      expect(parts.map((p) => p.text).join(), text);
      expect(parts.map((p) => p.text), contains(startsWith(link)));
    });

    test('al azar: juntos son el texto, y solo se pasa del tope lo que mide '
        'una construcción que no entra', () {
      final random = Random(41);
      const pieces = [
        'palabra ',
        'fin. ',
        '[un enlace con texto](https://es.wikipedia.org/wiki/X_(y)) ',
        '**negrita de varias palabras** ',
        '*cursiva. Con punto* ',
        '\n',
        '\n\n',
        'x',
      ];
      for (var round = 0; round < 200; round++) {
        final buffer = StringBuffer();
        for (var i = random.nextInt(200); i > 0; i--) {
          buffer.write(pieces[random.nextInt(pieces.length)]);
        }
        final text = buffer.toString();
        final maxChars = 40 + random.nextInt(200);
        final parts = splitIntoParts(text, maxChars: maxChars, markdown: true);
        expect(parts.map((p) => p.text).join(), text);
        expectNoneCut(text, parts);
        for (final part in parts) {
          if (part.text.length <= maxChars) continue;
          // Si se pasó, es porque termina en una construcción que empezó
          // en su comienzo y no entraba.
          expect(
            markdownInlinePattern.matchAsPrefix(text, part.start)?.end,
            part.end,
          );
        }
      }
    });

    test('un texto sin Markdown se corta exactamente como siempre', () {
      final text = List.generate(
        200,
        (i) => 'Oración número $i del libro.${i % 7 == 0 ? '\n\n' : ' '}',
      ).join();

      expect(
        splitIntoParts(text, maxChars: 300, markdown: true),
        splitIntoParts(text, maxChars: 300),
      );
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
