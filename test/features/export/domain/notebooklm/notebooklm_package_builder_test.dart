import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter.dart';
import 'package:sinapsis/features/export/domain/notebooklm/notebooklm_package_builder.dart';

import '../../../../support/sample_knowledge_item.dart';

/// Exportador de mentira: el nombre y el contenido salen los dos del título,
/// para poder comprobar cómo el armador resuelve los nombres repetidos sin
/// depender de cómo escribe de verdad ningún exportador real.
class _FakeExporter implements Exporter {
  const _FakeExporter();

  @override
  ExportFormat get format => ExportFormat.markdown;

  @override
  String suggestedFileName(KnowledgeItem item) => '${item.title}.md';

  @override
  Future<Uint8List> export(KnowledgeItem item) async =>
      Uint8List.fromList(utf8.encode('contenido de ${item.title}'));
}

void main() {
  const builder = NotebookLmPackageBuilder(exporter: _FakeExporter());

  test('un archivo por elemento, más el índice', () async {
    final files = await builder.build([
      sampleKnowledgeItem(title: 'Uno'),
      sampleKnowledgeItem(title: 'Dos'),
    ]);

    expect(files.keys, containsAll(['Uno.md', 'Dos.md']));
    expect(
      files,
      containsPair(NotebookLmPackageBuilder.indexFileName, isA<Uint8List>()),
    );
    expect(files, hasLength(3));
  });

  test('el nombre del índice ordena primero en cualquier explorador', () {
    expect(NotebookLmPackageBuilder.indexFileName, startsWith('00'));
  });

  test(
    'el contenido de cada archivo es el que produce el exportador',
    () async {
      final files = await builder.build([sampleKnowledgeItem(title: 'Uno')]);

      expect(utf8.decode(files['Uno.md']!), 'contenido de Uno');
    },
  );

  test('el índice menciona a NotebookLM y enlaza cada archivo', () async {
    final files = await builder.build([
      sampleKnowledgeItem(title: 'Un artículo'),
    ]);
    final index = utf8.decode(files[NotebookLmPackageBuilder.indexFileName]!);

    expect(index, contains('notebooklm.google.com'));
    expect(index, contains('[Un artículo](Un artículo.md)'));
  });

  test('el índice cuenta los elementos, en singular o en plural', () async {
    final unico = await builder.build([sampleKnowledgeItem(title: 'Solo')]);
    final varios = await builder.build([
      sampleKnowledgeItem(title: 'Uno'),
      sampleKnowledgeItem(title: 'Dos'),
    ]);

    expect(
      utf8.decode(unico[NotebookLmPackageBuilder.indexFileName]!),
      contains('1 elemento '),
    );
    expect(
      utf8.decode(varios[NotebookLmPackageBuilder.indexFileName]!),
      contains('2 elementos '),
    );
  });

  test(
    'sin elementos, el paquete es solo el índice, vacío de contenido',
    () async {
      final files = await builder.build([]);

      expect(files.keys, [NotebookLmPackageBuilder.indexFileName]);
    },
  );

  group('nombres repetidos', () {
    test('dos elementos con el mismo título no se pisan', () async {
      final files = await builder.build([
        sampleKnowledgeItem(title: 'Repetido'),
        sampleKnowledgeItem(title: 'Repetido'),
      ]);

      expect(files.keys, containsAll(['Repetido.md', 'Repetido (2).md']));
      expect(files, hasLength(3));
      expect(utf8.decode(files['Repetido.md']!), 'contenido de Repetido');
      expect(utf8.decode(files['Repetido (2).md']!), 'contenido de Repetido');
    });

    test('tres repetidos siguen contando: (2), (3)', () async {
      final files = await builder.build(
        List.generate(3, (_) => sampleKnowledgeItem(title: 'Igual')),
      );

      expect(
        files.keys,
        containsAll(['Igual.md', 'Igual (2).md', 'Igual (3).md']),
      );
    });

    test(
      'un elemento que se llamaría igual que el índice no lo pisa',
      () async {
        // El exportador de mentira usa el título tal cual: uno llamado
        // "00-indice" produce justo el mismo nombre que el archivo índice.
        final files = await builder.build([
          sampleKnowledgeItem(title: '00-indice'),
        ]);

        expect(
          utf8.decode(files[NotebookLmPackageBuilder.indexFileName]!),
          contains('## Contenido'),
        );
        expect(files.keys, contains('00-indice (2).md'));
      },
    );
  });
}
