import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';

void main() {
  final now = DateTime(2026, 9, 11, 10);

  group('Rendition.searchableText', () {
    test('un texto plano se busca tal cual', () {
      final rendition = Rendition.text(
        id: 'r-1',
        itemId: 'item-1',
        kind: RenditionKind.plainText,
        content: 'contenido de prueba',
        isPrimary: true,
        createdAt: now,
      );

      expect(rendition.searchableText, 'contenido de prueba');
    });

    test('una nota de bloques se busca por el texto de cada bloque, no por '
        'el JSON crudo', () {
      final content = encodeContentBlocks(const [
        ContentBlock.heading(text: 'Un título con enzimas'),
        ContentBlock.paragraph(text: 'que catalizan reacciones'),
      ]);

      final rendition = Rendition.text(
        id: 'r-1',
        itemId: 'item-1',
        kind: RenditionKind.blocks,
        content: content,
        isPrimary: true,
        createdAt: now,
      );

      expect(
        rendition.searchableText,
        'Un título con enzimas\nque catalizan reacciones',
      );
      // Ninguna clave de la estructura JSON debería colarse en lo
      // buscable: si "type" o "level" aparecieran acá, una búsqueda de
      // "heading" encontraría cualquier nota de bloques, sin importar
      // qué escribió el usuario.
      expect(rendition.searchableText, isNot(contains('type')));
      expect(rendition.searchableText, isNot(contains('level')));
    });

    test('una forma de archivo no tiene texto buscable', () {
      final rendition = Rendition.file(
        id: 'r-1',
        itemId: 'item-1',
        kind: RenditionKind.pdf,
        relativePath: 'originales/x/y.pdf',
        isPrimary: true,
        createdAt: now,
      );

      expect(rendition.searchableText, isNull);
    });
  });
}
