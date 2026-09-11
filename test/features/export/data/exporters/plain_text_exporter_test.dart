import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/export/data/exporters/plain_text_exporter.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';

import '../../../../support/sample_knowledge_item.dart';

void main() {
  const exporter = PlainTextExporter();

  Future<String> exportToString(KnowledgeItem item) async =>
      utf8.decode(await exporter.export(item));

  group('formato', () {
    test('es texto plano', () {
      expect(exporter.format, ExportFormat.plainText);
    });
  });

  group('nombre de archivo', () {
    test('usa el título saneado con extensión .txt', () {
      final item = sampleKnowledgeItem(title: 'Título: con / caracteres?');

      expect(exporter.suggestedFileName(item), endsWith('.txt'));
      expect(exporter.suggestedFileName(item), isNot(contains('/')));
      expect(exporter.suggestedFileName(item), isNot(contains(':')));
    });
  });

  group('cuerpo', () {
    test('el título va subrayado con signos igual, del mismo largo', () async {
      final text = await exportToString(
        sampleKnowledgeItem(title: 'Un título'),
      );

      expect(text, startsWith('Un título\n${'=' * 'Un título'.length}\n'));
    });

    test('el subtítulo va en su propia línea, sin marcado', () async {
      final text = await exportToString(
        sampleKnowledgeItem(subtitle: 'Un subtítulo'),
      );

      expect(text, contains('\nUn subtítulo\n'));
    });

    test('sin subtítulo no deja una línea vacía de más', () async {
      final withSubtitle = await exportToString(
        sampleKnowledgeItem(subtitle: 'Algo'),
      );
      final withoutSubtitle = await exportToString(
        sampleKnowledgeItem(subtitle: null),
      );

      expect(withoutSubtitle.length, lessThan(withSubtitle.length));
    });

    test('las notas se escriben tal cual, sin marcado', () async {
      final text = await exportToString(
        sampleKnowledgeItem(notes: 'Una nota\ncon dos líneas'),
      );

      expect(text, contains('Una nota\ncon dos líneas'));
    });

    test('el contenido de las formas de texto llega entero', () async {
      final text = await exportToString(
        sampleKnowledgeItem(
          renditions: [sampleTextRendition('El cuerpo del artículo.')],
        ),
      );

      expect(text, contains('El cuerpo del artículo.'));
    });

    test('no interpreta el Markdown: los símbolos quedan tal cual', () async {
      final text = await exportToString(
        sampleKnowledgeItem(
          renditions: [sampleTextRendition('# Un título\n\n**negrita**')],
        ),
      );

      expect(text, contains('# Un título'));
      expect(text, contains('**negrita**'));
    });

    test(
      'sin ninguna forma de texto, lo dice en vez de dejarlo en blanco',
      () async {
        final text = await exportToString(sampleKnowledgeItem());

        expect(text, contains('Sin contenido extraído todavía.'));
      },
    );
  });

  group('pie de procedencia', () {
    test('repite la fecha, la fuente y el autor en texto corriente', () async {
      final text = await exportToString(
        sampleKnowledgeItem(
          capturedAt: DateTime(2026, 9, 11),
          url: 'https://ejemplo.org/a',
          authorName: 'Ada Lovelace',
        ),
      );

      expect(text, contains('Guardado el 2026-09-11.'));
      expect(text, contains('Fuente: https://ejemplo.org/a'));
      expect(text, contains('Autor: Ada Lovelace'));
    });

    test('si hay perfil de autor, usa el perfil y no el nombre', () async {
      final text = await exportToString(
        sampleKnowledgeItem(
          authorName: 'Ada Lovelace',
          authorUrl: 'https://ejemplo.org/ada',
        ),
      );

      expect(text, contains('Autor: https://ejemplo.org/ada'));
      expect(text, isNot(contains('Autor: Ada Lovelace')));
    });
  });
}
