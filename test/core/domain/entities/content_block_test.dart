import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';

void main() {
  group('encodeContentBlocks / decodeContentBlocks', () {
    test('un párrafo hace el viaje de ida y vuelta sin cambios', () {
      const blocks = [ContentBlock.paragraph(text: 'Hola mundo')];

      final decoded = decodeContentBlocks(encodeContentBlocks(blocks));

      expect(decoded, blocks);
    });

    test('cada tipo de bloque conserva sus datos propios', () {
      const blocks = [
        ContentBlock.heading(text: 'Título', level: 2),
        ContentBlock.bulletItem(text: 'primer ítem'),
        ContentBlock.numberedItem(text: 'segundo ítem'),
        ContentBlock.checklistItem(text: 'por hacer', checked: true),
        ContentBlock.quote(text: 'una cita'),
      ];

      final decoded = decodeContentBlocks(encodeContentBlocks(blocks));

      expect(decoded, blocks);
    });

    test('el orden de los bloques se conserva', () {
      const blocks = [
        ContentBlock.paragraph(text: 'primero'),
        ContentBlock.paragraph(text: 'segundo'),
        ContentBlock.paragraph(text: 'tercero'),
      ];

      final decoded = decodeContentBlocks(encodeContentBlocks(blocks));

      expect(decoded.map((b) => b.text), ['primero', 'segundo', 'tercero']);
    });

    test('una lista vacía codifica y decodifica a otra lista vacía', () {
      expect(decodeContentBlocks(encodeContentBlocks(const [])), isEmpty);
    });

    test('un tipo desconocido —de una versión futura— se lee como párrafo, '
        'no rompe la nota entera', () {
      final decoded = decodeContentBlocks(
        '[{"type": "tabla-del-futuro", "text": "contenido rescatado"}]',
      );

      expect(decoded, [
        const ContentBlock.paragraph(text: 'contenido rescatado'),
      ]);
    });

    test('un encabezado sin nivel explícito cae en nivel 1', () {
      final decoded = decodeContentBlocks('[{"type": "heading", "text": "x"}]');

      expect(decoded, [const ContentBlock.heading(text: 'x')]);
    });

    test('un casillero sin "checked" explícito cae en sin marcar', () {
      final decoded = decodeContentBlocks(
        '[{"type": "checklistItem", "text": "x"}]',
      );

      expect(decoded, [const ContentBlock.checklistItem(text: 'x')]);
    });
  });

  group('ContentBlock.text', () {
    test('devuelve el texto propio de cada variante', () {
      expect(const ContentBlock.paragraph(text: 'a').text, 'a');
      expect(const ContentBlock.heading(text: 'b').text, 'b');
      expect(const ContentBlock.bulletItem(text: 'c').text, 'c');
      expect(const ContentBlock.numberedItem(text: 'd').text, 'd');
      expect(const ContentBlock.checklistItem(text: 'e').text, 'e');
      expect(const ContentBlock.quote(text: 'f').text, 'f');
    });
  });
}
