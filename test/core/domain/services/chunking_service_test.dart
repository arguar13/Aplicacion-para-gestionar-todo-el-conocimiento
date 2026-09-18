import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/services/chunking_service.dart';

void main() {
  const service = ChunkingService();

  /// Ningún corte debería caer en medio de un par subrogado UTF-16: el
  /// último code unit de un fragmento nunca es un high surrogate, y el
  /// primero del fragmento siguiente nunca es un low surrogate sobrante.
  void expectNoSplitSurrogatePairs(List<TextChunk> chunks) {
    for (final chunk in chunks) {
      if (chunk.text.isEmpty) continue;
      final lastUnit = chunk.text.codeUnitAt(chunk.text.length - 1);
      expect(
        lastUnit,
        isNot(inInclusiveRange(0xD800, 0xDBFF)),
        reason: 'un fragmento terminó a mitad de un emoji/carácter compuesto',
      );
    }
  }

  group('reconstrucción byte a byte', () {
    test('un párrafo simple, sin separadores, da un solo fragmento', () {
      const text = 'Una idea completa, sin ninguna línea en blanco.';

      final chunks = service.chunk(text, kind: RenditionKind.plainText);

      expect(chunks, hasLength(1));
      expect(chunkingInvariantHolds(text, chunks), isTrue);
    });

    test('varios párrafos separados por línea en blanco dan varios '
        'fragmentos', () {
      const text =
          'Primer párrafo.\n\nSegundo párrafo, más largo que el primero.'
          '\n\n\nTercero, con tres saltos de línea antes.';

      final chunks = service.chunk(text, kind: RenditionKind.markdown);

      expect(chunks.length, greaterThan(1));
      expect(chunkingInvariantHolds(text, chunks), isTrue);
      for (var i = 0; i < chunks.length; i++) {
        expect(chunks[i].seq, i);
      }
    });

    test('texto con acentos, eñes y emoji fuera del BMP reconstruye exacto '
        'sin cortar ningún carácter compuesto', () {
      const text =
          'Epistemología y política.\n\n'
          'La revolución científica según Kuhn 🔭👨‍🔬.\n\n'
          'Último párrafo, sin nada raro.';

      final chunks = service.chunk(text, kind: RenditionKind.plainText);

      expect(chunkingInvariantHolds(text, chunks), isTrue);
      expectNoSplitSurrogatePairs(chunks);
    });

    test('una transcripción [mm:ss] que cruza el umbral de 75s se agrupa en '
        'más de un fragmento, reconstruyendo exacto', () {
      final buffer = StringBuffer();
      for (var i = 0; i < 12; i++) {
        final seconds = i * 10;
        final minutes = seconds ~/ 60;
        final secs = (seconds % 60).toString().padLeft(2, '0');
        buffer.writeln('[$minutes:$secs] Línea número $i de la charla.');
      }
      // Sin el último salto de línea, como hace `formatTranscript`.
      final text = buffer.toString().trimRight();

      final chunks = service.chunk(text, kind: RenditionKind.markdown);

      expect(chunks.length, greaterThan(1));
      expect(chunkingInvariantHolds(text, chunks), isTrue);
      expect(chunks.first.startMs, 0);
      // Cada fragmento salvo el último sabe hasta dónde llega.
      for (final chunk in chunks.sublist(0, chunks.length - 1)) {
        expect(chunk.endMs, isNotNull);
      }
      expect(chunks.last.endMs, isNull);
    });

    test(
      'una transcripción con marcas [h:mm:ss] de más de una hora reconstruye '
      'exacto',
      () {
        const text =
            '[1:02:07] Ya pasada la primera hora.\n'
            '[1:02:40] Sigue la charla acá.\n'
            '[1:05:00] Y termina en este punto.';

        final chunks = service.chunk(text, kind: RenditionKind.markdown);

        expect(chunkingInvariantHolds(text, chunks), isTrue);
        expect(chunks.first.startMs, (1 * 3600 + 2 * 60 + 7) * 1000);
      },
    );

    test('una nota de bloques con los seis tipos reconstruye exacto, un '
        'fragmento por bloque', () {
      final blocks = <ContentBlock>[
        const ContentBlock.heading(text: 'Título'),
        const ContentBlock.paragraph(text: 'Un párrafo cualquiera.'),
        const ContentBlock.bulletItem(text: 'Primer punto'),
        const ContentBlock.numberedItem(text: 'Paso uno'),
        const ContentBlock.checklistItem(text: 'Por hacer'),
        const ContentBlock.quote(text: 'Una cita textual.'),
      ];
      final text = encodeContentBlocks(blocks);

      final chunks = service.chunk(text, kind: RenditionKind.blocks);

      expect(chunks, hasLength(blocks.length));
      expect(chunkingInvariantHolds(text, chunks), isTrue);
      for (var i = 0; i < chunks.length; i++) {
        expect(chunks[i].seq, i);
      }
    });

    test('texto vacío da cero fragmentos', () {
      final chunks = service.chunk('', kind: RenditionKind.plainText);

      expect(chunks, isEmpty);
      expect(chunkingInvariantHolds('', chunks), isTrue);
    });

    test('un solo carácter da un fragmento de esa misma longitud', () {
      final chunks = service.chunk('x', kind: RenditionKind.plainText);

      expect(chunks, hasLength(1));
      expect(chunks.single.text, 'x');
      expect(chunkingInvariantHolds('x', chunks), isTrue);
    });

    test('un párrafo gigante sin ningún separador no se parte de más', () {
      final text = 'palabra '.padRight(5000, 'x');

      final chunks = service.chunk(text, kind: RenditionKind.plainText);

      expect(chunks, hasLength(1));
      expect(chunkingInvariantHolds(text, chunks), isTrue);
    });
  });
}
