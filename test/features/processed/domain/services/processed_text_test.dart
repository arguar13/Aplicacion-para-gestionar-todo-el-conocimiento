import 'dart:isolate';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';

String _isolateName(int _) => Isolate.current.debugName ?? '';

/// Las páginas del texto de un documento procesado, las palabras y el hilo
/// en que se hace lo pesado (F41).
void main() {
  String randomText(Random random, int length) {
    const pieces = ['palabra', ' ', '. ', '\n\n', 'ñandú', '\n', 'x'];
    final buffer = StringBuffer();
    while (buffer.length < length) {
      buffer.write(pieces[random.nextInt(pieces.length)]);
    }
    return buffer.toString().substring(0, length);
  }

  group('las páginas', () {
    test('juntas son el texto entero, sin perder ni repetir nada', () {
      final random = Random(41);
      for (var round = 0; round < 200; round++) {
        final text = randomText(random, random.nextInt(40000));
        final pages = processedTextPages(text);
        expect(pages.map((p) => p.text).join(), text);
        var at = 0;
        for (final page in pages) {
          expect(page.start, at);
          expect(page.text.length, lessThanOrEqualTo(kProcessedTextPageChars));
          expect(page.text, isNotEmpty);
          at = page.end;
        }
      }
    });

    test('un texto vacío no tiene páginas', () {
      expect(processedTextPages(''), isEmpty);
    });

    test('alrededor de lo excluido son exactamente el resto', () {
      final random = Random(7);
      for (var round = 0; round < 200; round++) {
        final text = randomText(random, 1 + random.nextInt(30000));
        final cuts = [
          for (var i = 0; i < 4; i++) random.nextInt(text.length + 1),
        ]..sort();
        final excluded = [
          (start: cuts[0], end: cuts[1]),
          (start: cuts[2], end: cuts[3]),
        ];
        final pages = processedTextPages(text, excluded: excluded);
        final kept = StringBuffer();
        for (final page in pages) {
          expect(text.substring(page.start, page.end), page.text);
          for (final range in excluded) {
            expect(
              page.end <= range.start || page.start >= range.end,
              isTrue,
              reason: 'una página no pisa lo excluido',
            );
          }
          kept.write(page.text);
        }
        final rest =
            text.substring(0, cuts[0]) +
            text.substring(cuts[1], cuts[2]) +
            text.substring(cuts[3]);
        expect(kept.toString(), rest);
      }
    });

    test('excluir una página entera deja las demás como estaban', () {
      final text = randomText(Random(3), 50000);
      final pages = processedTextPages(text);
      for (var i = 0; i < pages.length; i++) {
        final around = processedTextPages(
          text,
          excluded: [(start: pages[i].start, end: pages[i].end)],
        );
        expect(around, [...pages]..removeAt(i));
      }
    });
  });

  test('cuenta palabras como tramos entre espacios', () {
    expect(processedWordCount(''), 0);
    expect(processedWordCount('  una  dos\ttres\n\ncuatro '), 4);
    expect(processedWordCount('sola'), 1);
    expect(processedWordCount('a b'), 2);
  });

  group('lo pesado', () {
    test('un texto corto se hace acá, uno largo en otro hilo', () async {
      final here = Isolate.current.debugName ?? '';

      expect(
        await runProcessedWork(_isolateName, 0, size: kProcessedInlineChars),
        here,
      );
      expect(
        await runProcessedWork(
          _isolateName,
          0,
          size: kProcessedInlineChars + 1,
        ),
        isNot(here),
      );
    });
  });

  group('el id del procesado de una fuente', () {
    test('es siempre el mismo para la misma fuente, y otro para otra', () {
      expect(processedDocumentIdFor('libro'), processedDocumentIdFor('libro'));
      expect(
        processedDocumentIdFor('libro'),
        isNot(processedDocumentIdFor('libro2')),
      );
      expect(processedDocumentIdFor('libro'), isNot('libro'));
    });

    test('es un UUID, fijo entre versiones', () {
      expect(
        processedDocumentIdFor('libro'),
        matches(
          RegExp(
            '^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}$',
          ),
        ),
      );
      // Cambiarlo dejaría dos procesados de la misma fuente entre una versión
      // de la app y la siguiente.
      expect(processedDocumentIdFor('fuente-de-prueba'), _knownId);
    });
  });
}

/// El id de `fuente-de-prueba`, tal como sale hoy.
const _knownId = 'f8944eef-cbae-54a7-8249-0eb66b3bd696';
