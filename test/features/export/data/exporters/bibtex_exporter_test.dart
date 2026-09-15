import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/export/data/exporters/bibtex_exporter.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';

import '../../../../support/sample_knowledge_item.dart';

void main() {
  const exporter = BibtexExporter();

  Future<String> exportToString(KnowledgeItem item) async =>
      utf8.decode(await exporter.export(item));

  group('formato', () {
    test('es BibTeX', () {
      expect(exporter.format, ExportFormat.bibtex);
    });
  });

  group('nombre de archivo', () {
    test('usa el título saneado con extensión .bib', () {
      final item = sampleKnowledgeItem(title: 'Título: con / caracteres?');

      expect(exporter.suggestedFileName(item), endsWith('.bib'));
      expect(exporter.suggestedFileName(item), isNot(contains('/')));
    });
  });

  group('cuerpo', () {
    test('trae el título, el autor y la URL del elemento', () async {
      // Los valores por defecto de `sampleKnowledgeItem` ya son estos.
      final text = await exportToString(sampleKnowledgeItem());

      expect(
        text,
        contains(
          'title = {La estructura de las revoluciones científicas}',
        ),
      );
      expect(text, contains('author = {Thomas Kuhn}'));
      expect(text, contains('url = {https://ejemplo.org/kuhn}'));
    });

    test('con un enlace, es una entrada @online', () async {
      final text = await exportToString(sampleKnowledgeItem());

      expect(text, startsWith('@online{'));
    });
  });
}
