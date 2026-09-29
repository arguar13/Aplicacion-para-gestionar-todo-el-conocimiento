import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/bibliography_builder.dart';
import 'package:sinapsis/features/citations/domain/services/styles/apa7_style.dart';
import 'package:sinapsis/features/export/data/exporters/docx_exporter.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/transform/data/documents/docx_parser.dart';

import '../../../../support/document_parsing.dart';
import '../../../../support/sample_knowledge_item.dart';

void main() {
  const exporter = DocxExporter();

  group('formato', () {
    test('es .docx', () {
      expect(exporter.format, ExportFormat.docx);
    });
  });

  group('nombre de archivo', () {
    test('usa el título saneado con extensión .docx', () {
      final item = sampleKnowledgeItem(title: 'Título: con / caracteres?');

      expect(exporter.suggestedFileName(item), endsWith('.docx'));
      expect(exporter.suggestedFileName(item), isNot(contains('/')));
    });
  });

  group('cuerpo', () {
    // La prueba más fuerte de que esto es un `.docx` de verdad —y no algo
    // que solo se le parece— es que el propio `DocxParser` del proyecto,
    // pensado para leer documentos de Word de verdad, lo pueda leer.
    Future<String> exportAndReadBack(KnowledgeItem item) async {
      final bytes = await exporter.export(item);
      final parsed = await const DocxParser().parseBytes(bytes);
      return parsed.markdown;
    }

    test('trae el título', () async {
      final markdown = await exportAndReadBack(sampleKnowledgeItem());

      expect(
        markdown,
        contains('La estructura de las revoluciones científicas'),
      );
    });

    test('trae el subtítulo y las notas', () async {
      final item = sampleKnowledgeItem(notes: 'Una nota de ejemplo.');
      final markdown = await exportAndReadBack(item);

      expect(markdown, contains('Thomas Kuhn'));
      expect(markdown, contains('Una nota de ejemplo.'));
    });

    test('trae el contenido de las formas de texto, por párrafo', () async {
      final item = sampleKnowledgeItem(
        renditions: [
          sampleTextRendition('Primer párrafo.\n\nSegundo párrafo.'),
        ],
      );
      final markdown = await exportAndReadBack(item);

      expect(markdown, contains('Primer párrafo.'));
      expect(markdown, contains('Segundo párrafo.'));
    });

    test('sin contenido extraído, lo dice', () async {
      final markdown = await exportAndReadBack(sampleKnowledgeItem());

      expect(markdown, contains('Sin contenido extraído todavía.'));
    });

    test('trae la procedencia: fecha, fuente y autor', () async {
      final markdown = await exportAndReadBack(sampleKnowledgeItem());

      expect(markdown, contains('Guardado el 2026-09-11'));
      expect(markdown, contains('https://ejemplo.org/kuhn'));
      expect(markdown, contains('Thomas Kuhn'));
    });

    test('con una bibliografía, la agrega al pie', () async {
      final bibliography = buildBibliography([
        BibliographySource(
          itemId: 'f1',
          source: CitationSource(
            title: 'Un libro citado',
            reference: const ReferenceData(
              type: ReferenceType.book,
              contributors: [Contributor(name: PersonName(family: 'García'))],
              publisher: 'Editorial',
            ),
            date: PublicationDate.ofYear(2020),
          ),
        ),
      ], style: const Apa7Style());

      final bytes = await exporter.export(
        sampleKnowledgeItem(),
        bibliography: bibliography,
      );
      final markdown = (await const DocxParser().parseBytes(bytes)).markdown;

      expect(markdown, contains('Referencias'));
      expect(markdown, contains('García'));
      expect(
        markdown.indexOf('Guardado el'),
        lessThan(markdown.indexOf('Referencias')),
      );
    });

    test('sin bibliografía, no agrega la sección', () async {
      final markdown = await exportAndReadBack(sampleKnowledgeItem());

      expect(markdown, isNot(contains('Referencias')));
    });
  });
}
